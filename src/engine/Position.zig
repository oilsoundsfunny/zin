const misc = @import("misc");
const std = @import("std");

const Zobrist = @import("Zobrist.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");

const Self = @This();

mailbox:	std.EnumArray(misc.types.Square, misc.types.Piece),
piece_occ:	std.EnumArray(misc.types.Piece,  misc.types.BitBoard),

pub const State = struct {
	castle:	 misc.types.Castle,
	en_pas:	?misc.types.Square,
	rule50:	 usize,

	key:	Zobrist.Int,
	pawn_key:	Zobrist.Int,
	minor_key:	Zobrist.Int,
	major_key:	Zobrist.Int,

	checkers:	misc.types.BitBoard,

	pub const Stack = struct {
		array:	std.BoundedArray(State, 1024),
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

pub fn colorOcc(self: Self, c: misc.types.Color) misc.types.BitBoard {
	return self.colorOccPtrConst(c).*;
}

pub fn pieceOcc(self: Self, p: misc.types.Piece) misc.types.BitBoard {
	return self.pieceOccPtrConst(p).*;
}
