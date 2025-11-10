const bitboard = @import("bitboard");
const nnue = @import("nnue");
const std = @import("std");
const types = @import("types");

const movegen = @import("movegen.zig");
const Position = @import("Position.zig");

pub const score = struct {
	const max = std.math.maxInt(i16);
	const min = std.math.minInt(i16);

	pub const Int = i32;

	pub const mate  = 0 + max;
	pub const mated = 0 - max;
	pub const none  = min;

	pub const win  = 0 + (max - 1 - movegen.Move.Root.capacity);
	pub const draw = 0;
	pub const lose = 0 - (max - 1 - movegen.Move.Root.capacity);

	pub fn isMate(s: Int) bool {
		return s == std.math.clamp(s, win, mate);
	}

	pub fn isMated(s: Int) bool {
		return s == std.math.clamp(s, mated, lose);
	}

	pub fn mateIn(ply: usize) Int {
		const i: Int = @intCast(ply);
		return mate - i;
	}

	pub fn matedIn(ply: usize) Int {
		const i: Int = @intCast(ply);
		return mated + i;
	}

	pub fn normalize(s: Int, mat: Int) Int {
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
		const inferred = nnue.net.default.infer(pos);
		const tapered = @divTrunc(inferred * (100 - pos.ss.top().rule50), 100);
		return std.math.clamp(tapered, lose + 1, win - 1);
	}
};
