const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const search = @import("search.zig");

const RootMove = struct {
	line:	std.BoundedArray(Move, length) = .{
		.buffer = .{Move {}} ** length,
		.len = 0,
	},
	score:	evaluation.score.Int = evaluation.score.draw,

	pub const List = struct {
		array:	std.BoundedArray(RootMove, 256) = .{
			.buffer = .{RootMove {}} ** 256,
			.len = 0,
		},
	};

	const length = 256 - (@sizeOf(usize) + @sizeOf(evaluation.score.Int)) / @sizeOf(Move);
};

const ScoredMove = packed struct(u32) {
	move:	Move = .{},
	score:	evaluation.score.Int = evaluation.score.draw,

	pub const List = struct {
		array:	std.BoundedArray(ScoredMove, capacity) = .{
			.buffer = .{ScoredMove {}} ** capacity,
			.len = 0,
		},
		index:	usize,

		const capacity = 256 - 2 * @sizeOf(usize) / @sizeOf(ScoredMove);
	};
};

pub const Move = packed struct(u16) {
	flag:	Flag = .nil,
	key:	Flag.Int = 0,
	src:	misc.types.Square = .a1,
	dst:	misc.types.Square = .a1,

	pub const Root = RootMove;
	pub const Scored = ScoredMove;

	pub const Flag = enum(u2) {
		nil,
		en_passant,
		promote,
		castle,

		pub const Int = std.meta.Tag(Flag);
	};

	pub const List = struct {
		array:	std.BoundedArray(Move, capacity) = .{
			.buffer = .{Move {}} ** capacity,
			.len = 0,
		},

		const capacity = 256 - @sizeOf(usize) / @sizeOf(Move);
	};

	pub fn gen(comptime flag: Flag, comptime promo: misc.types.Ptype,
	  src: misc.types.Square,
	  dst: misc.types.Square) Move {
		return .{
			.flag = flag,
			.src = src,
			.dst = dst,
			.key = sw: switch (promo) {
				.nil => {
					if (flag == .promote) {
						@compileError("unexpected tag " ++ @tagName(flag));
					}
					break :sw 0;
				},
				.knight, .bishop, .rook, .queen => {
					if (flag != .promote) {
						@compileError("unexpected tag " ++ @tagName(flag));
					}
					break :sw @as(comptime_int, promo.int())
					  - @as(comptime_int, misc.types.Ptype.knight.int());
				},
				else => @compileError("unexpected tag " ++ @tagName(promo)),
			},
		};
	}

	pub fn promotion(self: Move) misc.types.Ptype {
		return if (self.flag == .promote)
		  misc.types.Ptype.fromInt(misc.types.Ptype.knight.int() + self.key)
		else if (self.key == 0) .nil
		else std.debug.panic("weird move", .{});
	}
};

pub const Picker = struct {
	list:	Move.Scored.List = .{},
	info:	*const search.Info,

	quies:	bool,
	stage:	Stage,

	noisy_cnt:	usize = 0,
	quiet_cnt:	usize = 0,
	bad_noisy_cnt:	usize = 0,
	bad_quiet_cnt:	usize = 0,

	pub const Stage = enum(u8) {
		ttm,
		gen_noisy, good_noisy,
		killer0, killer1,
		gen_quiet, good_quiet,
		bad_noisy,
		bad_quiet,
		end,

		pub const Int = std.meta.Tag(Stage);

		pub fn int(self: Stage) Int {
			return @intFromEnum(self);
		}

		pub fn inc(self: Stage) Stage {
			return @enumFromInt(self.int() + 1);
		}
	};

	pub fn next(self: *Picker) ?Move.Scored {
		if (self.stage == .ttm) {
			self.stage = self.stage.inc();
			if (self.ttm != .{}) {
				return .{
					.move = self.ttm,
					.score = self.scoreQuiet(self.ttm),
				};
			}
		}

		if (self.stage == .gen_noisy) {
			self.stage = self.stage.inc();
			self.list = .{};
		}

		while (self.stage == .good_noisy) {
			const sm = self.pick() orelse {
				self.stage = self.stage.inc();
				self.list.resize(self.bad_noisy_cnt);
				self.list.index = self.bad_noisy_cnt;
				break;
			};
			if (sm.score < evaluation.score.draw) {
				self.list.slice()[self.bad_noisy_cnt] = sm;
				self.bad_noisy_cnt += 1;
			} else return sm;
		}

		return null;
	}
};
