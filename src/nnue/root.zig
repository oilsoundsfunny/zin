const std = @import("std");

pub const Accumulator = @import("Accumulator.zig");
pub const arch = @import("arch.zig");
pub const Net = @import("net.zig").Self;

pub const net = init: {
	const b align(64) = @embedFile("embed.nn");
	var n: Net align(64) = undefined;
	@memcpy(std.mem.asBytes(&n), b[0 ..]);
	break :init n;
};
