const base = @import("base");
const engine = @import("engine");
const std = @import("std");

pub const psqt = psqt_init: {
	const bin = @embedFile("psqt.bin");
	var mem: [base.types.Ptype.cnt][base.types.Square.cnt]engine.evaluation.Pair = undefined;
	var tbl = std
	  .EnumArray(base.types.Ptype, std.EnumArray(base.types.Square, engine.evaluation.Pair))
	  .initUndefined();

	@memcpy(std.mem.sliceAsBytes(mem[0 ..]), bin[0 ..]);
	for (base.types.Ptype.values) |pt| {
		@memcpy(std.mem.sliceAsBytes(tbl.getPtr(pt).values[0 ..]), mem[pt.tag()][0 ..]);
	}
	break :psqt_init tbl;
};

pub const ptsc = ptsc_init: {
	const bin = @embedFile("ptsc.bin");
	var tbl = std.EnumArray(base.types.Ptype, engine.evaluation.Pair).initUndefined();
	@memcpy(std.mem.sliceAsBytes(tbl.values[0 ..]), bin[0 ..]);
	break :ptsc_init tbl;
};
