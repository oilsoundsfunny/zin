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
		depth:	?engine.search.Depth,
		nodes:	?usize,
		threads:	usize,
	};

	pub fn alloc(options: Options) !Tourney {
		if (options.depth == null and options.nodes == null) {
			std.process.fatal("missing args '{s}' and '{s}'", .{"--depth", "--nodes"});
		} else if (options.threads == 0) {
			std.process.fatal("invalid thread count: {d}", .{options.threads});
		}

		var self: Tourney = .{};
		try self.players.appendNTimes(base.heap.allocator, undefined, options.threads);
		try self.threads.appendNTimes(base.heap.allocator, undefined, options.threads);

		for (self.players.items, 0 ..) |*player, i| {
			const n = options.threads;
			player.* = std.mem.zeroInit(Self, .{
				.games = if (options.games) |g| g / n + @intFromBool(i < g % n) else null,
				.index = i,
			});

			try player.instance.alloc(1);
			player.instance.options.infinite = false;
			player.instance.options.depth = options.depth;
			player.instance.options.nodes = options.nodes;
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

fn playOut(self: *Self) !void {
	std.debug.assert(self.instance.infos.len == 1);
	const infos = self.instance.infos;
	const info = &infos[0];
	const pos = &info.pos;
	const root_moves = &info.root_moves;

	self.data = viri.Self.fromPosition(pos);
	self.line = try @TypeOf(self.line).init(0);

	var ply: usize = 0;
	while (true) : (ply += 1) {
		if (ply >= random_ply) {
			try self.instance.start();
			self.instance.waitStop();
		} else {
			root_moves.* = engine.movegen.Move.Root.List.init(pos);
		}

		const rms = root_moves.constSlice();
		const rmn = rms.len;

		if (rmn == 0 or pos.isDrawn()) {
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

		const i = self.prng.random().uintLessThan(usize, @max(rmn, 2) / 2);
		const rm = &rms[i];
		const pvm = rm.constSlice()[0];
		const pvs = rm.score;
		try pos.doMove(pvm);

		if (ply >= random_ply) {
			const m = viri.Move.fromMove(pvm);
			const s = engine.evaluation.score.toCentipawns(@intCast(pvs));
			try self.line.append(.{
				.move = m,
				.score = @intCast(s),
			});
		}
	}
}

fn match(self: *Self) !void {
	while (self.readOpening()) {
		defer base.heap.allocator.free(self.opening);

		const played = self.played;
		const games = if (self.games) |g| g else std.math.maxInt(usize);

		while (self.played - played < random_games and self.played < games) {
			self.playOut() catch |err| {
				std.debug.panic("error: {s} @ player {d}, game {d}",
				  .{@errorName(err), self.index, self.played});
				return err;
			};

			defer self.played += 1;
			try self.writeData();
		}
	} else |err| switch (err) {
		error.EndOfStream => {},
		else => return err,
	}
}
