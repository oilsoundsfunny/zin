const bitboard = @import("bitboard");
const misc = @import("misc");
const std = @import("std");

const Zobrist = @import("Zobrist.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");

const Self = @This();

mailbox:	std.EnumArray(misc.types.Square, misc.types.Piece)
  = std.EnumArray(misc.types.Square, misc.types.Piece).initFill(.nil),
piece_occ:	std.EnumArray(misc.types.Piece,  misc.types.BitBoard)
  = std.EnumArray(misc.types.Piece,  misc.types.BitBoard).initFill(.nil),

side2move:	misc.types.Color = .white,
game_len:	usize = 1,

ss:	State.Stack = .{},

pub const State = struct {
	castle:	 misc.types.Castle = .nil,
	en_pas:	?misc.types.Square = null,
	rule50:	 usize = 0,

	key:	Zobrist.Int = 0,
	pawn_key:	Zobrist.Int = 0,
	minor_key:	Zobrist.Int = 0,
	major_key:	Zobrist.Int = 0,

	checkers:	misc.types.BitBoard = .nil,

	pub const Stack = struct {
		array:	std.BoundedArray(State, 1024) = .{
			.buffer = .{Stack {}} ** 1024,
			.len = offset,
		},

		pub const length = 1024;
		pub const offset = 8;
	};
};

fn colorOccPtr(self: *Self, c: misc.types.Color) *misc.types.BitBoard {
	return self.pieceOccPtr(misc.types.Piece.fromPtype(c, .all));
}

fn pieceOccPtr(self: *Self, p: misc.types.Piece) *misc.types.BitBoard {
	return self.piece_occ.getPtr(p);
}

fn colorOccPtrConst(self: *const Self, c: misc.types.Color) *const misc.types.BitBoard {
	return self.pieceOccPtrConst(misc.types.Piece.fromPtype(c, .all));
}

fn pieceOccPtrConst(self: *const Self, p: misc.types.Piece) *const misc.types.BitBoard {
	return self.piece_occ.getPtrConst(p);
}

fn genCheckers(self: Self, checked_side: misc.types.Color) misc.types.BitBoard {
	const our_king = misc.types.Piece.fromPtype(checked_side, .king);
	const k_bb = self.pieceOcc(our_king);
	const k_sq = k_bb.lowSquare();

	const their_pieces = std.EnumArray(misc.types.Ptype, misc.types.BitBoard).init(.{
		.nil = undefined,
		.pawn   = self.pieceOcc(misc.types.Piece.fromPtype(checked_side.flip(), .pawn)),
		.knight = self.pieceOcc(misc.types.Piece.fromPtype(checked_side.flip(), .knight)),
		.bishop = self.pieceOcc(misc.types.Piece.fromPtype(checked_side.flip(), .bishop)),
		.rook   = self.pieceOcc(misc.types.Piece.fromPtype(checked_side.flip(), .rook)),
		.queen  = self.pieceOcc(misc.types.Piece.fromPtype(checked_side.flip(), .queen)),
		.king   = self.pieceOcc(misc.types.Piece.fromPtype(checked_side.flip(), .king)),
		.all = undefined,
	});
	const occ = self.allOcc();
	var atk = bitboard.pAtk(k_bb, checked_side).bitAnd(their_pieces.get(.pawn))
	  .bitOr(bitboard.nAtk(k_sq).bitAnd(their_pieces.get(.knight)))
	  .bitOr(bitboard.kAtk(k_sq).bitAnd(their_pieces.get(.king)));

	const diag = their_pieces.get(.queen).bitOr(their_pieces.get(.bishop));
	var k_ba = bitboard.bAtk(k_sq, occ).bitAnd(diag);
	while (k_ba != .nil) : (k_ba.popLow()) {
		const s = k_ba.lowSquare();
		atk = atk.bitOr(s.bb()).bitOr(bitboard.bAtk(s, occ).bitAnd(k_ba));
	}

	const line = their_pieces.get(.queen).bitOr(their_pieces.get(.rook));
	var k_ra = bitboard.rAtk(k_sq, occ).bitAnd(line);
	while (k_ra != .nil) : (k_ra.popLow()) {
		const s = k_ra.lowSquare();
		atk = atk.bitOr(s.bb()).bitOr(bitboard.rAtk(s, occ).bitAnd(k_ra));
	}

	return if (atk != .nil) atk else .all;
}

fn genKey(self: Self) Zobrist.Int {
	var z = Zobrist.default.cas.get(self.ss.top().castle)
	  ^ (if (self.ss.top().en_pas) |s| Zobrist.default.enp.get(s.file()) else 0)
	  ^ (if (self.stm == .white) Zobrist.default.stm else 0);

	for (misc.types.Piece.w_pieces) |p| {
		var b = self.pieceOcc(p);
		while (b != .nil) : (b.popLow()) {
			const s = b.lowSquare();
			z ^= Zobrist.default.get(s).get(p);
		}
	}

	for (misc.types.Piece.b_pieces) |p| {
		var b = self.pieceOcc(p);
		while (b != .nil) : (b.popLow()) {
			const s = b.lowSquare();
			z ^= Zobrist.default.get(s).get(p);
		}
	}

	return z;
}

pub fn colorOcc(self: Self, c: misc.types.Color) misc.types.BitBoard {
	return self.colorOccPtrConst(c).*;
}

pub fn pieceOcc(self: Self, p: misc.types.Piece) misc.types.BitBoard {
	return self.pieceOccPtrConst(p).*;
}

pub fn ptypeOcc(self: Self, p: misc.types.Ptype) misc.types.BitBoard {
	return misc.types.BitBoard.nil
	  .bitOr(self.pieceOcc(misc.types.Piece.fromPtype(.white, p)))
	  .bitOr(self.pieceOcc(misc.types.Piece.fromPtype(.black, p)));
}
