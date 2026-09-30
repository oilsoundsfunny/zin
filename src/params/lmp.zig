const engine = @import("engine");
const std = @import("std");

const root = @import("root.zig");

var table: [32][2][2]u8 = undefined;

fn calc(depth: engine.Thread.Depth, improving: bool, is_direct_check: bool) u8 {
    const base = if (improving)
        root.values.lmp_improving_quad * depth * depth +
            root.values.lmp_improving_mult * depth +
            root.values.lmp_improving_bias
    else
        root.values.lmp_nonimproving_quad * depth * depth +
            root.values.lmp_nonimproving_mult * depth +
            root.values.lmp_nonimproving_bias;
    return @intCast(@max(@divTrunc(base, 1024) + @intFromBool(is_direct_check), 1));
}

pub fn get(depth: engine.Thread.Depth, improving: bool, is_direct_check: bool) usize {
    const d: usize = @intCast(std.math.clamp(depth, 1, 32) - 1);
    return table[d][@intFromBool(improving)][@intFromBool(is_direct_check)];
}

pub fn init() !void {
    for (table[0..], 1..) |*p, d| {
        p.* = .{
            // zig fmt: off
            .{ calc(@intCast(d), false, false), calc(@intCast(d), false, true) },
            .{ calc(@intCast(d), true,  false), calc(@intCast(d), true,  true) },
            // zig fmt: on
        };
    }
}
