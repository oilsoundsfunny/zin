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
    const noisy_mult: f64 = @floatFromInt(root.values.lmr_init_noisy_mult);
    const noisy_bias: f64 = @floatFromInt(root.values.lmr_init_noisy_bias);
    const quiet_mult: f64 = @floatFromInt(root.values.lmr_init_quiet_mult);
    const quiet_bias: f64 = @floatFromInt(root.values.lmr_init_quiet_bias);

    for (table[0..], 1..) |*pd, depth| {
        for (pd[0..], 1..) |*pn, num| {
            const d: f64 = @floatFromInt(depth);
            const n: f64 = @floatFromInt(num);

            const noisy = @round(noisy_bias + noisy_mult * @log(d) * @log(n));
            const quiet = @round(quiet_bias + quiet_mult * @log(d) * @log(n));
            pn.* = .{ @intFromFloat(noisy), @intFromFloat(quiet) };
        }
    }
}
