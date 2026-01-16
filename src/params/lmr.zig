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
            const d: f32 = @floatFromInt(depth);
            const n: f32 = @floatFromInt(num);

            const noisy1: f32 = @floatFromInt(root.values.base_lmr_noisy1);
            const noisy0: f32 = @floatFromInt(root.values.base_lmr_noisy0);
            const noisy = @round(noisy0 + noisy1 * @log(d) * @log(n));

            const quiet1: f32 = @floatFromInt(root.values.base_lmr_quiet1);
            const quiet0: f32 = @floatFromInt(root.values.base_lmr_quiet0);
            const quiet = @round(quiet0 + quiet1 * @log(d) * @log(n));

            by_num.* = .{ @intFromFloat(noisy), @intFromFloat(quiet) };
        }
    }
}
