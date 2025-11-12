const bitboard = @import("bitboard");
const nnue = @import("nnue");
const std = @import("std");
const types = @import("types");

const Position = @import("Position.zig");

pub const score = struct {
	pub const Int = i32;

	pub const none = -32768;

	pub const win  = 0 + 32767;
	pub const draw = 0;
	pub const lose = 0 - 32767;

	pub const tbwin  = 0 + 32640;
	pub const tblose = 0 - 32640;

	pub fn centipawns(s: Int, mat: Int) Int {
		const params = [_]f32 {
			6.87155862, -39.65226391, 90.68460352, 170.66996364,
		};
		const fm: f32 = @floatFromInt(@max(mat, 10));
		const fs: f32 = @floatFromInt(s);

		var x = params[0];
		for (params[1 ..]) |k| {
			x = @mulAdd(f32, x, fm / 58.0, k);
		}
		return @intFromFloat(@round(100.0 * fs / x));
	}

	pub fn fromPosition(pos: *const Position) Int {
		var ev = nnue.net.default.infer(pos);
		ev *= 128 - pos.ss.top().rule50;
		ev = @divTrunc(ev, 128);
		ev = std.math.clamp(ev, score.tblose + 1, score.tbwin - 1);
		return ev;
	}
};
