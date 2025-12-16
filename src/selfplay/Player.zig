const bounded_array = @import("bounded_array");
const engine = @import("engine");
const root = @import("root");
const std = @import("std");
const types = @import("types");

const viri = @import("viri.zig");

const Player = @This();

const max_cp = 400;

idx:	usize,
cnt:	usize,

pool:	engine.search.Pool,
prng:	std.Random.Xoroshiro128,
opening:	[]const u8,

games:	?usize,
ply:	 usize,
repeat:	 usize,
played:	 usize,

data:	viri.Self,
line:	bounded_array.BoundedArray(viri.Move.Scored, 1024),

pub const Tourney = struct {
	allocator:	std.mem.Allocator,
	players:	[]Player,
	threads:	[]std.Thread,

	pub const Options = struct {
		allocator:	std.mem.Allocator,
		io:	*types.Io,
		tt:	*engine.transposition.Table,
		games:	?usize,
		ply:	?usize,
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

		const tourney: Tourney = .{
			.allocator = options.allocator,
			.players = try options.allocator.alloc(Player, options.threads),
			.threads = try options.allocator.alloc(std.Thread, options.threads),
		};
		const line_n = try options.io.lineCount();

		for (tourney.players, 0 ..) |*player, i| {
			const io = options.io;
			const tt = options.tt;

			const n = options.threads;
			const games = if (options.games) |g| g / n + @intFromBool(i < g % n) else null;
			const repeat = if (options.games) |g| g / line_n + @intFromBool(g % line_n != 0) else 1;
			const ply = options.ply orelse 4;

			player.* = .{
				.idx = i,
				.cnt = n,

				.pool = try @TypeOf(player.pool).init(tourney.allocator, 1, true, io, tt),
				.prng = std.Random.Xoroshiro128.init(0xaaaaaaaaaaaaaaaa),
				.opening = undefined,

				.games = games,
				.ply = ply,
				.repeat = repeat,
				.played = 0,

				.data = .{},
				.line = .{
					.buffer = .{@as(viri.Move.Scored, .{})} ** 1024,
					.len = 0,
				},
			};

			try player.pool.reset();
			player.pool.options.depth = options.depth;
			player.pool.options.nodes = options.nodes;
		}

		return tourney;
	}

	pub fn spawn(self: *Tourney) !void {
		for (self.players, self.threads) |*player, *thread| {
			thread.* = try std.Thread.spawn(.{.allocator = self.allocator}, match, .{player});
		}
	}

	pub fn join(self: *Tourney) void {
		for (self.threads) |*thread| {
			std.Thread.join(thread.*);
			thread.* = undefined;
		}
	}
};

fn readOpening(self: *Player) !void {
	self.pool.io.lockReader();
	defer self.pool.io.unlockReader();

	const line = try self.pool.io.reader().takeDelimiterInclusive('\n');
	self.opening = try self.pool.allocator.dupe(u8, line);
}

fn writeData(self: *Player) !void {
	self.pool.io.lockWriter();
	defer self.pool.io.unlockWriter();

	const writer = self.pool.io.writer();
	try writer.writeAll(std.mem.asBytes(&self.data));
	for (self.line.constSlice()) |sm| {
		try writer.writeAll(std.mem.asBytes(&sm));
	}

	if (writer.buffer.len - writer.buffered().len < 4096) {
		try writer.flush();
	}
}

fn playRandom(self: *Player) !void {
	const threads = self.pool.threads;
	const thread = &threads[0];

	var board = thread.board;
	var ply: usize = 0;
	defer thread.board = board;

	while (true) : ({
		ply = 0;
		board = thread.board;
	}) {
		while (ply <= self.ply) : (ply += 1) {
			const root_moves = engine.movegen.Move.Root.List.init(&board);
			const rms = root_moves.constSlice();
			const rmn = rms.len;
			if (rmn == 0) {
				break;
			}

			if (ply < self.ply) {
				const i = self.prng.random().uintLessThan(usize, rmn);
				const m = rms[i].constSlice()[0];
				board.doMove(m) catch break;
			} else {
				const ev = board.evaluate();
				const cp = engine.evaluation.score.normalize(ev, board.top().material());
				if (cp < -max_cp or cp > max_cp) {
					break;
				}
			}
		} else break;
	}
}

fn playOut(self: *Player) !void {
	const threads = self.pool.threads;
	const thread = &threads[0];
	const board = &thread.board;

	self.data = viri.Self.fromPosition(board);
	self.line = try @TypeOf(self.line).init(0);

	while (true) {
		try self.pool.threads[0].search();

		const root_moves = &thread.root_moves;
		const rms = root_moves.constSlice();
		const rmn = rms.len;

		if (rmn == 0) {
			const is_checked = board.top().isChecked();
			const is_drawn = board.isDrawn() or board.isTerminal();
			const stm = board.top().stm;

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
		try board.doMove(pvm);

		const m = viri.Move.fromMove(pvm);
		const s = engine.evaluation.score.normalize(@intCast(pvs), board.top().material());
		try self.line.append(.{
			.move = m,
			.score = @intCast(s),
		});
	}
}

fn match(self: *Player) !void {
	while (self.readOpening()) {
		var board: engine.Board = .{};
		defer self.pool.allocator.free(self.opening);

		board.parseFen(self.opening) catch {
			std.log.err("invalid fen {s} @ worker {d}", .{self.opening, self.idx});
			continue;
		};

		const games = self.games orelse std.math.maxInt(usize);
		const played = self.played;
		const repeat = self.repeat;

		while (self.played < games and self.played - played < repeat) {
			self.pool.setBoard(&board, true);
			self.playRandom() catch |err| {
				std.log.err("error: {s} @ game {d}, worker {d}",
				  .{@errorName(err), self.played, self.idx});
				continue;
			};

			self.playOut() catch |err| {
				std.log.err("error: {s} @ game {d}, worker{d}",
				  .{@errorName(err), self.played, self.idx});
				continue;
			};

			self.writeData() catch |err| {
				std.log.err("failed to write data, error {s}", .{@errorName(err)});
				continue;
			};
			self.played += 1;
		} else if (self.played >= games) {
			break;
		}
	} else |err| switch (err) {
		error.EndOfStream => {},
		else => return err,
	}
}
