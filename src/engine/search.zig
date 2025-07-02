const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const timeman = @import("timeman.zig");

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

	fn qs(self: *Info, ss_many: [*]Position.Stack,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int,
	  comptime is_pv: bool) evaluation.score.Int {
		const ss: *Position.Stack = @ptrCast(ss_many);

		const lose: evaluation.score.Int
		  = evaluation.score.lose
		  + @as(u8, @truncate(ss - self.root));

		const b = beta;
		var a = alpha;

		var best = movegen.Move.Scored {
			.move  = .{},
			.score = lose,
		};
		var mp = movegen.Picker.init(self, .{}, .{}, .{}, !is_pv and !self.pos.isChecked());

		while (mp.next()) |sm| {
			const move = sm.move;
			const s = recursion: {
				self.pos.doMove(move) catch continue;
				defer self.pos.undoMove();

				var score = sm.score;

				if (is_pv) {
					if (best.score == lose) {
						score = -self.qs(ss_many + 1, -b, -a, true);
					} else {
						score = -self.qs(ss_many + 1, -a - 1, -a, false);
						if (score > a and score < b) {
							score = -self.qs(ss_many + 1, -b, -a, true);
						}
					}
				} else {
					score = -self.qs(-a - 1, -a, false);
				}

				break :recursion score;
			};

			if (s > best.score) {
				best.score = s;
				if (s > a) {
					a = s;
					best.move = move;
				}
				if (s >= b) {
					break;
				}
			}
		}

		if (best.score == lose) {
			return lose;
		} else {
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
