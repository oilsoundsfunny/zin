const std = @import("std");

pub const score = struct {
	pub const Int = i32;

	pub const none = std.math.minInt(i16);
	pub const unit = 256;

	pub const win  = 0 + std.math.maxInt(i16);
	pub const draw = 0;
	pub const lose = 0 - std.math.maxInt(i16);

	pub const tbwin  = win  - 247;
	pub const tblose = lose + 247;

	pub fn fromCentipawns(c: Int) Int {
		std.debug.assert(c == std.math.clamp(c, lose, win));
		const m = c * unit;
		const d = @divTrunc(m, 100);
		return d;
	}

	pub fn toCentipawns(s: Int) Int {
		std.debug.assert(s == std.math.clamp(s, lose, win));
		const m = s * 100;
		const d = @divTrunc(m, 256);
		return d;
	}
};
