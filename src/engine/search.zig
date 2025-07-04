const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const timeman = @import("timeman.zig");
const transposition = @import("transposition.zig");

pub const Depth = u8;
pub const Hist = i16;

pub const Info = struct {
	pos:	Position,
	root:	*Position.State,

	depth:	Depth,
	nodes:	u64,
	tbhits:	u64,

	rms:	[]movegen.Move.Root,
	rmi:	usize,

	pub const Many = struct {
		slice:	?[]Info = null,

		pub const Error = error {
			Uninitialized,
		};

		pub fn alloc(self: *Many, cnt: usize) !void {
			if (self.slice) |s| {
				self.slice = try misc.heap.allocator.realloc(s, cnt);
			} else {
				self.slice = try misc.heap.allocator
				  .alignedAlloc(Info, std.heap.page_size_max, cnt);
			}
		}

		pub fn ofMain(self: Many) Error!*Info {
			const infos = try self.ofWorkers();
			return &infos[0];
		}

		pub fn ofWorkers(self: Many) Error![]Info {
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

		const fetch = transposition.table.fetch(ss.key)
			catch std.debug.panic("tt is uninitialized", .{});
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

				break :recur score;
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
				.key = @truncate(pos.ss.top().key),
				.age = @truncate(transposition.table.age),
				.was_pv = if (is_pv) true else tte.was_pv,
				.flag = flag,
				.move = best.move,
				.eval = eval,
				.score = best.score,
				.depth = depth,
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
		  + @as(evaluation.score.Int, @as(u4, @truncate(self.nodes)));
		const lose: evaluation.score.Int
		  = evaluation.score.lose
		  + @as(evaluation.score.Int, @as(u8, @truncate(ss_ply)));

		const b = beta;
		var a = alpha;

		const fetch = transposition.table.fetch(ss.key)
			catch std.debug.panic("tt is uninitialized", .{});
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

				break :recur score;
			};

			if (s > best.score) {
				best.score = s;
			}
			if (s > a) {
				a = s;
				best.move = move;
				flag = if (is_pv) .exact else .lowerbound;
			}
			if (s >= b) {
				flag = .upperbound;
				break;
			}
		}

		if (best.score == lose) {
			return if (pos.isChecked()) lose else draw;
		} else {
			tte.* = .{
				.key = @truncate(pos.ss.top().key),
				.age = @truncate(transposition.table.age),
				.was_pv = if (is_pv) true else tte.was_pv,
				.flag = flag,
				.move = best.move,
				.eval = eval,
				.score = best.score,
				.depth = 0,
			};

			return best.score;
		}
	}

	pub fn threaded(self: *Info, idx: usize) void {
		const depth = self.depth;
		const pos = &self.pos;

		const beta: evaluation.score.Int = evaluation.score.win;
		var alpha: evaluation.score.Int = evaluation.score.lose;

		for (self.rms, 0 ..) |*rm, i| {
			self.rmi = i;

			const move = rm.line.get(0);
			const s = recur: {
				pos.doMove(move) catch unreachable;
				defer pos.doMove();

				var score: evaluation.score.Int = evaluation.score.lose + 1;
				if (i == 0) {
					score = -self.ab(1, -beta, -alpha, depth - 1, true);
				} else {
					score = -self.ab(1, -beta, -alpha, depth - 1, false);
					if (score > alpha and score < beta) {
						score = -self.ab(1, -beta, -alpha, depth - 1, true);
					}
				}
			};

			if (s > best.score) {
			}
			if (s > alpha) 	{
			}
			if (s >= beta) {
			}
		}
	}
};

pub const manager = struct {
	fn func() !void {
	}

	pub fn spawn() !void {
		const infos = try Info.many.ofWorkers();
		const main_info = try Info.many.ofMain();
		const pos = &main_info.pos;

		timeman.start = misc.time.read(.ms);
		if (timeman.movetime) |movetime| {
			timeman.stop = timeman.start + movetime - timeman.overhead;
		}
		if (timeman.increment.get(pos.stm) != null and timeman.time.get(pos.stm) != null) {
			const increment = timeman.increment.?;
			const time = timeman.time.?;

			timeman.stop = timeman.start + time / 20 + increment / 2 - timeman.overhead;
		}

		var root_moves = movegen.Move.Root.List.fromPosition(pos);
		for (root_moves.slice()) |*rm| {
			const move = rm.line.get(0);
			pos.doMove(move) catch unreachable;
			defer pos.undoMove();

			rm.score = -main_info.qs(1, evaluation.score.lose, evaluation.score.win, true);
		}
		movegen.Move.Root.sortSlice(root_moves.slice());

		var pool: std.Thread.Pool = undefined;
		var wg = std.Thread.WaitGroup {};
		try pool.init(.{
			.allocator = misc.heap.allocator,
			.n_jobs = infos.len,
		});
		defer pool.deinit();

		const min_depth = 2;
		const max_depth = timeman.depth orelse 240;
		for (min_depth .. max_depth) |depth| {
			wg.reset();
			for (infos, 0 ..) |*info, i| {
				info.depth = depth + @intFromBool(i % 2 != 0);
				info.nodes = 0;

				pool.spawnWg(&wg, Info.threaded, .{info, i});
			}
			pool.waitAndWork(&wg);
		}
	}
};
