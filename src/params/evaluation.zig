const base = @import("base");
const engine = @import("engine");
const std = @import("std");

pub const ptsc = init: {
	const bin align(64) = @embedFile("ptsc.bin");
	var tbl align(64) = std.EnumArray(base.types.Ptype, engine.evaluation.Pair).initUndefined();

	@memcpy(std.mem.sliceAsBytes(tbl.values[0 ..]), bin[0 ..]);
	break :init tbl;
};
