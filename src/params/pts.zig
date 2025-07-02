const engine = @import("engine");
const misc = @import("misc");
const std = @import("std");

// same as in psqt.zig

pub const mg_tbl = std.EnumArray(misc.types.Ptype, comptime_int).init(.{
	.nil = 0,
	.pawn   = 256,
	.knight = 800,
	.bishop = 864,
	.rook  = 1280,
	.queen = 2304,
	.king  = 0,
	.all = 0,
});

pub const eg_tbl = std.EnumArray(misc.types.Ptype, comptime_int).init(.{
	.nil = 0,
	.pawn   = 256,
	.knight = 784,
	.bishop = 880,
	.rook  = 1280,
	.queen = 2304,
	.king  = 0,
	.all = 0,
});

pub const tbl = init: {
	var tmp = std.mem.zeroInit(std.EnumArray(misc.types.Ptype, engine.evaluation.Pair), .{});
	for (misc.types.Ptype.values) |pt| {
		tmp.set(pt, .{
			.mg = mg_tbl.get(pt),
			.eg = eg_tbl.get(pt),
		});
	}
	break :init tmp;
};
