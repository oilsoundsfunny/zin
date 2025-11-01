const std = @import("std");

pub const score = struct {
	const max = std.math.maxInt(i16);
	const min = std.math.minInt(i16);

	pub const Int = i32;

	pub const none = std.math.minInt(i16);
	pub const unit = 256;

	pub const win  = 0 + std.math.maxInt(i16);
	pub const draw = 0;
	pub const lose = 0 - std.math.maxInt(i16);

	pub const tbwin  = 0 + (max - 247);
	pub const tblose = 0 - (max - 247);

	pub fn toCentipawns(s: Int) Int {
		std.debug.assert(s < tbwin);
		std.debug.assert(s > tblose);

		const mul = s * 100;
		return @divTrunc(mul, unit);
	}
};
