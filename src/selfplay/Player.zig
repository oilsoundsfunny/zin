const bounded_array = @import("bounded_array");
const engine = @import("engine");
const root = @import("root");
const std = @import("std");
const types = @import("types");

const viri = @import("viri.zig");

const Self = @This();

const random_ply = 8;
const random_games = 4;

const max_cp = 400;

pool:	engine.search.Pool,
prng:	std.Random.Sfc64,
opening:	[]const u8 = &.{},

games:	?usize,
played:	 usize,

data:	viri.Self,
line:	bounded_array.BoundedArray(viri.Move.Scored, 1024),

pub const Tourney = struct {
	allocator:	std.mem.Allocator,
	players:	[]Self,
	threads:	[]std.Thread,

	pub const Options = struct {
		allocator:	std.mem.Allocator,
		io:	*types.Io,
		tt:	*engine.transposition.Table,
		games:	?usize,
		depth:	?engine.search.Depth,
		nodes:	?usize,
		threads:	usize,
	};

	pub fn deinit(self: *Tourney) void {
		self.allocator.free(self.players);
		self.allocator.free(self.threads);

		self.players = undefined;
		self.threads = undefined;
	}

	pub fn init(options: Options) !Tourney {
		if (options.depth == null and options.nodes == null) {
			std.process.fatal("missing args '{s}' and '{s}'", .{"--depth", "--nodes"});
		} else if (options.threads == 0) {
			std.process.fatal("bad thread count: {d}", .{options.threads});
		}

		const self: Tourney = .{
			.allocator = options.allocator,
			.players = try options.allocator.alloc(Self, options.threads),
			.threads = try options.allocator.alloc(std.Thread, options.threads),
		};

		for (self.players) |*player| {
			const i = player[0 .. 1].ptr - self.players.ptr;
			const n = options.threads;

			const io = options.io;
			const tt = options.tt;

			player.* = .{
				.pool = try @TypeOf(player.pool).init(self.allocator, 1, true, io, tt),
				.prng = std.Random.Sfc64.init(0xaaaaaaaaaaaaaaaa),
				.opening = undefined,

				.games = if (options.games) |lim| lim / n + @intFromBool(i < lim % n) else null,
				.played = 0,

				.data = .{},
				.line = .{
					.buffer = .{@as(viri.Move.Scored, .{})} ** 1024,
					.len = 0,
				},
			};

			try player.pool.reset();
			player.pool.options.infinite = false;
			player.pool.options.depth = options.depth;
			player.pool.options.nodes = options.nodes;
		}

		return self;
	}

	pub fn start(self: *Tourney) !void {
		for (self.players, self.threads) |*player, *thread| {
			thread.* = try std.Thread.spawn(.{.allocator = self.allocator}, match, .{player});
		}
	}

	pub fn stop(self: *const Tourney) void {
		for (self.threads) |thread| {
			std.Thread.join(thread);
		}
	}
};

fn readOpening(self: *Self) !void {
	self.pool.io.lockReader();
	defer self.pool.io.unlockReader();

	const reader = self.pool.io.reader();
	const line = try reader.takeDelimiterInclusive('\n');
	self.opening = try self.pool.allocator.dupe(u8, line);
}

fn writeData(self: *Self) !void {
	self.pool.io.lockWriter();
	defer self.pool.io.unlockWriter();

	const writer = self.pool.io.writer();
	try writer.writeAll(std.mem.asBytes(&self.data));
	for (self.line.constSlice()) |sm| {
		try writer.writeAll(std.mem.asBytes(&sm));
	}
	try writer.flush();
}

fn playRandom(self: *Self) !void {
	const threads = self.pool.threads;
	const thread = &threads[0];

	var pos = thread.pos;
	var ply: usize = 0;
	defer thread.pos = pos;

	find_line: while (true) : ({
		ply = 0;
		pos = thread.pos;
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
	const threads = self.pool.threads;
	const thread = &threads[0];
	const pos = &thread.pos;

	self.data = viri.Self.fromPosition(pos);
	self.line = try @TypeOf(self.line).init(0);

	while (true) {
		try self.pool.start();
		self.pool.waitStop();

		const root_moves = &thread.root_moves;
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
		defer self.pool.allocator.free(self.opening);

		const played = self.played;
		const games = self.games orelse std.math.maxInt(usize);

		while (self.played - played < random_games and self.played < games) {
			self.playRandom() catch |err| {
				std.debug.panic("error: {s} @ game {d}", .{@errorName(err), self.played});
				return err;
			};

			self.playOut() catch |err| {
				std.debug.panic("error: {s} @ game {d}", .{@errorName(err), self.played});
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
