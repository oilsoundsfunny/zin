const misc = @import("misc");
const std = @import("std");

const Self = @This();

psq:	std.EnumArray(misc.types.Square, std.EnumArray(misc.types.Piece, Int)),
castle:	std.EnumArray(misc.types.Castle, Int),
en_pas:	std.EnumArray(misc.types.File, Int),
stm:	std.EnumArray(misc.types.Color, Int),

pub const Int = misc.types.BitBoard.Int;
pub const default = init: {
	@setEvalBranchQuota(1 << 28);
	var sfc = std.Random.Sfc64.init(0xaa55aa55aa55aa55);
	var tbl = std.mem.zeroes(Self);

	for (misc.types.Square.values) |s| {
		for (misc.types.Piece.w_pieces) |p| {
			tbl.psq.getPtr(s).set(p, sfc.random().int(Int));
		}
		for (misc.types.Piece.b_pieces) |p| {
			tbl.psq.getPtr(s).set(p, sfc.random().int(Int));
		}
	}
	for (misc.types.Castle.min .. misc.types.Castle.max) |c| {
		tbl.castle.set(@enumFromInt(c), sfc.random().int(Int));
	}
	for (misc.types.File.values) |f| {
		tbl.en_pas.set(f, sfc.random().int(Int));
	}
	for (misc.types.Color.values) |c| {
		tbl.stm.set(c, sfc.random().int(Int));
	}

	break :init tbl;
};
