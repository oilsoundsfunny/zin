const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const timeman = @import("timeman.zig");
const transposition = @import("transposition.zig");

pub const Depth = u8;

pub const Info = struct {
	pos:	Position,
	root:	*Position.Stack,

	depth:	Depth,
	nodes:	u64,
	tbhits:	u64,

	pub const Many = struct {
		slice:	?[]Info = null,

		pub const Error = error {
			Uninitialized,
		};

		pub fn ofMain(self: Many) Error!*Info {
			const infos = try self.ofWorkers();
			return &infos[0];
		}

		pub fn ofWorkers(self: Many) Error!*Info {
			return self.slice orelse error.Uninitialized;
		}
	};

	pub var many = Many {};

	fn ab(self: *Info, ss_ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int,
	  depth: Depth,
	  comptime is_pv: bool) evaluation.score.Int {
		if (depth == 0) {
			return self.qs(ss_ply, alpha, beta, is_pv);
		}

		const pos = &self.pos;
		const ss = &self.root[0 .. 1].ptr[ss_ply];

		const draw: evaluation.score.Int
		  = evaluation.score.draw
		  + @as(u4, @truncate(self.nodes));
		const lose: evaluation.score.Int
		  = evaluation.score.lose
		  + @as(u8, @truncate(ss_ply));

		const d = depth;
		const b = beta;
		var a = alpha;

		const fetch = transposition.table.fetch(ss.key);
		const tte = fetch[0];
		const hit = fetch[1];
		if (hit and tte.shouldTrust(a, b, d)) {
			return tte.score;
		}

		const eval = if (hit) tte.eval else evaluation.score.fromPosition(pos.*);

		var best = movegen.Move.Scored {
			.move = .{},
			.score = evaluation.score.lose,
		};
		var flag = transposition.Entry.Flag.lowerbound;

		var mp = movegen.Picker.init(self, tte.move, ss.down(1).killer0, ss.down(1).killer1, false);
		var searched_noisy_moves = movegen.Move.List {};
		var searched_quiet_moves = movegen.Move.List {};

		while (mp.next()) |sm| {
			const move = sm.move;
			const s = recur: {
				pos.doMove(move) catch break :recur evaluation.score.lose;
				defer pos.undoMove();

				var score = sm.score;
				if (is_pv) {
					if (best.score == lose) {
						score = -self.ab(ss_ply + 1, -b, -a, true);
					} else {
						score = -self.ab(ss_ply + 1, -a - 1, -a, d - 1, false);
						if (score > a and score < b) {
							score = -self.ab(ss_ply + 1, -b, -a, d - 1, true);
						}
					}
				} else {
					score = -self.ab(ss_ply + 1, -b, -a, d - 1, false);
				}
			};

			if (s > best.score) {
				best.score = s;
				if (s > a) {
					a = s;
					best.move = move;
					flag = .exact;
				}
				if (s >= b) {
					flag = .upperbound;
					break;
				} else {
					if (pos.isMoveNoisy(move)) {
						searched_noisy_moves.append(move);
					} else {
						searched_quiet_moves.append(move);
					}
				}
			}
		}

		if (best.score == lose) {
			return if (pos.isChecked()) lose else draw;
		} else {
			tte.* = .{
				.flag = flag,
				.was_pv = if (is_pv) true else tte.was_pv,
				.age = @truncate(transposition.table.age),
				.depth = depth,
				.move = best.move,
				.eval = eval,
				.score = best.score,
			};

			return best.score;
		}
	}

	fn qs(self: *Info, ss_ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int,
	  comptime is_pv: bool) evaluation.score.Int {
		const pos = &self.pos;
		const ss = &self.root[0 .. 1].ptr[ss_ply];

		const draw: evaluation.score.Int
		  = evaluation.score.draw
		  + @as(u4, @truncate(self.nodes));
		const lose: evaluation.score.Int
		  = evaluation.score.lose
		  + @as(u8, @truncate(ss_ply));

		const b = beta;
		var a = alpha;

		const fetch = transposition.table.fetch(ss.key);
		const tte = fetch[0];
		const hit = fetch[1];
		if (hit and tte.shouldTrust(a, b, 0)) {
			return tte.score;
		}

		const eval = if (hit) tte.eval else evaluation.score.fromPosition(pos.*);

		var best = movegen.Move.Scored {
			.move = .{},
			.score = lose,
		};
		var flag = transposition.Entry.Flag.lowerbound;

		var mp = movegen.Picker.init(self, tte.move, ss.down(1).killer0, ss.down(1).killer1,
		  !pos.isChecked());
		var searched_noisy_moves = movegen.Move.List {};
		var searched_quiet_moves = movegen.Move.List {};

		while (mp.next()) |sm| {
			const move = sm.move;
			const s = recur: {
				pos.doMove(move) catch break :recur evaluation.score.lose;
				defer pos.undoMove();

				var score = sm.score;
				if (is_pv) {
					if (best.score == lose) {
						score = -self.qs(ss_ply + 1, -b, -a, true);
					} else {
						score = -self.qs(ss_ply + 1, -a - 1, -a, false);
						if (score > a and score < b) {
							score = -self.qs(ss_ply + 1, -b, -a, true);
						}
					}
				} else {
					score = -self.qs(ss_ply + 1, -a - 1, -a, false);
				}
			};

			if (s > best.score) {
				best.score = s;
				if (s > a) {
					a = s;
					best.move = move;
					flag = if (is_pv) .exact else .lowerbound;
				}
				if (s >= b) {
				} else {
					if (pos.isMoveNoisy(move)) {
						searched_noisy_moves.append(move);
					} else {
						searched_quiet_moves.append(move);
					}
				}
			}
		}

		if (best.score == lose) {
			return if (pos.isChecked()) lose else eval;
		} else {
			tte.* = .{
				.flag = flag,
				.was_pv = if (is_pv) true else tte.was_pv,
				.age = @truncate(transposition.table.age),
				.depth = 0,
				.move = best.move,
				.eval = eval,
				.score = best.score,
			};

			return best.score;
		}
	}
};

pub const manager = struct {
	fn func() !void {
	}

	pub fn spawn() !void {
		const main_info = try Info.many.ofMain();

		timeman.start = misc.time.read(.ms);
		if (timeman.movetime) |movetime| {
			timeman.stop = timeman.start.? + movetime - timeman.overhead;
		}

		var root_moves = movegen.Move.Root.List.fromPosition(&main_info.pos);
		for (root_moves.slice()) |rm| {
			const move = rm.move;
			main_info.pos.doMove(move) catch unreachable;
			defer main_info.pos.undoMove();

			rm.score = -main_info.qs(evaluation.score.lose, evaluation.score.win);
		}
		movegen.Move.Root.sortSlice(root_moves.slice());
	}
};
