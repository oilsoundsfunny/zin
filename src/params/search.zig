const base = @import("base");
const engine = @import("engine");
const std = @import("std");

pub const lmr = init: {
	const bin = @embedFile("lmr.bin");
	var tbl: [32][32][2]u8 = undefined;
	@memcpy(std.mem.sliceAsBytes(tbl[0 ..]), bin[0 ..]);
	break :init tbl;
};
