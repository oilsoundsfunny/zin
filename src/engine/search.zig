const builtin = @import("builtin");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const timeman = @import("timeman.zig");
const transposition = @import("transposition.zig");
const uci = @import("uci.zig");

pub const Info = struct {
	pos:	Position = .{},
	depth:	u8 = undefined,
	rms:	[]movegen.RootMove = undefined,

	nodes:	u64 = 0,
	tbhits:	u64 = 0,

	bfhist:	HistArray(Hist, 1) = std.mem.zeroes(HistArray(Hist, 1)),
	capthist:	HistArray(Hist, 2) = std.mem.zeroes(HistArray(Hist, 2)),
	conthist:	HistArray(Hist, 2) = std.mem.zeroes(HistArray(Hist, 2)),

	pub const Hist = i16;

	pub const Error = error {
		Uninitialized,
	};

	pub var global: ?[]Info = null;

	fn HistArray(comptime T: type, comptime n: comptime_int) type {
		return switch (n) {
			1 => std.EnumArray(misc.types.Piece, std.EnumArray(misc.types.Square, T)),
			2 => HistArray(HistArray(T, 1), 1),
			else => @compileError("unexpected comptime integer"
			  ++ std.fmt.comptimePrint("{d}", .{n})),
		};
	}

	pub fn isMain(self: *Info) bool {
		const main_info = ofMain() catch return false;
		return self == main_info;
	}
	pub fn ofMain() Error!*Info {
		const all = try ofThreads();
		return &all[0];
	}
	pub fn ofHelpers() Error![]Info {
		const all = try ofThreads();
		return all[1 ..];
	}
	pub fn ofThreads() Error![]Info {
		const all = global orelse return error.Uninitialized;
		return all[0 ..];
	}
};

pub const manager = struct {
	pub var native: ?std.Thread.Handle = null;

	fn func() !void {
		@atomicStore(bool, &timeman.is_searching, true, .monotonic);
		defer @atomicStore(bool, &timeman.is_searching, false, .monotonic);

		const infos = Info.global orelse return error.Uninitialized;
		const stdout = std.io.getStdOut();
		var buffered = std.io.bufferedWriter(stdout.writer());

		const overhead = timeman.overhead orelse 10;
		const stm = infos[0].pos.stm;
		timeman.start = misc.time.read(.ms);
		if (timeman.movetime) |movetime| {
			timeman.stop = timeman.start + movetime - overhead;
		}
		if (timeman.increment.get(stm) != null and timeman.time.get(stm) != null) {
			const inc = timeman.increment.get(stm).?;
			const time = timeman.time.get(stm).?;

			timeman.stop = timeman.start + time / 20 + inc / 2 - overhead;
		}

		const min_depth = 2;
		const max_depth = timeman.depth orelse 240;

		var root_moves = movegen.RootMove.List.fromInfo(&infos[0]);
		for (root_moves.slice()) |*rm| {
			const move = rm.line.constSlice()[0];
			infos[0].pos.doMove(move) catch unreachable;
			defer infos[0].pos.undoMove();

			rm.score = -qs(&infos[0], -evaluation.score.win, -evaluation.score.lose);
		}
		root_moves.sort();

		try print(buffered.writer(), 1, root_moves);
		try buffered.flush();

		const div = root_moves.constSlice().len / infos.len;
		const mod = root_moves.constSlice().len % infos.len;
		var start: usize = 0;
		for (infos[0 ..], 0 ..) |*info, i| {
			info.rms = root_moves.slice()[start ..][0 .. if (i < mod) div + 1 else div];
			start += info.rms.len;
		}
		for (infos[1 ..]) |*info| {
			info.pos = infos[0].pos;
		}

		var pool: std.Thread.Pool = undefined;
		var wg = std.Thread.WaitGroup {};
		try pool.init(.{
			.allocator = misc.heap.allocator,
			.n_jobs = infos.len,
			.track_ids = false,
		});
		defer pool.deinit();

		for (min_depth .. max_depth) |d| {
			const depth: u8 = @truncate(d);

			wg.reset();
			for (infos, 0 ..) |*info, i| {
				info.depth = depth + @intFromBool(i % 2 == 0);
				pool.spawnWg(&wg, threaded, .{info});
			}
			pool.waitAndWork(&wg);
			root_moves.sort();

			try print(buffered.writer(), depth, root_moves);
			try buffered.flush();

			if (timeman.hardStop()) {
				break;
			}
		}

		{
			const pv = root_moves.pv();
			const move = pv.line.constSlice()[0];
			const len: usize = if (move.promotion() == .nil) 4 else 5;
			const str = move.print();

			try buffered.writer().print("bestmove {s}\n", .{str[0 .. len]});
			try buffered.flush();
		}
	}

	fn print(writer: anytype, depth: u8, root_moves: movegen.RootMove.List) !void {
		const pv = root_moves.pv();
		const cp = evaluation.score.centipawns(pv.score);
		const current = misc.time.read(.ms);
		try writer.print("info", .{});
		try writer.print(" depth {d}", .{depth});
		try writer.print(" score cp {d}", .{cp});
		try writer.print(" time {d}", .{current - timeman.start});
		try writer.print(" pv", .{});
		for (pv.line.constSlice()) |move| {
			const len: usize = if (move.promotion() == .nil) 4 else 5; 
			const str = move.print();
			try writer.print(" {s}", .{str[0 .. len]});
		}
		try writer.print("\n", .{});
	}

	pub fn spawn() !void {
		const handle = try std.Thread.spawn(.{.allocator = misc.heap.allocator}, func, .{});
		std.Thread.detach(handle);
	}
};

fn qs(info: *Info, alpha: isize, beta: isize) isize {
	const is_pv = beta - alpha > 1;
	const b = beta;
	var a = alpha;
	var pos = &info.pos;
	const draw: evaluation.score.Int = evaluation.score.draw;
	const lose: evaluation.score.Int = evaluation.score.lose
	  + @as(evaluation.score.Int, @intCast(pos.ssPly()));

	if (pos.is3peat() or pos.ssTop().rule50 >= 100) {
		return draw;
	}

	var flag = transposition.Entry.Flag.alpha;
	const tt_fetch = transposition.Table.global.fetch(pos.ssTop().key);
	const tte = tt_fetch[0];
	const hit = tt_fetch[1];

	if (hit and tte.?.shouldTrust(alpha, beta)) {
		return tte.?.score;
	} else if (hit and timeman.hardStop()) {
		return tte.?.score;
	}
	const eval = if (hit) tte.?.eval else evaluation.scorePosition(pos.*);

	const ttm = if (hit) tte.?.move else movegen.Move.zero;
	var best = movegen.Move.Scored {
		.move  = ttm,
		.score = lose,
	};
	var mp = movegen.Picker.init(info,
	  ttm, movegen.Move.zero, movegen.Move.zero, pos.checkMask() == .all);

	while (mp.next()) |move| {
		if (timeman.hardStop()) {
			break;
		}

		pos.doMove(move) catch continue;
		defer pos.undoMove();

		var s: isize = evaluation.score.nil;
		if (is_pv and best.score == lose) {
			s = -qs(info, -b, -a);
		} else if (is_pv) {
			s = -qs(info, -a - 1, -a);
			if (s > a and s < b) {
				s = -qs(info, -b, -a);
			}
		} else {
			s = -qs(info, -a - 1, -a);
		}

		if (s > best.score) {
			best.score = @intCast(s);
			if (s > a) {
				flag = if (pos.checkMask() == .all) .pv else .alpha;
				a = s;
				best.move = move;
			}
			if (s >= b) {
				flag = .beta;
				break;
			}
		}
	}

	if (best.score == lose) {
		return if (pos.checkMask() == .all) eval else lose;
	} else {
		if (tte != null) {
			tte.?.* = .{
				.age = @truncate(transposition.Table.global.age),
				.key = @truncate(pos.ssTop().key),
				.flag = flag,
				.eval = @intCast(eval),
				.move = best.move,
				.score = best.score,
				.depth = 0,
			};
		}

		return best.score;
	}
}

fn ab(info: *Info, alpha: isize, beta: isize, depth: u8) isize {
	if (depth == 0) {
		return qs(info, alpha, beta);
	}

	const is_pv = beta - alpha > 1;
	const d = depth;
	const b = beta;
	var a = alpha;
	var pos = &info.pos;
	const draw: evaluation.score.Int = evaluation.score.draw;
	const lose: evaluation.score.Int = evaluation.score.lose
	  + @as(evaluation.score.Int, @intCast(pos.ssPly()));

	if (pos.is3peat() or pos.ssTop().rule50 >= 100) {
		return draw;
	}

	var flag = transposition.Entry.Flag.alpha;
	const tt_fetch = transposition.Table.global.fetch(pos.ssTop().key);
	const tte = tt_fetch[0];
	const hit = tt_fetch[1];

	if (hit and tte.?.depth >= depth and tte.?.shouldTrust(alpha, beta)) {
		return tte.?.score;
	} else if (hit and timeman.hardStop()) {
		return tte.?.score;
	}
	const eval = if (hit) tte.?.eval else evaluation.scorePosition(pos.*);

	const ttm = if (hit) tte.?.move else movegen.Move.zero;
	var best = movegen.Move.Scored {
		.move  = ttm,
		.score = lose,
	};
	var mp = movegen.Picker.init(info, ttm, movegen.Move.zero, movegen.Move.zero, false);

	while (mp.next()) |move| {
		if (timeman.hardStop()) {
			break;
		}

		pos.doMove(move) catch continue;
		defer pos.undoMove();

		var s: isize = evaluation.score.nil;
		if (is_pv and best.score == lose) {
			s = -ab(info, -b, -a, d - 1);
		} else if (is_pv) {
			s = -ab(info, -a - 1, -a, d - 1);
			if (s > a and s < b) {
				s = -ab(info, -b, -a, d - 1);
			}
		} else {
			s = -ab(info, -a - 1, -a, d - 1);
		}

		if (s > best.score) {
			best.score = @intCast(s);
			if (s > a) {
				flag = .pv;
				a = s;
				best.move = move;
			}
			if (s >= b) {
				flag = .beta;
				break;
			}
		}
	}

	if (best.score == lose) {
		return if (pos.checkMask() == .all) draw else lose;
	} else {
		if (tte != null) {
			tte.?.* = .{
				.age = @truncate(transposition.Table.global.age),
				.key = @truncate(pos.ssTop().key),
				.flag = flag,
				.eval = @intCast(eval),
				.move = best.move,
				.score = best.score,
				.depth = @intCast(depth),
			};
		}
		return best.score;
	}
}

pub fn threaded(info: *Info) void {
	const lose = evaluation.score.lose;
	const b = evaluation.score.win;
	const d = info.depth;
	var a: isize = evaluation.score.lose;

	const tt_fetch = transposition.Table.global.fetch(info.pos.ssTop().key);
	const tte = tt_fetch[0];
	const hit = tt_fetch[1];
	if (timeman.hardStop()) {
		return;
	}

	const eval = if (hit) tte.?.eval else evaluation.scorePosition(info.pos);
	var best = movegen.Move.Scored {
		.move  = if (hit) tte.?.move else movegen.Move.zero,
		.score = lose,
	};

	for (info.rms[0 ..], 0 ..) |*rm, i| {
		if (timeman.hardStop()) {
			break;
		}

		const move = rm.line.constSlice()[0];
		info.pos.doMove(move) catch unreachable;
		defer info.pos.undoMove();

		var s: isize = rm.score;
		if (i == 0) {
			s = -ab(info, -b, -a, d - 1);
		} else {
			s = -ab(info, -a - 1, -a, d - 1);
			if (s > a and s < b) {
				s = -ab(info, -b, -a, d - 1);
			}
		}
		rm.score = s;

		if (s > best.score) {
			best.score = @intCast(s);
			if (s > a) {
				a = s;
				best.move = move;
			}
		}
	}

	if (best.score != lose) {
		if (tte != null) {
			tte.?.* = .{
				.age = @truncate(transposition.Table.global.age),
				.key = @truncate(info.pos.ssTop().key),
				.depth = info.depth,
				.flag = .pv,
				.eval = @intCast(eval),
				.move = best.move,
				.score = @intCast(best.score),
			};
		}
	}
}
