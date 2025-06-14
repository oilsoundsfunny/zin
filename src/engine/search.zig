const builtin = @import("builtin");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const Thread = @import("Thread.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const timeman = @import("timeman.zig");
const transposition = @import("transposition.zig");

fn qs(thread: *Thread, ss: [*]Position.Stack, alpha: isize, beta: isize) isize {
	const b = beta;
	var a = alpha;
	var pos = &thread.pos;

	if (pos.is3peat() or pos.ssTop().rule50 >= 100) {
		return evaluation.score.draw;
	}

	var tt_flag = transposition.Entry.Flag.alpha;
	const tt_fetch = transposition.Table.global.fetch(pos.ssTop().key);
	const tte = tt_fetch[0];
	const tt_hit = tt_fetch[1];

	if (tt_hit and tte.?.shouldTrust(alpha, beta)) {
		return tte.?.score;
	}
	const eval = evaluation.scorePosition(pos.*);

	const ttm = if (tt_hit) tte.?.move else movegen.Move.zero;
	var best = movegen.ScoredMove {
		.move  = ttm,
		.score = evaluation.score.nil,
	};
	var mp = movegen.Picker.init(thread,
	  ttm, movegen.Move.zero, movegen.Move.zero, pos.checkMask() == .all);
	var mp_idx: usize = 0;

	while (mp.next()) |move| : (mp_idx += 1) {
		var s: isize = evaluation.score.nil;

		pos.doMove(move) catch continue;
		if (mp_idx == 0) {
			s = -qs(thread, ss + 1, -b, -a);
		} else {
			s = -qs(thread, ss + 1, -a - 1, -a);
			if (s >= a + 1) {
				s = -qs(thread, ss + 1, -b, -a);
			}
		}
		pos.undoMove();

		if (s > best.score) {
			best.score = @intCast(s);
			if (s > a) {
				a = s;
				best.move = move;
			}
			if (s >= b) {
				tt_flag = .beta;
				break;
			}
		}
	}

	if (best.score == evaluation.score.nil) {
		const lose: isize = evaluation.score.lose;
		return if (pos.checkMask() == .all) eval else lose + @as(isize, @intCast(pos.ss_ply));
	} else {
		if (tte != null) {
			tte.?.* = .{
				.age = @truncate(transposition.Table.global.age),
				.key = @truncate(pos.ssTop().key),
				.flag = tt_flag,
				.eval = @intCast(eval),
				.move = best.move,
				.score = best.score,
				.depth = 0,
			};
		}

		return best.score;
	}
}

fn ab(thread: *Thread, ss: [*]Position.Stack,
  alpha: isize, beta: isize, depth: Thread.Depth) isize {
	if (depth <= 0) {
		return qs(thread, ss, alpha, beta);
	}

	const d = depth;
	const b = beta;
	var a = alpha;
	var pos = &thread.pos;

	if (pos.is3peat() or pos.ssTop().rule50 >= 100) {
		return evaluation.score.draw;
	}

	var tt_flag = transposition.Entry.Flag.alpha;
	const tt_fetch = transposition.Table.global.fetch(pos.ssTop().key);
	const tte = tt_fetch[0];
	const tt_hit = tt_fetch[1];

	if (tt_hit and tte.?.depth >= depth and tte.?.shouldTrust(alpha, beta)) {
		return tte.?.score;
	}
	const eval = if (tt_hit) tte.?.eval else evaluation.scorePosition(pos.*);

	const rfp_margin = depth * 128;
	if (pos.checkMask() == .all and beta - alpha == 1 and eval >= beta + rfp_margin) {
		return eval;
	}

	const ttm = if (tt_hit) tte.?.move else movegen.Move.zero;
	var best = movegen.ScoredMove {.move = ttm, .score = evaluation.score.nil};
	var mp = movegen.Picker.init(thread, ttm, movegen.Move.zero, movegen.Move.zero, false);
	var mp_idx: usize = 0;

	while (mp.next()) |move| : (mp_idx += 1) {
		pos.doMove(move) catch continue;
		var s: isize = evaluation.score.nil;
		if (mp_idx == 0) {
			s = -ab(thread, ss + 1, -b, -a, d - 1);
		} else {
			s = -ab(thread, ss + 1, -a - 1, -a, d - 1);
			if (s >= a + 1) {
				s = -ab(thread, ss + 1, -b, -a, d - 1);
			}
		}
		pos.undoMove();

		if (s > best.score) {
			best.score = @intCast(s);
			if (s > a) {
				tt_flag = .pv;
				a = s;
				best.move = move;
			}
			if (s >= b) {
				tt_flag = .beta;
				break;
			}
		}
	}

	if (best.score == evaluation.score.nil) {
		const draw: isize = evaluation.score.draw;
		const lose: isize = evaluation.score.lose;
		return if (pos.checkMask() == .all) draw else lose + @as(isize, @intCast(pos.ss_ply));
	} else {
		if (tte != null) {
			tte.?.* = .{
				.age = @truncate(transposition.Table.global.age),
				.key = @truncate(pos.ssTop().key),
				.flag = tt_flag,
				.eval = @intCast(eval),
				.move = best.move,
				.score = best.score,
				.depth = @intCast(depth),
			};
		}

		return best.score;
	}
}

pub fn onThread(thread: *Thread) !void {
	const is_main = thread.isMainWorker();
	const pos = &thread.pos;
	const ss = pos.ssTopPtr();
	const stdout = std.io.getStdOut();

	for (0 .. @intCast(timeman.depth.?)) |d| {
		if (is_main) {
			@atomicStore(bool, &Thread.Pool.global.is_helpers_awake, true, .monotonic);
			Thread.Pool.global.cond.broadcast();
			@atomicStore(bool, &Thread.Pool.global.is_helpers_awake, false, .monotonic);
		}

		var best = movegen.ScoredMove {
		  .move  = movegen.Move.zero,
		  .score = evaluation.score.lose,
		};
		const depth: isize = @intCast(d);
		thread.depth = depth;

		for (thread.root_moves.slice[0 ..], 0 ..) |*rm, i| {
			const move = rm.line[0];
			var window: struct {isize, isize} = .{-evaluation.score.pawn, evaluation.score.pawn};
			var score: isize = evaluation.score.nil;

			thread.root_moves.idx = i;
			pos.doMove(move) catch unreachable;
			defer {
				pos.undoMove();
				if (score > best.score) {
					best = .{.move = move, .score = @intCast(score)};
				}
				rm.score = score;
			}

			if (is_main) {
				@atomicStore(bool, &Thread.Pool.global.is_searching,
				  !timeman.hardStop(), .monotonic);
			}
			if (!Thread.Pool.global.isSearching()) {
				break;
			}
			score = -ab(thread, ss + 1, rm.score + window[0], rm.score + window[1], depth);

			if (score <= window[0] or score > window[1]) {
				if (score <= window[0]) {
					window[0] = std.math.clamp(window[0] * 4, evaluation.score.lose - score, 0);
				} else {
					window[1] = std.math.clamp(window[1] * 4, 0, evaluation.score.win - score);
				}

				if (is_main) {
					@atomicStore(bool, &Thread.Pool.global.is_searching,
					  !timeman.hardStop(), .monotonic);
				}
				if (!Thread.Pool.global.isSearching()) {
					break;
				}
				score = -ab(thread, ss + 1, score + window[0], score + window[1], depth);
			}
		}

		if (!is_main) {
			thread.sleep(&Thread.Pool.global.is_helpers_awake);
			continue;
		}

		Thread.Pool.global.sortRootMoves();

		const pv = thread.root_moves.slice[0];
		try stdout.writer().print("info depth {d} pv", .{depth});
		for (pv.line[0 .. pv.len]) |move| {
			try stdout.writer().print(" {s}", .{move.print()});
		}
		try stdout.writer().print(" score cp {d}", .{evaluation.score.centipawns(pv.score)});
		try stdout.writer().print("\n", .{});

		if (!Thread.Pool.global.isSearching()) {
			break;
		}
	}

	try stdout.writer().print("bestmove {s}\n", .{thread.root_moves.slice[0].line[0].print()});
}

test {
	try transposition.Table.global.allocate(512);
	defer transposition.Table.global.free();

	try Thread.Pool.global.allocate(1);
	defer Thread.Pool.global.free();

	const fens = [_][]const u8 {
		"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
		"8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
		"r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
		"rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
		"r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
		"K6R/8/8/8/8/8/6kp/8 w - - 0 1",
	};
	const main_worker = try Thread.Pool.global.getMainWorker();

	for (fens[2 ..][0 .. 0]) |fen| {
		try main_worker.pos.parseFen(fen);
		try Thread.Pool.global.genRootMoves();

		main_worker.depth = 12;
		_ = onThread(main_worker);
	}
}

test {
	_ = qs;
	_ = ab;
}
