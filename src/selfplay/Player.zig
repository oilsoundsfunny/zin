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

instance:	engine.search.Instance,

io:	*base.Io,
opening:	[]const u8 = &.{},
prng:	std.Random.Xoroshiro128 = std.Random.Xoroshiro128.init(0xaaaaaaaaaaaaaaaa),

games:	?usize,
played:	 usize,
index:	 usize,

data:	viri.Self,
line:	bounded_array.BoundedArray(viri.Move.Scored, 1024),

pub const Tourney = struct {
	players:	std.ArrayList(Self) = .{},
	threads:	std.ArrayList(std.Thread) = .{},

	pub const Options = struct {
		io:	*base.Io,
		games:	?usize,
		depth:	?engine.search.Depth,
		nodes:	?usize,
		threads:	usize,
	};

	pub fn init(options: Options) !Tourney {
		if (options.depth == null and options.nodes == null) {
			std.process.fatal("missing args '{s}' and '{s}'", .{"--depth", "--nodes"});
		} else if (options.threads == 0) {
			std.process.fatal("bad thread count: {d}", .{options.threads});
		}

		var self: Tourney = .{};
		try self.players.appendNTimes(base.heap.allocator, undefined, options.threads);
		try self.threads.appendNTimes(base.heap.allocator, undefined, options.threads);

		for (self.players.items, 0 ..) |*player, i| {
			const n = options.threads;
			player.* = std.mem.zeroInit(Self, .{
				.io = options.io,
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
	self.io.lockReader();
	defer self.io.unlockReader();

	const line = try self.io.reader().takeDelimiterInclusive('\n');
	self.opening = try base.heap.allocator.dupe(u8, line);
}

fn writeData(self: *Self) !void {
	self.io.lockWriter();
	defer self.io.unlockWriter();

	try self.io.writer().writeAll(std.mem.asBytes(&self.data));
	for (self.line.constSlice()) |sm| {
		try self.io.writer().writeAll(std.mem.asBytes(&sm));
	}
	try self.io.writer().flush();
}

fn playRandom(self: *Self) !void {
	const infos = self.instance.infos;
	const info = &infos[0];

	var pos = info.pos;
	var ply: usize = 0;
	defer info.pos = pos;

	find_line: while (true) : ({
		ply = 0;
		pos = info.pos;
	}) {
		while (ply <= random_ply) : (ply += 1) {
			const root_moves = engine.movegen.Move.Root.List.init(&pos);
			const rms = root_moves.constSlice();
			const rmn = rms.len;
			if (rmn == 0) {
				continue :find_line;
			}

			if (ply < random_ply) {
				const i = self.prng.random().uintLessThan(usize, rmn);
				const m = rms[i].constSlice()[0];
				pos.doMove(m) catch continue :find_line;
			} else {
				const ev = pos.evaluate();
				const cp = engine.evaluation.score.centipawns(ev);
				if (cp < -max_cp or cp > max_cp) {
					continue :find_line;
				}
			}
		} else break :find_line;
	}
}

fn playOut(self: *Self) !void {
	const infos = self.instance.infos;
	const info = &infos[0];
	const pos = &info.pos;

	self.data = viri.Self.fromPosition(pos);
	self.line = try @TypeOf(self.line).init(0);

	while (true) {
		try self.instance.start();
		self.instance.waitStop();

		const root_moves = &info.root_moves;
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

		const pv = &rms[0];
		const pvm = pv.constSlice()[0];
		const pvs = pv.score;
		try pos.doMove(pvm);

		const m = viri.Move.fromMove(pvm);
		const s = engine.evaluation.score.centipawns(@intCast(pvs));
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

			defer self.played += 1;
			try self.writeData();
		}
	} else |err| switch (err) {
		error.EndOfStream => {},
		else => return err,
	}
}
