const engine = @import("engine");
const misc = @import("misc");
const std = @import("std");

// same as in psqt.zig

pub const mg_tbl = std.EnumArray(misc.types.Ptype, comptime_int).init(.{
	.nil = 0,
	.pawn   = 100,
	.knight = 320,
	.bishop = 330,
	.rook  = 500,
	.queen = 900,
	.king  = 0,
	.all = 0,
});

pub const eg_tbl = std.EnumArray(misc.types.Ptype, comptime_int).init(.{
	.nil = 0,
	.pawn   = 100,
	.knight = 315,
	.bishop = 335,
	.rook  = 500,
	.queen = 900,
	.king  = 0,
	.all = 0,
});

pub const tbl = init: {
	var tmp = std.mem.zeroInit(std.EnumArray(misc.types.Ptype, engine.evaluation.Pair), .{});
	for (misc.types.Ptype.values) |pt| {
		tmp.set(pt, .{
			.mg = engine.evaluation.score.fromCentipawns(mg_tbl.get(pt)),
			.eg = engine.evaluation.score.fromCentipawns(eg_tbl.get(pt)),
		});
	}
	break :init tmp;
};
