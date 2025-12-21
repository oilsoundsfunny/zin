const engine = @import("engine");
const std = @import("std");

var table: [32][32][2]u8 = undefined;

pub fn get(depth: engine.Thread.Depth, searched: usize, quiet: bool) u8 {
	const clamped_d: usize = @intCast(std.math.clamp(depth, 0, 31));
	const clamped_i: usize = @intCast(std.math.clamp(searched, 0, 31));
	return table[clamped_d][clamped_i][@intFromBool(quiet)];
}

pub fn init() !void {
	for (table[0 ..], 0 ..) |*by_depth, depth| {
		for (by_depth[0 ..], 0 ..) |*by_num, num| {
			if (depth == 0 or num == 0) {
				by_num.* = .{0, 0};
				continue;
			}

			const d: f32 = @floatFromInt(depth);
			const n: f32 = @floatFromInt(num);

			const noisy = 0.20 + @log(d) * @log(n) / 3.35;
			const quiet = 1.35 + @log(d) * @log(n) / 2.75;
			by_num.* = .{@intFromFloat(noisy), @intFromFloat(quiet)};
		}
	}
}
