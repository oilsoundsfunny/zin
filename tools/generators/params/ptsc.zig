const base = @import("base");
const root = @import("root");
const std = @import("std");

pub const tbl = std.EnumArray(base.types.Ptype, root.Pair).init(.{
	.nul = .{ .mg = 0, .eg = 0 },
	.all = .{ .mg = 0, .eg = 0 },

	.pawn = .{
		.mg = base.defs.score.fromCentipawns(100),
		.eg = base.defs.score.fromCentipawns(100),
	},

	.knight = .{
		.mg = base.defs.score.fromCentipawns(300),
		.eg = base.defs.score.fromCentipawns(300),
	},

	.bishop = .{
		.mg = base.defs.score.fromCentipawns(300),
		.eg = base.defs.score.fromCentipawns(300),
	},

	.rook = .{
		.mg = base.defs.score.fromCentipawns(500),
		.eg = base.defs.score.fromCentipawns(500),
	},

	.queen = .{
		.mg = base.defs.score.fromCentipawns(900),
		.eg = base.defs.score.fromCentipawns(900),
	},

	.king = .{
		.mg = base.defs.score.draw,
		.eg = base.defs.score.draw,
	},
});

pub fn init() void {
}
