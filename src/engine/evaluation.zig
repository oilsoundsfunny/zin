const misc = @import("misc");
const std = @import("std");

pub const Score = enum(i16) {
	win  = 0 + 32767,
	draw = 0,
	lose = 0 - 32767,

	nil  = -32768,
	pawn = 256,

	_,

	pub const Int = std.meta.Tag(Score);

	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);

	pub fn centipawns(self: Score) Int {
		const s: isize = self.int();
		const d = @divTrunc(s * 100, Score.pawn.int());
		return @intCast(d);
	}

	pub fn int(self: Score) Int {
		return @intFromEnum(self);
	}

	pub fn fromCentipawns(cp: Int) Score {
		const c: isize = cp;
		const d = @divTrunc(c * Score.pawn.int(), 100);
		return fromInt(@intCast(d));
	}

	pub fn fromInt(i: Int) Score {
		return @enumFromInt(i);
	}
};
