const bitboard = @import("bitboard");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");

const EvalTest = struct {
	fen:	[]const u8,
	centipawns:	isize,

	pub const suite = [_]EvalTest {
		.{
			.fen = "rn1qk2r/pb1pbppp/1p2pn2/8/2PQ4/2N2NP1/PP2PPBP/R1B2RK1 b kq - 0 8",
			.centipawns = 28,
		}, .{
			.fen = "6k1/4Rp1p/4p1p1/1P4N1/p2PPPnP/1r6/6P1/5K2 w - - 4 35",
			.centipawns = 0,
		},
	};
};

pub const score = struct {
	const pawn_f: comptime_float = @floatFromInt(pawn);

	pub const Int = i16;

	pub const win  = 0 + 32767;
	pub const draw = 0;
	pub const lose = 0 - 32767;

	pub const nil  = -32768;
	pub const pawn = 256;

	pub fn centipawns(eval: Int) isize {
		return @divTrunc(eval * 100, pawn);
	}

	pub fn fromCentipawns(c: isize) Int {
		return @divTrunc(c * pawn, 100);
	}
};

pub const Taper = struct {
	mg:	isize,
	eg:	isize,

	const phase = struct {
		pub const tbl = std.EnumArray(misc.types.Ptype, comptime_int).init(.{
			.nil = 0,
			.pawn   = 1,
			.knight = 3,
			.bishop = 3,
			.rook  = 5,
			.queen = 9,
			.king  = 0,
			.all = 0,
		});

		pub const max = 16 * tbl.get(.pawn)
		  + 4 * tbl.get(.knight)
		  + 4 * tbl.get(.bishop)
		  + 4 * tbl.get(.rook)
		  + 2 * tbl.get(.queen)
		  + 2 * tbl.get(.king);

		pub fn fromPosition(pos: Position) isize {
			var r: isize = 0;
			inline for (misc.types.Piece.w_pieces) |p| {
				r += @as(isize, pos.ptypeOcc(p.ptype()).cntSquares())
				  * tbl.get(p.ptype());
			}
			return r;
		}
	};

	pub const psqt = psqt_init: {
		@setEvalBranchQuota(1 << 28);
		const mg_tbl = std
		  .EnumArray(misc.types.Ptype, std.EnumArray(misc.types.Square, comptime_int)).init(.{
			.nil = std.mem.zeroes(std.EnumArray(misc.types.Square, comptime_int)),
			.pawn = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =  0, .b8 =  0, .c8 =  0, .d8 =  0, .e8 =  0, .f8 =  0, .g8 =  0, .h8 =  0,
				.a7 = 50, .b7 = 50, .c7 = 50, .d7 = 50, .e7 = 50, .f7 = 50, .g7 = 50, .h7 = 50,
				.a6 = 10, .b6 = 10, .c6 = 20, .d6 = 30, .e6 = 30, .f6 = 20, .g6 = 10, .h6 = 10,
				.a5 =  5, .b5 =  5, .c5 = 10, .d5 = 25, .e5 = 25, .f5 = 10, .g5 =  5, .h5 =  5,
				.a4 =  0, .b4 =  0, .c4 =  0, .d4 = 20, .e4 = 20, .f4 =  0, .g4 =  0, .h4 =  0,
				.a3 =  5, .b3 = -5, .c3 =-10, .d3 =  0, .e3 =  0, .f3 =-10, .g3 = -5, .h3 =  5,
				.a2 =  5, .b2 = 10, .c2 = 10, .d2 =-20, .e2 =-20, .f2 = 10, .g2 = 10, .h2 =  5,
				.a1 =  0, .b1 =  0, .c1 =  0, .d1 =  0, .e1 =  0, .f1 =  0, .g1 =  0, .h1 =  0,
			}),
			.knight = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =-50, .b8 =-40, .c8 =-30, .d8 =-30, .e8 =-30, .f8 =-30, .g8 =-40, .h8 =-50,
				.a7 =-40, .b7 =-20, .c7 =  0, .d7 =  0, .e7 =  0, .f7 =  0, .g7 =-20, .h7 =-40,
				.a6 =-30, .b6 =  0, .c6 = 10, .d6 = 15, .e6 = 15, .f6 = 10, .g6 =  0, .h6 =-30,
				.a5 =-30, .b5 =  5, .c5 = 15, .d5 = 20, .e5 = 20, .f5 = 15, .g5 =  5, .h5 =-30,
				.a4 =-30, .b4 =  0, .c4 = 15, .d4 = 20, .e4 = 20, .f4 = 15, .g4 =  0, .h4 =-30,
				.a3 =-30, .b3 =  5, .c3 = 10, .d3 = 15, .e3 = 15, .f3 = 10, .g3 =  5, .h3 =-30,
				.a2 =-40, .b2 =-20, .c2 =  0, .d2 =  5, .e2 =  5, .f2 =  0, .g2 =-20, .h2 =-40,
				.a1 =-50, .b1 =-40, .c1 =-30, .d1 =-30, .e1 =-30, .f1 =-30, .g1 =-40, .h1 =-50,
			}),
			.bishop = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =-20, .b8 =-10, .c8 =-10, .d8 =-10, .e8 =-10, .f8 =-10, .g8 =-10, .h8 =-20,
				.a7 =-10, .b7 =  0, .c7 =  0, .d7 =  0, .e7 =  0, .f7 =  0, .g7 =  0, .h7 =-10,
				.a6 =-10, .b6 =  0, .c6 =  5, .d6 = 10, .e6 = 10, .f6 =  5, .g6 =  0, .h6 =-10,
				.a5 =-10, .b5 =  5, .c5 =  5, .d5 = 10, .e5 = 10, .f5 =  5, .g5 =  5, .h5 =-10,
				.a4 =-10, .b4 =  0, .c4 = 10, .d4 = 10, .e4 = 10, .f4 = 10, .g4 =  0, .h4 =-10,
				.a3 =-10, .b3 = 10, .c3 = 10, .d3 = 10, .e3 = 10, .f3 = 10, .g3 = 10, .h3 =-10,
				.a2 =-10, .b2 =  5, .c2 =  0, .d2 =  0, .e2 =  0, .f2 =  0, .g2 =  5, .h2 =-10,
				.a1 =-20, .b1 =-10, .c1 =-10, .d1 =-10, .e1 =-10, .f1 =-10, .g1 =-10, .h1 =-20,
			}),
			.rook = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =  0, .b8 =  0, .c8 =  0, .d8 =  0, .e8 =  0, .f8 =  0, .g8 =  0, .h8 =  0,
				.a7 =  5, .b7 = 10, .c7 = 10, .d7 = 10, .e7 = 10, .f7 = 10, .g7 = 10, .h7 =  5,
				.a6 = -5, .b6 =  0, .c6 =  0, .d6 =  0, .e6 =  0, .f6 =  0, .g6 =  0, .h6 = -5,
				.a5 = -5, .b5 =  0, .c5 =  0, .d5 =  0, .e5 =  0, .f5 =  0, .g5 =  0, .h5 = -5,
				.a4 = -5, .b4 =  0, .c4 =  0, .d4 =  0, .e4 =  0, .f4 =  0, .g4 =  0, .h4 = -5,
				.a3 = -5, .b3 =  0, .c3 =  0, .d3 =  0, .e3 =  0, .f3 =  0, .g3 =  0, .h3 = -5,
				.a2 = -5, .b2 =  0, .c2 =  0, .d2 =  0, .e2 =  0, .f2 =  0, .g2 =  0, .h2 = -5,
				.a1 =  0, .b1 =  0, .c1 =  0, .d1 =  5, .e1 =  5, .f1 =  0, .g1 =  0, .h1 =  0,
			}),
			.queen = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =-20, .b8 =-10, .c8 =-10, .d8 = -5, .e8 = -5, .f8 =-10, .g8 =-10, .h8 =-20,
				.a7 =-10, .b7 =  0, .c7 =  0, .d7 =  0, .e7 =  0, .f7 =  0, .g7 =  0, .h7 =-10,
				.a6 =-10, .b6 =  0, .c6 =  5, .d6 =  5, .e6 =  5, .f6 =  5, .g6 =  0, .h6 =-10,
				.a5 = -5, .b5 =  0, .c5 =  5, .d5 =  5, .e5 =  5, .f5 =  5, .g5 =  0, .h5 = -5,
				.a4 =  0, .b4 =  0, .c4 =  5, .d4 =  5, .e4 =  5, .f4 =  5, .g4 =  0, .h4 =  0,
				.a3 =-10, .b3 =  5, .c3 =  5, .d3 =  5, .e3 =  5, .f3 =  5, .g3 =  5, .h3 =-10,
				.a2 =-10, .b2 =  0, .c2 =  5, .d2 =  0, .e2 =  0, .f2 =  5, .g2 =  0, .h2 =-10,
				.a1 =-20, .b1 =-10, .c1 =-10, .d1 = -5, .e1 = -5, .f1 =-10, .g1 =-10, .h1 =-20,
			}),
			.king = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =-30, .b8 =-40, .c8 =-40, .d8 =-50, .e8 =-50, .f8 =-40, .g8 =-40, .h8 =-30,
				.a7 =-30, .b7 =-40, .c7 =-40, .d7 =-50, .e7 =-50, .f7 =-40, .g7 =-40, .h7 =-30,
				.a6 =-30, .b6 =-40, .c6 =-40, .d6 =-50, .e6 =-50, .f6 =-40, .g6 =-40, .h6 =-30,
				.a5 =-30, .b5 =-40, .c5 =-40, .d5 =-50, .e5 =-50, .f5 =-40, .g5 =-40, .h5 =-30,
				.a4 =-20, .b4 =-30, .c4 =-30, .d4 =-40, .e4 =-40, .f4 =-30, .g4 =-30, .h4 =-20,
				.a3 =-10, .b3 =-20, .c3 =-20, .d3 =-20, .e3 =-20, .f3 =-20, .g3 =-20, .h3 =-10,
				.a2 = 20, .b2 = 20, .c2 =  0, .d2 =  0, .e2 =  0, .f2 =  0, .g2 = 20, .h2 = 20,
				.a1 = 20, .b1 = 30, .c1 = 10, .d1 =  0, .e1 =  0, .f1 = 10, .g1 = 30, .h1 = 20,
			}),
			.all = std.mem.zeroes(std.EnumArray(misc.types.Square, comptime_int)),
		});
		const eg_tbl = std
		  .EnumArray(misc.types.Ptype, std.EnumArray(misc.types.Square, comptime_int)).init(.{
			.nil = std.mem.zeroes(std.EnumArray(misc.types.Square, comptime_int)),
			.pawn = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =  0, .b8 =  0, .c8 =  0, .d8 =  0, .e8 =  0, .f8 =  0, .g8 =  0, .h8 =  0,
				.a7 = 50, .b7 = 50, .c7 = 50, .d7 = 50, .e7 = 50, .f7 = 50, .g7 = 50, .h7 = 50,
				.a6 = 10, .b6 = 10, .c6 = 20, .d6 = 30, .e6 = 30, .f6 = 20, .g6 = 10, .h6 = 10,
				.a5 =  5, .b5 =  5, .c5 = 10, .d5 = 25, .e5 = 25, .f5 = 10, .g5 =  5, .h5 =  5,
				.a4 =  0, .b4 =  0, .c4 =  0, .d4 = 20, .e4 = 20, .f4 =  0, .g4 =  0, .h4 =  0,
				.a3 =  5, .b3 = -5, .c3 =-10, .d3 =  0, .e3 =  0, .f3 =-10, .g3 = -5, .h3 =  5,
				.a2 =  5, .b2 = 10, .c2 = 10, .d2 =-20, .e2 =-20, .f2 = 10, .g2 = 10, .h2 =  5,
				.a1 =  0, .b1 =  0, .c1 =  0, .d1 =  0, .e1 =  0, .f1 =  0, .g1 =  0, .h1 =  0,
			}),
			.knight = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =-50, .b8 =-40, .c8 =-30, .d8 =-30, .e8 =-30, .f8 =-30, .g8 =-40, .h8 =-50,
				.a7 =-40, .b7 =-20, .c7 =  0, .d7 =  0, .e7 =  0, .f7 =  0, .g7 =-20, .h7 =-40,
				.a6 =-30, .b6 =  0, .c6 = 10, .d6 = 15, .e6 = 15, .f6 = 10, .g6 =  0, .h6 =-30,
				.a5 =-30, .b5 =  5, .c5 = 15, .d5 = 20, .e5 = 20, .f5 = 15, .g5 =  5, .h5 =-30,
				.a4 =-30, .b4 =  0, .c4 = 15, .d4 = 20, .e4 = 20, .f4 = 15, .g4 =  0, .h4 =-30,
				.a3 =-30, .b3 =  5, .c3 = 10, .d3 = 15, .e3 = 15, .f3 = 10, .g3 =  5, .h3 =-30,
				.a2 =-40, .b2 =-20, .c2 =  0, .d2 =  5, .e2 =  5, .f2 =  0, .g2 =-20, .h2 =-40,
				.a1 =-50, .b1 =-40, .c1 =-30, .d1 =-30, .e1 =-30, .f1 =-30, .g1 =-40, .h1 =-50,
			}),
			.bishop = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =-20, .b8 =-10, .c8 =-10, .d8 =-10, .e8 =-10, .f8 =-10, .g8 =-10, .h8 =-20,
				.a7 =-10, .b7 =  0, .c7 =  0, .d7 =  0, .e7 =  0, .f7 =  0, .g7 =  0, .h7 =-10,
				.a6 =-10, .b6 =  0, .c6 =  5, .d6 = 10, .e6 = 10, .f6 =  5, .g6 =  0, .h6 =-10,
				.a5 =-10, .b5 =  5, .c5 =  5, .d5 = 10, .e5 = 10, .f5 =  5, .g5 =  5, .h5 =-10,
				.a4 =-10, .b4 =  0, .c4 = 10, .d4 = 10, .e4 = 10, .f4 = 10, .g4 =  0, .h4 =-10,
				.a3 =-10, .b3 = 10, .c3 = 10, .d3 = 10, .e3 = 10, .f3 = 10, .g3 = 10, .h3 =-10,
				.a2 =-10, .b2 =  5, .c2 =  0, .d2 =  0, .e2 =  0, .f2 =  0, .g2 =  5, .h2 =-10,
				.a1 =-20, .b1 =-10, .c1 =-10, .d1 =-10, .e1 =-10, .f1 =-10, .g1 =-10, .h1 =-20,
			}),
			.rook = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =  0, .b8 =  0, .c8 =  0, .d8 =  0, .e8 =  0, .f8 =  0, .g8 =  0, .h8 =  0,
				.a7 =  5, .b7 = 10, .c7 = 10, .d7 = 10, .e7 = 10, .f7 = 10, .g7 = 10, .h7 =  5,
				.a6 = -5, .b6 =  0, .c6 =  0, .d6 =  0, .e6 =  0, .f6 =  0, .g6 =  0, .h6 = -5,
				.a5 = -5, .b5 =  0, .c5 =  0, .d5 =  0, .e5 =  0, .f5 =  0, .g5 =  0, .h5 = -5,
				.a4 = -5, .b4 =  0, .c4 =  0, .d4 =  0, .e4 =  0, .f4 =  0, .g4 =  0, .h4 = -5,
				.a3 = -5, .b3 =  0, .c3 =  0, .d3 =  0, .e3 =  0, .f3 =  0, .g3 =  0, .h3 = -5,
				.a2 = -5, .b2 =  0, .c2 =  0, .d2 =  0, .e2 =  0, .f2 =  0, .g2 =  0, .h2 = -5,
				.a1 =  0, .b1 =  0, .c1 =  0, .d1 =  5, .e1 =  5, .f1 =  0, .g1 =  0, .h1 =  0,
			}),
			.queen = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =-20, .b8 =-10, .c8 =-10, .d8 = -5, .e8 = -5, .f8 =-10, .g8 =-10, .h8 =-20,
				.a7 =-10, .b7 =  0, .c7 =  0, .d7 =  0, .e7 =  0, .f7 =  0, .g7 =  0, .h7 =-10,
				.a6 =-10, .b6 =  0, .c6 =  5, .d6 =  5, .e6 =  5, .f6 =  5, .g6 =  0, .h6 =-10,
				.a5 = -5, .b5 =  0, .c5 =  5, .d5 =  5, .e5 =  5, .f5 =  5, .g5 =  0, .h5 = -5,
				.a4 =  0, .b4 =  0, .c4 =  5, .d4 =  5, .e4 =  5, .f4 =  5, .g4 =  0, .h4 =  0,
				.a3 =-10, .b3 =  5, .c3 =  5, .d3 =  5, .e3 =  5, .f3 =  5, .g3 =  5, .h3 =-10,
				.a2 =-10, .b2 =  0, .c2 =  5, .d2 =  0, .e2 =  0, .f2 =  5, .g2 =  0, .h2 =-10,
				.a1 =-20, .b1 =-10, .c1 =-10, .d1 = -5, .e1 = -5, .f1 =-10, .g1 =-10, .h1 =-20,
			}),
			.king = std.EnumArray(misc.types.Square, comptime_int).init(.{
				.a8 =-50, .b8 =-40, .c8 =-30, .d8 =-20, .e8 =-20, .f8 =-30, .g8 =-40, .h8 =-50,
				.a7 =-30, .b7 =-20, .c7 =-10, .d7 =  0, .e7 =  0, .f7 =-10, .g7 =-20, .h7 =-30,
				.a6 =-30, .b6 =-10, .c6 = 20, .d6 = 30, .e6 = 30, .f6 = 20, .g6 =-10, .h6 =-30,
				.a5 =-30, .b5 =-10, .c5 = 30, .d5 = 40, .e5 = 40, .f5 = 30, .g5 =-10, .h5 =-30,
				.a4 =-30, .b4 =-10, .c4 = 30, .d4 = 40, .e4 = 40, .f4 = 30, .g4 =-10, .h4 =-30,
				.a3 =-30, .b3 =-10, .c3 = 20, .d3 = 30, .e3 = 30, .f3 = 20, .g3 =-10, .h3 =-30,
				.a2 =-30, .b2 =-30, .c2 =  0, .d2 =  0, .e2 =  0, .f2 =  0, .g2 =-30, .h2 =-30,
				.a1 =-50, .b1 =-30, .c1 =-30, .d1 =-30, .e1 =-30, .f1 =-30, .g1 =-30, .h1 =-50,
			}),
			.all = std.mem.zeroes(std.EnumArray(misc.types.Square, comptime_int)),
		});
		var tbl = std.mem
		  .zeroes(std.EnumArray(misc.types.Ptype, std.EnumArray(misc.types.Square, Taper)));

		for (misc.types.Piece.w_pieces) |p| {
			const pt = p.ptype();
			for (misc.types.Square.values) |s| {
				tbl.getPtr(pt).set(s, .{
					.mg = score.fromCentipawns(mg_tbl.get(pt).get(s)),
					.eg = score.fromCentipawns(eg_tbl.get(pt).get(s)),
				});
			}
		}
		break :psqt_init tbl;
	};

	pub fn dither(self: Taper, scale: isize) isize {
		const clamped = std.math.clamp(scale, 0, phase.max);
		return @divTrunc(self.mg * clamped + self.eg * (phase.max - clamped), phase.max);
	}
};
test {
	_ = Taper.psqt;
}

pub const Ft = struct {
	piece_atk:	std.EnumArray(misc.types.Piece, misc.types.BitBoard),
	passed_pawns:	std.EnumArray(misc.types.Color, misc.types.BitBoard),
	mobile_area:	std.EnumArray(misc.types.Color, misc.types.BitBoard),
	king_area:	std.EnumArray(misc.types.Color, misc.types.BitBoard),
	king_atk_cnt:	std.EnumArray(misc.types.Color, isize),
	king_atk_mat:	std.EnumArray(misc.types.Color, isize),
	king_def_cnt:	std.EnumArray(misc.types.Color, isize),
	king_def_mat:	std.EnumArray(misc.types.Color, isize),

	fn evalKing(self: Ft, pos: Position, comptime mg: bool) isize {
		const stm = pos.stm;
		var ev: isize = 0;

		_ = self;

		const kings = std.EnumArray(misc.types.Color, misc.types.BitBoard).init(.{
			.white = pos.pieceOcc(misc.types.Piece.fromPtype(.white, .king)),
			.black = pos.pieceOcc(misc.types.Piece.fromPtype(.black, .king)),
		});
		inline for (misc.types.Color.values) |c| {
			const b = switch (c) {
				.white => kings.get(c),
				.black => kings.get(c).flipRank(),
			};
			const s = b.lowSquare();
			switch (c) {
				.white => ev += if (mg) Taper.psqt.get(.king).get(s).mg
					else Taper.psqt.get(.king).get(s).eg,
				.black => ev -= if (mg) Taper.psqt.get(.king).get(s).mg
					else Taper.psqt.get(.king).get(s).eg,
			}
		}

		return switch (stm) {
			.white =>  ev,
			.black => -ev,
		};
	}

	fn evalPawn(self: Ft, pos: Position, comptime mg: bool) isize {
		const stm = pos.stm;
		var ev: isize = 0;

		_ = self;

		const pawns = std.EnumArray(misc.types.Color, misc.types.BitBoard).init(.{
			.white = pos.pieceOcc(misc.types.Piece.fromPtype(.white, .pawn)),
			.black = pos.pieceOcc(misc.types.Piece.fromPtype(.black, .pawn)),
		});
		inline for (misc.types.Color.values) |c| {
			var b = switch (c) {
				.white => pawns.get(c),
				.black => pawns.get(c).flipRank(),
			};
			while (b != .nil) : (b.popLow()) {
				const s = b.lowSquare();
				switch (c) {
					.white => ev += if (mg) Taper.psqt.get(.pawn).get(s).mg
						else Taper.psqt.get(.pawn).get(s).eg,
					.black => ev -= if (mg) Taper.psqt.get(.pawn).get(s).mg
						else Taper.psqt.get(.pawn).get(s).eg,
				}
			}
		}

		return switch (stm) {
			.white =>  ev,
			.black => -ev,
		};
	}

	fn evalPtype(self: Ft, pos: Position,
	  comptime pt: misc.types.Ptype,
	  comptime mg: bool) isize {
		const stm = pos.stm;
		var ev: isize = 0;

		_ = self;

		const pieces = std.EnumArray(misc.types.Color, misc.types.BitBoard).init(.{
			.white = pos.pieceOcc(misc.types.Piece.fromPtype(.white, pt)),
			.black = pos.pieceOcc(misc.types.Piece.fromPtype(.black, pt)),
		});
		inline for (misc.types.Color.values) |c| {
			var b = switch (c) {
				.white => pieces.get(c),
				.black => pieces.get(c).flipRank(),
			};
			while (b != .nil) : (b.popLow()) {
				const s = b.lowSquare();
				switch (c) {
					.white => ev += if (mg) Taper.psqt.get(pt).get(s).mg
						else Taper.psqt.get(pt).get(s).eg,
					.black => ev -= if (mg) Taper.psqt.get(pt).get(s).mg
						else Taper.psqt.get(pt).get(s).eg,
				}
			}
		}

		return switch (stm) {
			.white =>  ev,
			.black => -ev,
		};
	}

	pub fn init(pos: Position) Ft {
		var tbl = std.mem.zeroes(Ft);
		const occ = pos.allOcc();

		
		inline for (misc.types.Color.values) |c| {
			const all_piece = misc.types.Piece.fromPtype(c, .all);

			const pawn = misc.types.Piece.fromPtype(c, .pawn);
			tbl.piece_atk.set(pawn, bitboard.pAtk(pos.pieceOcc(pawn), c));
			tbl.piece_atk.set(all_piece, bitboard.pAtk(pos.pieceOcc(pawn), c));

			const pieces = switch (c) {
				.white => misc.types.Piece.w_pieces,
				.black => misc.types.Piece.b_pieces,
			}[1 ..];

			inline for (pieces) |p| {
				var b = pos.pieceOcc(p);
				while (b != .nil) : (b.popLow()) {
					const s = b.lowSquare();
					tbl.piece_atk.set(p,
					  tbl.piece_atk.get(p).bitOr(bitboard.ptAtk(p.ptype(), s, occ)));
				}
				tbl.piece_atk.set(all_piece,
					  tbl.piece_atk.get(all_piece).bitOr(tbl.piece_atk.get(p)));
			}
		}

		return tbl;
	}

	pub fn eval(self: Ft, pos: Position) isize {
		const by_ptype = std.EnumArray(misc.types.Ptype, Taper).init(.{
			.nil = undefined,
			.pawn = .{
				.mg = self.evalPawn(pos, true),
				.eg = self.evalPawn(pos, false),
			},
			.knight = .{
				.mg = self.evalPtype(pos, .knight, true),
				.eg = self.evalPtype(pos, .knight, false),
			},
			.bishop = .{
				.mg = self.evalPtype(pos, .bishop, true),
				.eg = self.evalPtype(pos, .bishop, false),
			},
			.rook = .{
				.mg = self.evalPtype(pos, .rook, true),
				.eg = self.evalPtype(pos, .rook, false),
			},
			.queen = .{
				.mg = self.evalPtype(pos, .queen, true),
				.eg = self.evalPtype(pos, .queen, false),
			},
			.king = .{
				.mg = self.evalKing(pos, true),
				.eg = self.evalKing(pos, false),
			},
			.all = undefined,
		});

		const accum = Taper {
			.mg = by_ptype.get(.pawn).mg + by_ptype.get(.knight).mg + by_ptype.get(.bishop).mg
			  + by_ptype.get(.rook).mg + by_ptype.get(.queen).mg + by_ptype.get(.king).mg,
			.eg = by_ptype.get(.pawn).eg + by_ptype.get(.knight).eg + by_ptype.get(.bishop).eg
			  + by_ptype.get(.rook).eg + by_ptype.get(.queen).eg + by_ptype.get(.king).eg,
		};
		const phase = Taper.phase.fromPosition(pos);

		var ev = accum.dither(phase);
		ev = @divTrunc(ev * (100 - pos.ssTop().rule50), 100);
		return ev;
	}
};

pub fn scorePosition(pos: Position) isize {
	const ft = Ft.init(pos);
	return ft.eval(pos);
}
