const builtin = @import("builtin");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const timeman = @import("timeman.zig");
const transposition = @import("transposition.zig");
const uci = @import("uci.zig");

const lmr_tbl = lmr_init: {
	@setEvalBranchQuota(1 << 20);
	var tbl align(std.heap.page_size_max) = std.mem.zeroes([256][256][2]Info.Depth);
	for (tbl[1 ..], 1 ..) |*by_depth, depth| {
		for (by_depth.*[1 ..], 1 ..) |*by_number, num| {
			const d: comptime_float = @floatFromInt(depth);
			const n: comptime_float = @floatFromInt(num);
			by_number[0] = @intFromFloat(0.20 + @log(d) * @log(n) / 3.35);
			by_number[1] = @intFromFloat(1.35 + @log(d) * @log(n) / 2.75);
		}
	}
	break :lmr_init tbl;
};

pub const Info = struct {
	pos:	Position = .{},
	depth:	u8 = undefined,
	rms:	[]movegen.RootMove = undefined,

	nodes:	u64 = 0,
	tbhits:	u64 = 0,

	bfhist:	HistArray(Hist, 1) = std.mem.zeroes(HistArray(Hist, 1)),
	cuthist:	HistArray(Hist, 1) = std.mem.zeroes(HistArray(Hist, 1)),
	capthist:	HistArray(Hist, 2) = std.mem.zeroes(HistArray(Hist, 2)),
	conthist:	[6]HistArray(Hist, 2) = std.mem.zeroes([6]HistArray(Hist, 2)),
	countermove:	HistArray(movegen.Move, 1) = std.mem.zeroes(HistArray(movegen.Move, 1)),

	pub const Depth = u8;
	pub const Hist = i16;
	pub const Score = evaluation.score.Int;

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

	pub fn getCaptHist(self: Info, move: movegen.Move) Hist {
		const src = move.src;
		const dst = move.dst;
		const src_piece = self.pos.getSquare(src);
		const dst_piece = self.pos.getSquare(dst);

		return self.capthist.get(src_piece).get(src).get(dst_piece).get(dst);
	}
	pub fn bonusCaptHist(self: *Info, move: movegen.Move, bonus: Hist) void {
		const src = move.src;
		const dst = move.dst;
		const src_piece = self.pos.getSquare(src);
		const dst_piece = self.pos.getSquare(dst);

		const ptr = self.capthist.getPtr(src_piece).getPtr(src).getPtr(dst_piece).getPtr(dst);
		const current: isize = ptr.*;
		const clamped: isize = bonus;
		const abs: isize = @intCast(@abs(clamped));
		const next = current + clamped - @divTrunc(current * abs, std.math.maxInt(Hist));

		ptr.* = @intCast(next);
	}
	pub fn malusCaptHist(self: *Info, move: movegen.Move, bonus: Hist) void {
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
		const clamped: isize = bonus;
		const abs: isize = @intCast(@abs(clamped));
		const next = current + clamped - @divTrunc(current * abs, std.math.maxInt(Hist));

		self.cuthist.getPtr(src_piece).set(dst, @intCast(next));
	}
	pub fn malusCutHist(self: *Info, move: movegen.Move, malus: Hist) void {
		// TODO: seperate function for malus
		self.bonusCutHist(move, -malus);
	}

	pub fn addCounterMove(self: *Info, counter: movegen.Move) void {
		const prev = self.pos.ssTop().move;
		const src = prev.src;
		const dst = prev.dst;
		const src_piece = self.pos.getSquare(src);

		self.countermove.getPtr(src_piece).set(dst, counter);
	}
	pub fn getCounterMove(self: Info) movegen.Move {
		const prev = self.pos.ssTop().move;
		const src = prev.src;
		const dst = prev.dst;
		const src_piece = self.pos.getSquare(src);

		return self.countermove.get(src_piece).get(dst);
	}

	pub fn getContHist(self: Info, ply: usize, move: movegen.Move) Hist {
		if (self.pos.ss.constSlice().len < ply) {
			return evaluation.score.draw;
		}

		const ss = &self.pos.ss.constSlice()[self.pos.ss.constSlice().len - ply];

		const prev = ss.move;
		const prev_dst = prev.dst;
		const prev_src_piece = ss.src_piece;

		const this_src = move.src;
		const this_dst = move.dst;
		const this_src_piece = self.pos.getSquare(this_src);

		return self.conthist[ply -| 1]
		  .get(prev_src_piece).get(prev_dst)
		  .get(this_src_piece).get(this_dst);
	}
	pub fn bonusContHist(self: *Info, ply: usize, move: movegen.Move, bonus: Hist) void {
		if (self.pos.ss.constSlice().len < ply) {
			return;
		}

		const ss = &self.pos.ss.constSlice()[self.pos.ss.constSlice().len - 2];
		const prev = ss.move;
		const prev_dst = prev.dst;
		const prev_src_piece = ss.src_piece;

		const this_src = move.src;
		const this_dst = move.dst;
		const this_src_piece = self.pos.getSquare(this_src);

		const ptr = self.conthist[ply -| 1]
		  .getPtr(prev_src_piece).getPtr(prev_dst)
		  .getPtr(this_src_piece).getPtr(this_dst);
		const current: isize = ptr.*;
		const clamped: isize = bonus;
		const abs: isize = @intCast(@abs(clamped));
		const next = current + clamped - @divTrunc(current * abs, std.math.maxInt(Hist));

		ptr.* = @intCast(next);
	}
	pub fn malusContHist(self: *Info, ply: usize, move: movegen.Move, bonus: Hist) void {
		self.bonusContHist(ply, move, -bonus);
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

		var root_moves = movegen.RootMove.List.fromInfo(&infos[0]);
		for (root_moves.slice()) |*rm| {
			const move = rm.line.constSlice()[0];
			infos[0].pos.doMove(move) catch unreachable;
			defer infos[0].pos.undoMove();

			infos[0].nodes = 0;
			rm.score = -ab(&infos[0], evaluation.score.lose, evaluation.score.win, 0);
		}
		root_moves.sort();

		try print(buffered.writer(), 1, root_moves);
		try buffered.flush();

		const div = root_moves.constSlice().len / infos.len;
		const mod = root_moves.constSlice().len % infos.len;
		var start: usize = 0;
		for (infos[0 ..], 0 ..) |*info, i| {
			info.pos = infos[0].pos;
			info.rms = root_moves.slice()[start ..][0 .. if (i < mod) div + 1 else div];
			start += info.rms.len;
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

			root_moves.sort();
			transposition.Table.global.doAging();

			try print(buffered.writer(), depth, root_moves);
			try buffered.flush();
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
		try writer.print(" nodes {d}", .{count_nodes: {
			var sum: u64 = 0;
			if (Info.global) |infos| {
				for (infos) |info| {
					sum += info.nodes;
				}
			}
			break :count_nodes sum;
		}});
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

fn qs(info: *Info, alpha: Info.Score, beta: Info.Score) Info.Score {
	const pos = &info.pos;
	const is_checked = pos.checkMask() != .all;
	const is_pv = beta - 1 > alpha;
	const b = beta;
	var a = alpha;
	const draw: Info.Score = evaluation.score.draw;
	const lose: Info.Score = evaluation.score.lose + @as(Info.Score, @intCast(pos.ssPly()));

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
	const ttm  = if (hit) tte.?.move else movegen.Move.zero;

	var best = movegen.Move.Scored {
		.move  = movegen.Move.zero,
		.score = lose,
	};
	var mp = movegen.Picker.init(info,
	  ttm, movegen.Move.zero, movegen.Move.zero, pos.checkMask() == .all);
	var mi: usize = 0;
	var penalized_noisy_moves = movegen.Move.List {};
	var penalized_quiet_moves = movegen.Move.List {};

	while (mp.next()) |sm| {
		if (timeman.hardStop()) {
			break;
		}
		const move = sm.move;

		if (!is_pv and !is_checked and eval < a) {
			const margin = @as(isize, a) - @as(isize, eval) + evaluation.score.pawn * 2;
			const clamped = std.math.clamp(margin, evaluation.score.lose, evaluation.score.win);
			if (!pos.seeMargin(move, @intCast(clamped))) {
				continue;
			}
		}

		const s = blk: {
			pos.doMove(move) catch continue;
			defer mi += 1;
			defer pos.undoMove();

			var score = best.score;
			if (is_pv and best.score == lose) {
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
			best.score = s;
			if (s > a) {
				flag = .alpha;
				a = s;
				best.move = move;
			}
			if (s >= b) {
				if (pos.checkMask() != .all and pos.isMoveQuiet(move)) {
					info.bonusCutHist(move, 128);
					for (penalized_quiet_moves.constSlice()) |prev| {
						info.malusCutHist(prev, 128);
					} 

					info.addCounterMove(move);
					for (1 .. 7) |ply| {
						info.bonusContHist(ply, move, 128);
					}
				} else {
					info.bonusCaptHist(move, 128);
					for (penalized_noisy_moves.constSlice()) |prev| {
						info.malusCaptHist(prev, 128);
					}
				}

				flag = .beta;
				break;
			} else if (pos.checkMask() != .all and pos.isMoveQuiet(move)) {
				penalized_quiet_moves.append(move);
			} else {
				penalized_noisy_moves.append(move);
			}
		}
	}

	if (best.score == lose) {
		return if (!is_checked) eval else lose;
	} else {
		if (tte) |entry| {
			entry.* = .{
				.age = @truncate(transposition.Table.global.age),
				.key = @truncate(pos.ssTop().key),
				.flag = flag,
				.eval = eval,
				.move = best.move,
				.score = best.score,
				.depth = 0,
			};
		}

		return best.score;
	}
}

fn ab(info: *Info, alpha: Info.Score, beta: Info.Score, depth: Info.Depth) Info.Score {
	if (depth == 0) {
		info.nodes += 1;
		return qs(info, alpha, beta);
	}

	const pos = &info.pos;
	const is_checked = pos.checkMask() != .all;
	const is_pv = beta - 1 > alpha;
	const b = beta;
	var a = alpha;
	var d = depth;
	const draw: Info.Score = evaluation.score.draw;
	const lose: Info.Score = evaluation.score.lose + @as(Info.Score, @intCast(pos.ssPly()));

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
	const ttm  = if (hit) tte.?.move else movegen.Move.zero;

	const rfp_margin = @as(Info.Score, depth) *| 128;
	if (!is_pv and !is_checked
	  and !ttm.isZero() and pos.isMoveQuiet(ttm)
	  and eval >= b +| rfp_margin) {
		return @divTrunc(eval, 2) + @divTrunc(b, 2);
	}

	const nmr_margin = 128;
	if (!is_pv and pos.checkMask() == .all and !pos.ssTop().move.isZero()
	  and eval >= b +| nmr_margin) {
		const ns = null_search: {
			pos.doNullMove() catch unreachable;
			defer pos.undoNullMove();

			const nr: Info.Depth = if (depth > 6) 4 else 3;
			const nd: Info.Depth = depth -| (nr + 1);
			break :null_search -ab(info, -b, 1 - b, nd);
		};

		if (ns >= b) {
			d -|= 4;
			if (d == 0) {
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
	var penalized_noisy_moves = movegen.Move.List {};
	var penalized_quiet_moves = movegen.Move.List {};

	while (mp.next()) |sm| {
		if (timeman.hardStop()) {
			break;
		}
		const move = sm.move;

		const fp_margin = @as(Info.Score, depth) *| 128;
		if (!is_pv and pos.checkMask() == .all
		  and a > evaluation.score.mated and b < evaluation.score.mate
		  and !mp.isMoveKiller(move) and mp.isQuiet()
		  and eval <= a -| fp_margin) {
			break;
		}

		const s = blk: {
			pos.doMove(move) catch continue;
			defer mi += 1;
			defer pos.undoMove();

			var lmr = if (!is_pv and mi >= 2)
			  lmr_tbl[depth][mi][@intFromBool(pos.isMoveQuiet(move))] else 0;
			if (lmr != 0 and hit and tte.?.flag == .beta) {
				lmr += 1;
			}
			if (lmr != 0 and !ttm.isZero() and pos.isMoveNoisy(move)) {
				lmr += 1;
			}
			if (lmr != 0 and is_checked) {
				lmr -|= 1;
			}
			if (lmr != 0 and pos.checkMask() != .all) {
				lmr -|= 1;
			}

			const original_d = d;
			defer d = original_d;

			d -|= lmr;
			d -|= 1;

			var score = best.score;
			if (is_pv and best.score == lose) {
				score = -ab(info, -b, -a, d);
			} else if (is_pv) {
				score = -ab(info, -a - 1, -a, d);
				if (score > a and score < b) {
					score = -ab(info, -b, -a, d);
				}
			} else {
				score = -ab(info, -a - 1, -a, d);
			}
			break :blk score;
		};

		if (s > best.score) {
			best.score = s;
			if (s > a) {
				flag = .pv;
				a = s;
				best.move = move;
			}
			if (s >= b) {
				if (pos.isMoveQuiet(move)) {
					info.bonusCutHist(move, @as(Info.Hist, depth) * 256 - 128);
					for (penalized_quiet_moves.constSlice()) |prev| {
						info.malusCutHist(prev, @as(Info.Hist, depth) * 256 - 128);
					} 

					info.addCounterMove(move);
					for (1 .. 7) |ply| {
						info.bonusContHist(ply, move, @as(Info.Hist, d) * 256 - 128);
					}
				} else {
					info.bonusCaptHist(move, @as(Info.Hist, depth) * 256 - 128);
					for (penalized_noisy_moves.constSlice()) |prev| {
						info.malusCaptHist(prev, @as(Info.Hist, depth) * 256 - 128);
					}
				}

				flag = .beta;
				break;
			} else if (pos.isMoveQuiet(move)) {
				penalized_quiet_moves.append(move);
			} else {
				penalized_noisy_moves.append(move);
			}
		}
	}

	if (best.score == lose) {
		return if (!is_checked) draw else lose;
	} else {
		if (tte) |entry| {
			entry.* = .{
				.age = @truncate(transposition.Table.global.age),
				.key = @truncate(pos.ssTop().key),
				.flag = flag,
				.eval = eval,
				.move = best.move,
				.score = best.score,
				.depth = depth,
			};
		}

		return best.score;
	}
}

pub fn threaded(info: *Info) void {
	const b = evaluation.score.win;
	const d = info.depth;
	var a: Info.Score = evaluation.score.lose;

	if (timeman.hardStop()) {
		return;
	}

	for (info.rms[0 ..], 0 ..) |*rm, i| {
		if (timeman.hardStop()) {
			break;
		}

		const move = rm.line.constSlice()[0];
		const s = blk: {
			info.pos.doMove(move) catch unreachable;
			defer info.pos.undoMove();

			var score = rm.score;
			if (info.isMain() and i == 0) {
				score = -ab(info, -b, -a, d - 1);
			} else {
				score = -ab(info, -a - 1, -a, d - 1);
				if (score > a and score < b) {
					score = -ab(info, -b, -a, d - 1);
				}
			}
			break :blk score;
		};

		rm.score = s;
		if (s > a) {
			a = s;
		}
		if (s >= b) {
			if (info.pos.isMoveQuiet(move)) {
				info.bonusCutHist(move, @as(Info.Hist, d) * 256 - 128);

				info.addCounterMove(move);
				for (1 .. 7) |ply| {
					info.bonusContHist(ply, move, @as(Info.Hist, d) * 256 - 128);
				}
			} else {
				info.bonusCaptHist(move, @as(Info.Hist, d) * 256 - 128);
			}
			break;
		}
	}
}
