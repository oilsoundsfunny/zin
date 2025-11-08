const bitboard = @import("bitboard");
const nnue = @import("nnue");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const Position = @import("Position.zig");

pub const score = struct {
	pub const Int = i32;

	pub const none = -32768;
	pub const unit = 256;

	pub const win  = 0 + 32767;
	pub const draw = 0;
	pub const lose = 0 - 32767;

	pub const tbwin  = 0 + 32640;
	pub const tblose = 0 - 32640;

	pub fn centipawns(s: Int) Int {
		std.debug.assert(s == std.math.clamp(s, lose, win));
		return @divTrunc(s * 100, unit);
	}

	pub fn fromPosition(pos: *const Position) Int {
		var ev = nnue.net.default.infer(pos);
		ev *= 128 - pos.ss.top().rule50;
		ev = @divTrunc(ev, 128);
		ev = std.math.clamp(ev, score.tblose + 1, score.tbwin - 1);
		return ev;
	}
};
