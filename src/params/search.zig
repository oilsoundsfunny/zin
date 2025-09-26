const base = @import("base");
const engine = @import("engine");
const std = @import("std");

pub const lmr = lmr_init: {
	@setEvalBranchQuota(1 << 16);
	var tbl: [32][32][2]u8 = undefined;

	for (tbl[0 ..], 0 ..) |*by_d, d| {
		@memset(std.mem.asBytes(by_d), 0);
		if (d == 0) {
			continue;
		}

		for (by_d[1 ..], 1 ..) |*by_n, n| {
			// TODO: tune instead yoinking from Weiss

			const ld = @log(@as(f64, @floatFromInt(d)));
			const ln = @log(@as(f64, @floatFromInt(n)));

			const noisy = 0.20 + ld * ln / 3.35;
			const quiet = 1.35 + ld * ln / 2.75;

			by_n[0] = @intFromFloat(noisy);
			by_n[1] = @intFromFloat(quiet);
		}
	}

	break :lmr_init tbl;
};
