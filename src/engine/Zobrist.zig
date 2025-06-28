const misc = @import("misc");
const std = @import("std");

const Self = @This();

psq:	std.EnumArray(misc.types.Square, std.EnumArray(misc.types.Piece, Int)),
cas:	std.EnumArray(misc.types.Castle, Int),
enp:	std.EnumArray(misc.types.File, Int),
stm:	Int,

pub const Int = misc.types.BitBoard.Int;

pub const default = init: {
	@setEvalBranchQuota(1 << 24);
	var sfc = std.Random.Sfc64
	  .init(0b01010101010101010101010101010101010101010101010101010101010101010101010101010101);
	var tbl = std.mem.zeroes(Self);

	for (misc.types.Square.values) |s| {
		for (misc.types.Piece.w_pieces) |p| {
			tbl.getPtr(s).set(p, sfc.random().int(Int));
		}
		for (misc.types.Piece.b_pieces) |p| {
			tbl.getPtr(s).set(p, sfc.random().int(Int));
		}
	}

	for (misc.types.Castle.min .. misc.types.Castle.max) |c| {
		tbl.set(misc.types.Castle.fromInt(@truncate(c)), sfc.random().int(Int));
	}

	for (misc.types.File.values) |f| {
		tbl.set(f, sfc.random().int(Int));
	}

	tbl.stm = sfc.random().int(Int);

	break :init tbl;
};
