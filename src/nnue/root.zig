const std = @import("std");

pub const Accumulator = @import("Accumulator.zig");
pub const arch = @import("arch.zig");
pub const Net = @import("net.zig").Self;

pub const net = init: {
	@setEvalBranchQuota(1 << 20);
	var n = std.mem.zeroes(Net);
	var r = std.Random.Xoroshiro128.init(0x43e694c47dd8195b);

	for (std.mem.bytesAsSlice(i16, std.mem.asBytes(&n))) |*p| {
		const i = @divTrunc(r.random().int(i16), 256);
		p.* = i;
	}
	break :init n;
};
