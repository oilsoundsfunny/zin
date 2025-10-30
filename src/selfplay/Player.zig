const base = @import("base");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const root = @import("root");
const std = @import("std");

const viri = @import("viri.zig");

const Self = @This();

const random_ply = 8;
const random_games = 4;

const max_cp = 400;
const min_cp = 0;

instance:	engine.search.Instance,
opening:	[]const u8 = &.{},

filter_draws:	bool,
random:	bool,
prng:	std.Random.Xoroshiro128 = std.Random.Xoroshiro128.init(0xaaaaaaaaaaaaaaaa),

games:	?usize,
played:	 usize,
index:	 usize,

data:	viri.Self,
line:	bounded_array.BoundedArray(viri.Move.Scored, 1024),

pub const Tourney = struct {
	players:	std.ArrayListAligned(Self, .@"64") = .{},
	threads:	std.ArrayListAligned(std.Thread, .@"64") = .{},

	pub const Options = struct {
		games:	?usize,
		depth:	?u8,
		nodes:	?usize,
		threads:	usize,

		filter_draws:	bool,
		random:	 		bool,
	};

	pub fn alloc(options: Options) !Tourney {
		if (!options.random
		  and options.depth == null
		  and options.nodes == null) {
			std.process.fatal("missing args '{s}' and '{s}'", .{"--depth", "--nodes"});
		}
		if (options.threads == 0) {
			std.process.fatal("get some real threads vro :wilted_rose:", .{});
		}

		var self: Tourney = .{};
		try self.players.appendNTimes(base.heap.allocator, undefined, options.threads);
		try self.threads.appendNTimes(base.heap.allocator, undefined, options.threads);

		for (self.players.items, 0 ..) |*player, i| {
			const n = options.threads;
			player.* = std.mem.zeroInit(Self, .{
				.filter_draws = options.filter_draws,
				.random = options.random,

				.games = if (options.games) |g| g / n + @intFromBool(i < g % n) else null,
				.index = i,
			});

			try player.instance.alloc(1);
			player.instance.options.infinite = false;
			player.instance.options.depth = if (options.random) options.depth orelse 0 else null;
			player.instance.options.nodes = if (options.random) options.nodes orelse 0 else null;
		}

		return self;
	}

	pub fn start(self: *Tourney) !void {
		for (self.players.items, self.threads.items) |*player, *thread| {
			thread.* = try std.Thread.spawn(.{.allocator = base.heap.allocator}, match, .{player});
		}
	}

	pub fn stop(self: *const Tourney) void {
		for (self.threads.items) |thread| {
			std.Thread.join(thread);
		}
	}
};

fn readOpening(self: *Self) !void {
	root.io.reader_mtx.lock();
	defer root.io.reader_mtx.unlock();

	const reader = &root.io.book_reader.interface;
	const line = try reader.takeDelimiterInclusive('\n');
	const copy = try base.heap.allocator.dupe(u8, line);
	self.opening = copy;
}

fn writeData(self: *Self) !void {
	root.io.writer_mtx.lock();
	defer root.io.writer_mtx.unlock();

	const writer = &root.io.data_writer.interface;
	try writer.writeAll(std.mem.asBytes(&self.data));
	for (self.line.constSlice()) |sm| {
		try writer.writeAll(std.mem.asBytes(&sm));
	}
	try writer.flush();
}

fn playRandom(self: *Self) !void {
	std.debug.assert(self.instance.infos.len == 1);
	const infos = self.instance.infos;
	const info = &infos[0];
	try info.pos.parseFen(self.opening);

	const original_depth = self.instance.options.depth;
	self.instance.options.depth = 1;
	defer self.instance.options.depth = original_depth;

	var pos = info.pos;

	find_line: while (true) : (pos = info.pos) {
		for (0 .. random_ply) |_| {
			const rml = engine.movegen.Move.Root.List.init(&pos);
			const rms = rml.constSlice();
			if (rms.len == 0 or pos.isDrawn()) {
				continue :find_line;
			}

			const r = self.prng.random().uintLessThan(usize, rms.len);
			const m = rms[r].constSlice()[0];
			try pos.doMove(m);
		}

		const ev = engine.evaluation.score.fromPosition(&pos);
		const cp = engine.evaluation.score.toCentipawns(ev);
		const abs = if (cp < 0) -cp else cp;

		if (abs != std.math.clamp(abs, min_cp, max_cp)) {
			continue :find_line;
		}

		const rml = engine.movegen.Move.Root.List.init(&pos);
		const rms = rml.constSlice();
		if (rms.len == 0 or pos.isDrawn()) {
			continue :find_line;
		}

		info.pos = pos;
		break :find_line;
	}
}

fn playOut(self: *Self) !void {
	std.debug.assert(self.instance.infos.len == 1);
	const infos = self.instance.infos;
	const info = &infos[0];
	const pos = &info.pos;

	self.data = viri.Self.fromPosition(pos);
	self.line = try @TypeOf(self.line).init(0);

	while (true) {
		try self.instance.start();
		self.instance.waitStop();

		const rml = info.result.pv;
		const rms = rml.constSlice();
		if (rms.len == 0 or pos.isDrawn()) {
			const is_checked = pos.isChecked();
			const is_drawn = pos.isDrawn();
			const stm = pos.stm;

			defer self.data.result = if (!is_checked or is_drawn) .draw else switch (stm) {
				.white => .black,
				.black => .white,
			};
			try self.line.append(.{});
			break;
		}

		const i = if (!self.random or rms.len <= 2) 0
		  else self.prng.random().uintLessThan(usize, rms.len / 2);
		const rm = &rms[i];
		const pvm = rm.constSlice()[0];
		const pvs = rm.score;
		try pos.doMove(pvm);

		const m = viri.Move.fromMove(pvm);
		const s = engine.evaluation.score.toCentipawns(@intCast(pvs));
		try self.line.append(.{
			.move = m,
			.score = @intCast(s),
		});
	}
}

fn match(self: *Self) !void {
	while (self.readOpening()) {
		defer base.heap.allocator.free(self.opening);

		const played = self.played;
		const games = if (self.games) |g| g else std.math.maxInt(usize);

		while (self.played - played < random_games and self.played < games) {
			self.playRandom() catch |err| {
				std.debug.panic("error: {s} @ player {d}, game {d}",
				  .{@errorName(err), self.index, self.played});
				return err;
			};
			self.playOut() catch |err| {
				std.debug.panic("error: {s} @ player {d}, game {d}",
				  .{@errorName(err), self.index, self.played});
				return err;
			};

			if (self.filter_draws and self.data.result == .draw) {
				continue;
			}

			defer self.played += 1;
			try self.writeData();
		}
	} else |err| switch (err) {
		error.EndOfStream => {},
		else => return err,
	}
}
