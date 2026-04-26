const engine = @import("engine");
const std = @import("std");

const root = @import("root.zig");

var table: [32][32][2]engine.Thread.Depth = undefined;

pub fn get(depth: engine.Thread.Depth, searched: usize, quiet: bool) engine.Thread.Depth {
    const clamped_d: usize = @intCast(std.math.clamp(depth, 1, 32) - 1);
    const clamped_i: usize = @intCast(std.math.clamp(searched, 1, 32) - 1);
    return table[clamped_d][clamped_i][@intFromBool(quiet)];
}

pub fn init() !void {
    for (table[0..], 0..) |*by_depth, depth| {
        for (by_depth[0..], 0..) |*by_num, num| {
            if (depth == 0 or num == 0) {
                by_num.* = .{ 0, 0 };
                continue;
            }

            const d: f32 = @floatFromInt(depth);
            const n: f32 = @floatFromInt(num);

            const noisy_mult: f32 = @floatFromInt(root.values.base_lmr_noisy_mult);
            const noisy_bias: f32 = @floatFromInt(root.values.base_lmr_noisy_bias);
            const noisy = @round(noisy_mult * @log(d) * @log(n) + noisy_bias);

            const quiet_mult: f32 = @floatFromInt(root.values.base_lmr_quiet_mult);
            const quiet_bias: f32 = @floatFromInt(root.values.base_lmr_quiet_bias);
            const quiet = @round(quiet_mult * @log(d) * @log(n) + quiet_bias);

            by_num.* = .{ @intFromFloat(noisy), @intFromFloat(quiet) };
        }
    }
}
