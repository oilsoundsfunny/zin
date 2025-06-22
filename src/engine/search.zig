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
	rmi:	usize = 0,

	nodes:	u64 = 0,
	tbhits:	u64 = 0,

	bfhist:	HistArray(Hist, 1) = std.mem.zeroes(HistArray(Hist, 1)),
	cuthist:	HistArray(Hist, 1) = std.mem.zeroes(HistArray(Hist, 1)),

	capthist:	HistArray(Hist, 2) = std.mem.zeroes(HistArray(Hist, 2)),

	conthist:	[6]HistArray(Hist, 2) = std.mem.zeroes([6]HistArray(Hist, 2)),
	countermove:	HistArray(movegen.Move, 1) = std.mem.zeroes(HistArray(movegen.Move, 1)),

	pub const Hist = i16;
	pub const hist_max = std.math.maxInt(Hist);
	pub const hist_min = std.math.maxInt(Hist);

	pub const Error = error {
		Uninitialized,
	};

	pub var global: ?[]Info = null;
	pub var root_moves = std.mem.zeroes(movegen.RootMove.List);

	fn HistArray(comptime T: type, comptime n: comptime_int) type {
		return switch (n) {
			1 => std.EnumArray(misc.types.Piece, std.EnumArray(misc.types.Square, T)),
			2 => HistArray(HistArray(T, 1), 1),
			else => @compileError("unexpected comptime integer"
			  ++ std.fmt.comptimePrint("{d}", .{n})),
		};
	}

	pub fn getCaptHist(self: Info, move: movegen.Move) Hist {
		const src = move.src;
		const dst = move.dst;
		const src_piece = self.pos.getSquare(move.src);
		const dst_piece = self.pos.getSquare(move.dst);

		return self.capthist.get(src_piece).get(src).get(dst_piece).get(dst);
	}
	pub fn bonusCaptHist(self: *Info, move: movegen.Move, bonus: isize) void {
		const src = move.src;
		const dst = move.dst;
		const src_piece = self.pos.getSquare(move.src);
		const dst_piece = self.pos.getSquare(move.dst);

		const ptr = self.capthist.getPtr(src_piece).getPtr(src).getPtr(dst_piece).getPtr(dst);
		const current: isize = ptr.*;
		const clamped: isize = std.math.clamp(bonus, hist_min, hist_max);
		const abs: isize = @intCast(@abs(clamped));
		const next = clamped - @divTrunc(current * abs, hist_max);

		ptr.* = @intCast(next);
	}
	pub fn malusCaptHist(self: *Info, move: movegen.Move, bonus: isize) void {
		self.bonusCaptHist(move, -bonus);
	}

	pub fn getCutHist(self: Info, move: movegen.Move) Hist {
		const src = move.src;
		const dst = move.dst;
		const src_piece = self.pos.getSquare(src);

		return self.cuthist.get(src_piece).get(dst);
	}
	pub fn bonusCutHist(self: *Info, move: movegen.Move, bonus: Hist) void {
		const src = move.src;
		const dst = move.dst;
		const src_piece = self.pos.getSquare(src);

		const current: isize = self.cuthist.get(src_piece).get(dst);
		const clamped: isize = std.math.clamp(bonus, hist_min, hist_max);
		const abs: isize = @intCast(@abs(clamped));
		const next = clamped - @divTrunc(current * abs, hist_max);

		self.cuthist.getPtr(src_piece).set(dst, @intCast(next));
	}
	pub fn malusCutHist(self: *Info, move: movegen.Move, malus: Hist) void {
		// TODO: seperate function for malus
		self.bonusCutHist(move, -malus);
	}

	pub fn addCounterMove(self: *Info, prev: movegen.Move, counter: movegen.Move) void {
		const src = prev.src;
		const dst = prev.dst;
		const src_piece = self.pos.getSquare(src);

		self.countermove.getPtr(src_piece).set(dst, counter);
	}
	pub fn getCounterMove(self: Info) movegen.Move {
		const dst = self.pos.ssTop().move.dst;
		const src_piece = self.pos.ssTop().src_piece;

		return self.countermove.get(src_piece).get(dst);
	}

	pub fn getCounterMoveHist(self: Info, move: movegen.Move) Hist {
		const prev = self.pos.ssTop().move;
		const prev_dst = prev.dst;
		const prev_src_piece = self.pos.ssTop().src_piece;

		const src = move.src;
		const dst = move.dst;
		const src_piece = self.pos.getSquare(src);

		return self.conthist[0].get(prev_src_piece).get(prev_dst).get(src_piece).get(dst);
	}
	pub fn bonusCounterMoveHist(self: *Info, move: movegen.Move, bonus: isize) void {
		const prev = self.pos.ssTop().move;
		const prev_dst = prev.dst;
		const prev_src_piece = self.pos.ssTop().src_piece;

		const src = move.src;
		const dst = move.dst;
		const src_piece = self.pos.getSquare(src);

		const ptr = self.conthist[0]
		  .getPtr(prev_src_piece).getPtr(prev_dst)
		  .getPtr(src_piece).getPtr(dst);

		const current: isize = ptr.*;
		const clamped: isize = std.math.clamp(bonus, hist_min, hist_max);
		const abs: isize = @intCast(@abs(clamped));
		const next = clamped - @divTrunc(current * abs, hist_max);

		ptr.* = @intCast(next);
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

	pub fn getNodesCount() Error!usize {
		const all = try ofThreads();
		var sum: usize = 0;
		for (all) |info| {
			sum += info.nodes;
		}
		return sum;
	}
};

pub const manager = struct {
	pub var native: ?std.Thread.Handle = null;

	fn func() !void {
		@atomicStore(bool, &timeman.is_searching, true, .monotonic);
		defer @atomicStore(bool, &timeman.is_searching, false, .monotonic);

		const infos = Info.global orelse return error.Uninitialized;
		Info.root_moves = movegen.RootMove.List.fromInfo(&infos[0]);
		for (Info.root_moves.slice()) |*rm| {
			infos[0].pos.doMove(rm.line.constSlice()[0]) catch unreachable;
			defer infos[0].pos.undoMove();

			rm.score = -ab(&infos[0], evaluation.score.lose, evaluation.score.win, 0);
		}
		Info.root_moves.sort();

		const stdout = std.io.getStdOut();
		var buffered_out = std.io.bufferedWriter(stdout.writer());
		try print(buffered_out.writer(), 1, Info.root_moves);
		try buffered_out.flush();

		const div = Info.root_moves.constSlice().len / infos.len;
		const mod = Info.root_moves.constSlice().len % infos.len;
		var rmi: usize = 0;
		for (infos, 0 ..) |*info, i| {
			info.pos = infos[0].pos;
			info.rms = Info.root_moves.slice()[rmi ..][0 .. if (i < mod) div + 1 else div];
			rmi += info.rms.len;
		}

		var pool: std.Thread.Pool = undefined;
		var wg = std.Thread.WaitGroup {};
		try pool.init(.{
			.allocator = misc.heap.allocator,
			.n_jobs = infos.len,
			.track_ids = false,
		});
		defer pool.deinit();

		const min_depth = 2;
		const max_depth = timeman.depth orelse 240;
		for (min_depth .. max_depth) |d| {
			if (timeman.hardStop()) {
				break;
			}
			const depth: u8 = @truncate(d);

			wg.reset();
			for (infos, 0 ..) |*info, i| {
				info.depth = depth + @intFromBool(i % 2 == 0);
				info.nodes = 0;

				pool.spawnWg(&wg, threaded, .{info});
			}
			pool.waitAndWork(&wg);

			Info.root_moves.sort();
			transposition.Table.global.doAging();

			try print(buffered_out.writer(), depth, Info.root_moves);
			try buffered_out.flush();
		}

		{
			const pv = Info.root_moves.pv();
			const move = pv.line.constSlice()[0];
			const len: usize = if (move.promotion() == .nil) 4 else 5;
			const str = move.print();

			try buffered_out.writer().print("bestmove {s}\n", .{str[0 .. len]});
			try buffered_out.flush();
		}
	}

	fn print(writer: anytype, depth: u8, root_moves: movegen.RootMove.List) !void {
		const pv = root_moves.pv();
		const cp = evaluation.score.centipawns(pv.score);
		const current = misc.time.read(.ms);

		try writer.print("info", .{});
		try writer.print(" depth {d}", .{depth});
		try writer.print(" nodes {d}", .{try Info.getNodesCount()});
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
		.move  = movegen.Move.zero,
		.score = lose,
	};
	var mp = movegen.Picker.init(info,
	  ttm, movegen.Move.zero, movegen.Move.zero, pos.checkMask() == .all);
	var mi: usize = 0;

	while (mp.next()) |move| {
		if (timeman.hardStop()) {
			break;
		}

		const s = blk: {
			pos.doMove(move) catch continue;
			defer mi += 1;
			defer pos.undoMove();

			var score: isize = best.score;
			if (is_pv and mi == 0) {
				score = -qs(info, -b, -a);
			} else if (is_pv) {
				score = -qs(info, -a - 1, -a);
				if (score > a and score < b) {
					score = -qs(info, -b, -a);
				}
			} else {
				score = -qs(info, -a - 1, -a);
			}
			break :blk score;
		};

		if (s > best.score) {
			best.score = @intCast(s);
			if (s > a) {
				a = s;
				best.move = move;
			}
			if (s >= b) {
				info.bonusCaptHist(move, 1);
				for (mp.constAllNoisyMoves()) |prev| {
					info.malusCaptHist(prev, 1);
				}

				flag = .beta;
				break;
			}
		}
	}

	if (best.score == lose) {
		return if (pos.checkMask() == .all) eval else lose;
	} else {
		if (tte) |entry| {
			entry.* = .{
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
		info.nodes += 1;
		return qs(info, alpha, beta);
	}

	const is_pv = beta - alpha > 1;
	const b = beta;
	var a = alpha;
	var d = depth;
	const pos = &info.pos;
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
	const ttm  = if (hit) tte.?.move else movegen.Move.zero;
	const eval = if (hit) @as(isize, tte.?.eval) else evaluation.scorePosition(pos.*);

	const razoring_margin = @as(isize, depth) * 256 + 768;
	if (!is_pv and pos.checkMask() == .all and eval < a - razoring_margin) {
		const rs = qs(info, a - 1, a);
		if (rs < alpha and rs > evaluation.score.mated and rs < evaluation.score.mate) {
			return rs;
		}
	}

	const rfp_margin = @as(isize, depth) * 256;
	if (!is_pv and pos.checkMask() == .all
	  and !ttm.isZero() and pos.isMoveQuiet(ttm)) {
		return eval;
	}

	if (!is_pv and pos.checkMask() == .all and !pos.ssTop().move.isZero() and eval >= b) {
		const ns = blk: {
			pos.doNullMove() catch unreachable;
			defer pos.undoNullMove();

			const nr: u8 = if (depth > 6) 4 else 3;
			const nd: u8 = depth -| (nr + 1);
			break :blk -ab(info, -b, 1 - b, nd);
		};

		if (ns >= b) {
			d -|= 4;
			if (d <= 0) {
				return qs(info, a, b);
			}
		}
	}

	var best = movegen.Move.Scored {
		.move  = movegen.Move.zero,
		.score = lose,
	};
	var mp = movegen.Picker.init(info, ttm, movegen.Move.zero, movegen.Move.zero, false);
	var mi: usize = 0;

	while (mp.next()) |move| {
		if (timeman.hardStop()) {
			break;
		}

		const fut_margin = rfp_margin;
		if (mp.isQuiet() and eval <= a - fut_margin) {
			break;
		}

		const s = blk: {
			pos.doMove(move) catch continue;
			defer mi += 1;
			defer pos.undoMove();

			var score: isize = best.score;
			if (is_pv and mi == 0) {
				score = -ab(info, -b, -a, d - 1);
			} else if (is_pv) {
				score = -ab(info, -a - 1, -a, d - 1);
				if (score > a and score < b) {
					score = -ab(info, -b, -a, d - 1);
				}
			} else {
				score = -ab(info, -a - 1, -a, d - 1);
			}
			break :blk score;
		};

		if (s > best.score) {
			best.score = @intCast(s);
			if (s > a) {
				flag = .pv;
				a = s;
				best.move = move;
			}
			if (s >= b) {
				if (pos.isMoveQuiet(move)) {
					info.bonusCutHist(move, depth);
					for (mp.constAllQuietMoves()) |prev| {
						info.malusCutHist(prev, depth);
					}

					info.addCounterMove(pos.ssTop().move, move);
					info.bonusCounterMoveHist(move, depth);
				} else {
					info.bonusCaptHist(move, depth);
					for (mp.constAllNoisyMoves()) |prev| {
						info.malusCaptHist(prev, depth);
					}
				}

				flag = .beta;
				break;
			}
		}
	}

	if (best.score == lose) {
		return if (pos.checkMask() == .all) draw else lose;
	} else {
		if (is_pv and pos.ssPly() < info.depth) {
			if (pos.ssPly() == info.depth - 1) {
				info.rms[info.rmi].line.resize(info.depth) catch unreachable;
			}
			info.rms[info.rmi].line.set(pos.ssPly(), best.move);
		}

		if (tte) |entry| {
			entry.* = .{
				.age = @truncate(transposition.Table.global.age),
				.key = @truncate(pos.ssTop().key),
				.flag = flag,
				.eval = @intCast(eval),
				.move = best.move,
				.score = best.score,
				.depth = depth,
			};
		}
		return best.score;
	}
}

fn aspiration(info: *Info, alpha: isize, beta: isize, depth: u8) isize {
	const rm = &info.rms[info.rmi];
	var score = rm.score;
	var window: struct {isize, isize} = .{
		0 - evaluation.score.pawn * 4,
		0 + evaluation.score.pawn * 4,
	};
	var lower = std.math.clamp(score + window[0], alpha, evaluation.score.win);
	var upper = std.math.clamp(score + window[0], evaluation.score.lose, beta);

	if (info.rmi == 0) {
		score = -ab(info, -upper, -lower, depth);
	} else {
		score = -ab(info, -lower - 1, -lower, depth);
		if (score > lower and score < upper) {
			score = -ab(info, -upper, -lower, depth);
		}
	}
	while (score > alpha and score < beta and (score <= lower or score >= upper)) {
		if (score <= lower) {
			window[0] *= 4;
			window[1]  = @divTrunc(window[1], 2);
		} else {
			window[0]  = @divTrunc(window[0], 2);
			window[1] *= 4;
		}

		lower = std.math.clamp(score + window[0], alpha, evaluation.score.win);
		upper = std.math.clamp(score + window[0], evaluation.score.lose, beta);
		score = -ab(info, -upper, -lower, depth);
	}

	rm.score = score;
	return rm.score;
}

fn threaded(info: *Info) void {
	const lose = evaluation.score.lose;
	const b = evaluation.score.win;
	const d = info.depth;
	var a: isize = evaluation.score.lose;

	var best = movegen.Move.Scored {
		.move  = movegen.Move.zero,
		.score = lose,
	};

	for (info.rms[0 ..], 0 ..) |*rm, i| {
		if (timeman.hardStop()) {
			break;
		}

		const move = rm.line.constSlice()[0];
		const s = blk: {
			info.pos.doMove(move) catch unreachable;
			info.rmi = i;
			defer info.pos.undoMove();

			var score = rm.score;
			if (info.isMain() and info.rmi == 0) {
				score = -ab(info, -b, -a, d - 1);
			} else {
				score = -ab(info, -a - 1, -a, d - 1);
				if (score > a and score < b) {
					score = -ab(info, -b, -a, d - 1);
				}
			}

			rm.score = score;
			break :blk score;
		};

		if (s > best.score) {
			best.score = @intCast(s);
			if (s > a) {
				a = s;
				best.move = move;
			}
			if (s >= b) {
				break;
			}
		}
	}
}
