const base = @import("base");
const std = @import("std");

pub var tbl: [32][32][2]u8 = undefined;

pub fn init() void {
	for (0 .. 32) |d| {
		for (0 .. 32) |n| {
			const p = &tbl[d][n];
			if (d == 0 or n == 0) {
				p.* = .{ 0, 0 };
				continue;
			}

			const ld = @log(@as(f64, @floatFromInt(d)));
			const ln = @log(@as(f64, @floatFromInt(n)));

			p.* = .{
				@intFromFloat(0.20 + ld * ln / 3.35),
				@intFromFloat(1.35 + ld * ln / 2.75),
			};
		}
	}
}
