const builtin = @import("builtin");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const smp = @import("smp.zig");
const transposition = @import("transposition.zig");

fn qs(info: *smp.Info, alpha: isize, beta: isize) isize {
	const b = beta;
	var a = alpha;
	var pos = &info.pos;

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
	var mp = movegen.Picker.init(info,
	  ttm, movegen.Move.zero, movegen.Move.zero, pos.checkMask() == .all);
	var mp_idx: usize = 0;

	while (mp.next()) |move| : (mp_idx += 1) {
		var s: isize = evaluation.score.nil;

		pos.doMove(move) catch continue;
		if (mp_idx == 0) {
			s = -qs(info, -b, -a);
		} else {
			s = -qs(info, -a - 1, -a);
			if (s >= a + 1) {
				s = -qs(info, -b, -a);
			}
		}
		defer pos.undoMove();

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

fn ab(info: *smp.Info, alpha: isize, beta: isize, depth: u8) isize {
	if (depth == 0) {
		return qs(info, alpha, beta);
	}

	const d = depth;
	const b = beta;
	var a = alpha;
	var pos = &info.pos;

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
	var mp = movegen.Picker.init(info, ttm, movegen.Move.zero, movegen.Move.zero, false);
	var mp_idx: usize = 0;

	while (mp.next()) |move| : (mp_idx += 1) {
		pos.doMove(move) catch continue;
		var s: isize = evaluation.score.nil;
		if (mp_idx == 0) {
			s = -ab(info, -b, -a, d - 1);
		} else {
			s = -ab(info, -a - 1, -a, d - 1);
			if (s >= a + 1) {
				s = -ab(info, -b, -a, d - 1);
			}
		}
		defer pos.undoMove();

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
