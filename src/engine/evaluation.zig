const bitboard = @import("bitboard");
const nnue = @import("nnue");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const movegen = @import("movegen.zig");

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

	fn winrate(s: Int, mat: Int) Int {
		const p_a = [_]f32 { 6.87155862, -39.65226391,   90.68460352, 170.66996364};
		const p_b = [_]f32 {-7.19890710,  56.13947185, -139.91091183, 182.81007427};
		const fm: f32 = @floatFromInt(std.math.clamp(mat, 17, 78));
		const fs: f32 = @floatFromInt(s);

		var a: f32 = 0.0;
		var b: f32 = 0.0;
		for (p_a[0 ..], p_b[0 ..]) |param_a, param_b| {
			a = @mulAdd(f32, a, fm / 58.0, param_a);
			b = @mulAdd(f32, b, fm / 58.0, param_b);
		}

		const num = 1000.0;
		const den = 1.0 + @exp((a - fs) / b);
		return @intFromFloat(num / den);
	}

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

	pub fn wdl(s: Int, mat: Int) struct {Int, Int, Int} {
		const w = winrate(s, mat);
		const l = winrate(-s, mat);
		return .{w, 1000 - w - l, l};
	}
};
