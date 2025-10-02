const base = @import("base");
const engine = @import("engine");
const std = @import("std");

pub const psqt = init: {
	@setEvalBranchQuota(1 << 16);
	const T = std
	  .EnumArray(base.types.Ptype, std.EnumArray(base.types.Square, engine.evaluation.Pair));
	const bin = @embedFile("psqt.bin");
	var mem align(64)
	  = std.mem.zeroes([base.types.Ptype.cnt][base.types.Square.cnt]engine.evaluation.Pair);
	var tbl align(64) = T.initUndefined();

	@memcpy(std.mem.sliceAsBytes(mem[0 ..]), bin[0 ..]);
	for (base.types.Ptype.values) |pt| {
		for (base.types.Square.values) |s| {
			const dst = tbl.getPtr(pt).getPtr(s);
			const src = &mem[pt.tag()][s.tag()];

			dst.* = src.*;
		}
	}
	break :init tbl;
};

pub const ptsc = init: {
	const bin = @embedFile("ptsc.bin");
	var mem align(64) = std.mem.zeroes([base.types.Ptype.cnt]engine.evaluation.Pair);
	var tbl align(64) = std.EnumArray(base.types.Ptype, engine.evaluation.Pair).initUndefined();

	@memcpy(std.mem.sliceAsBytes(mem[0 ..]), bin[0 ..]);
	for (base.types.Ptype.values) |pt| {
			tbl.set(pt, mem[pt.tag()]);
	}
	break :init tbl;
};
