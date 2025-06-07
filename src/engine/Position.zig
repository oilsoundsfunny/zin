const bitboard = @import("bitboard");
const builtin = @import("builtin");
const misc = @import("misc");
const std = @import("std");

const Zobrist = @import("Zobrist.zig");
const movegen = @import("movegen.zig");

const Self = @This();

mailbox:	std.EnumArray(misc.types.Square, misc.types.Piece),
piece_occ:	std.EnumArray(misc.types.Piece,  misc.types.BitBoard),
stm:	misc.types.Color,

game_len:	usize,
ss_ply:		usize,
ss:	[128]Stack,

pub const FenError = error {
	InvalidPiece,
	InvalidSquare,
	InvalidStm,
	InvalidCastle,
	InvalidEnPassant,
	InvalidHalfMoveClock,
	InvalidMoveClock,
	InvalidFen,
};

pub const MoveError = error {
	InvalidFlag,
	InvalidPromotion,
	InvalidSrc,
	InvalidDst,
	InvalidSrcPiece,
	InvalidDstPiece,
	InvalidMove,
};

pub const Stack = struct {
	move:	movegen.Move,
	src_piece:	misc.types.Piece,
	dst_piece:	misc.types.Piece,

	castle:	misc.types.Castle,
	chk:	misc.types.BitBoard,
	en_pas:	?misc.types.Square,
	key:	Zobrist.Int,
	rule50:	u8,
};

fn colorOccPtr(self: *Self, c: misc.types.Color) *misc.types.BitBoard {
	return self.pieceOccPtr(misc.types.Piece.fromPtype(c, .all));
}
fn pieceOccPtr(self: *Self, p: misc.types.Piece) *misc.types.BitBoard {
	return self.piece_occ.getPtr(p);
}
fn squarePtr(self: *Self, s: misc.types.Square) *misc.types.Piece {
	return self.mailbox.getPtr(s);
}
fn ssTopPtr(self: *Self) [*]Stack {
	return self.ss[self.ss_ply ..].ptr;
}

fn colorOccPtrConst(self: *const Self, c: misc.types.Color) *const misc.types.BitBoard {
	return self.pieceOccPtrConst(misc.types.Piece.fromPtype(c, .all));
}
fn pieceOccPtrConst(self: *const Self, p: misc.types.Piece) *const misc.types.BitBoard {
	return self.piece_occ.getPtrConst(p);
}
fn squarePtrConst(self: *const Self, s: misc.types.Square) *const misc.types.Piece {
	return self.mailbox.getPtrConst(s);
}
fn ssTopPtrConst(self: *const Self) [*]const Stack {
	return self.ss[self.ss_ply ..].ptr;
}

fn genChk(self: Self) misc.types.BitBoard {
	const occ = self.allOcc();
	const stm = self.stm;

	const k_bb = self.pieceOcc(misc.types.Piece.fromPtype(stm, .king));
	const k_sq = k_bb.lowSquare();

	const their_pieces = std.EnumArray(misc.types.Ptype, misc.types.BitBoard).init(.{
		.nil = undefined,
		.pawn   = self.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .pawn)),
		.knight = self.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .knight)),
		.bishop = self.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .bishop)),
		.rook   = self.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .rook)),
		.queen  = self.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .queen)),
		.king   = self.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .king)),
		.all = undefined,
	});
	var chk = bitboard.pAtk(k_bb, stm).bitAnd(their_pieces.get(.pawn))
	  .bitOr(bitboard.nAtk(k_sq).bitAnd(their_pieces.get(.knight)))
	  .bitOr(bitboard.kAtk(k_sq).bitAnd(their_pieces.get(.king)));

	const k_ba = bitboard.bAtk(k_sq, occ);
	var diag = misc.types.BitBoard.nil
	  .bitOr(their_pieces.get(.bishop))
	  .bitOr(their_pieces.get(.queen))
	  .bitAnd(k_ba);
	while (diag != .nil) : (diag.popLow()) {
		const s = diag.lowSquare();
		chk = chk.bitOr(s.bb()).bitOr(bitboard.bAtk(s, occ).bitAnd(k_ba));
	}

	const k_ra = bitboard.rAtk(k_sq, occ);
	var line = misc.types.BitBoard.nil
	  .bitOr(their_pieces.get(.rook))
	  .bitOr(their_pieces.get(.queen))
	  .bitAnd(k_ra);
	while (line != .nil) : (line.popLow()) {
		const s = line.lowSquare();
		chk = chk.bitOr(s.bb()).bitOr(bitboard.rAtk(s, occ).bitAnd(k_ra));
	}

	return if (chk != .nil) chk else .all;
}

fn genKey(self: Self) Zobrist.Int {
	var z = Zobrist.default.castle.get(self.ssTop().castle)
	  ^ (if (self.ssTop().en_pas) |s| Zobrist.default.en_pas.get(s.file()) else 0)
	  ^ (if (self.stm == .white) Zobrist.default.stm.get(.white) else 0);
	for (misc.types.Piece.w_pieces) |p| {
		var b = self.pieceOcc(p);
		while (b != .nil) : (b.popLow()) {
			const s = b.lowSquare();
			z ^= Zobrist.default.psq.get(s).get(p);
		}
	}
	for (misc.types.Piece.b_pieces) |p| {
		var b = self.pieceOcc(p);
		while (b != .nil) : (b.popLow()) {
			const s = b.lowSquare();
			z ^= Zobrist.default.psq.get(s).get(p);
		}
	}
	return z;
}

fn casAfterMove(self: Self, move: movegen.Move) misc.types.Castle {
	var cas = self.ssTop().castle;
	const dst = move.dst;
	const src = move.src;
	const dst_piece = self.getSquare(dst);
	const src_piece = self.getSquare(src);

	const stm = self.stm;
	if (src_piece.ptype() == .rook) {
		const home = stm.homeRank();
		const k_src = misc.types.Square.fromCoord(home, .file_h);
		const q_src = misc.types.Square.fromCoord(home, .file_a);

		const k_cas = if (stm == .white) misc.types.Castle.wk else misc.types.Castle.bk;
		const q_cas = if (stm == .white) misc.types.Castle.wq else misc.types.Castle.bq;

		cas = cas.bitAnd(if (src == k_src) k_cas.flip() else .all);
		cas = cas.bitAnd(if (src == q_src) q_cas.flip() else .all);
	} else if (src_piece.ptype() == .king) {
		const w_cas = misc.types.Castle.nil.bitOr(.wk).bitOr(.wq);
		const b_cas = misc.types.Castle.nil.bitOr(.bk).bitOr(.bq);
		cas = cas.bitAnd(if (stm == .white) w_cas.flip() else b_cas.flip());
	}

	const nstm = stm.flip();
	if (dst_piece.ptype() == .rook) {
		const home = nstm.homeRank();
		const k_dst = misc.types.Square.fromCoord(home, .file_h);
		const q_dst = misc.types.Square.fromCoord(home, .file_a);

		const k_cas = if (nstm == .white) misc.types.Castle.wk else misc.types.Castle.bk;
		const q_cas = if (nstm == .white) misc.types.Castle.wq else misc.types.Castle.bq;

		cas = cas.bitAnd(if (dst == k_dst) k_cas.flip() else .all);
		cas = cas.bitAnd(if (dst == q_dst) q_cas.flip() else .all);
	}

	return cas;
}

fn keyAfterMove(self: Self, move: movegen.Move) Zobrist.Int {
	const stm = self.stm;
	const dst = move.dst;
	const src = move.src;
	const dst_piece = self.getSquare(dst);
	const src_piece = self.getSquare(src);

	const next_cas = self.casAfterMove(move);
	const this_cas = self.ssTop().castle;
	const next_ep
	  = if (src_piece.ptype() != .pawn or dst.shift(stm.forward().flip(), 2) != src) null
	  else dst.shift(stm.forward().flip(), 1);
	const this_ep = self.ssTop().en_pas;

	var z = self.ssTop().key
	  ^ (if (stm == .white) Zobrist.default.stm.get(.white) else 0)
	  ^ Zobrist.default.castle.get(this_cas)
	  ^ Zobrist.default.castle.get(next_cas)
	  ^ (if (this_ep) |s| Zobrist.default.en_pas.get(s.file()) else 0)
	  ^ (if (next_ep) |s| Zobrist.default.en_pas.get(s.file()) else 0);

	z ^= Zobrist.default.psq.get(src).get(src_piece);
	z ^= Zobrist.default.psq.get(dst).get(dst_piece);
	if (move.flag == .nil) {
		@branchHint(.likely);
		z ^= Zobrist.default.psq.get(dst).get(src_piece);
	} else if (move.flag == .en_passant) {
		const our_pawn = misc.types.Piece.fromPtype(stm, .pawn);
		const their_pawn = misc.types.Piece.fromPtype(stm.flip(), .pawn);

		std.debug.assert(dst_piece == .nil);
		std.debug.assert(src_piece == our_pawn);
		z ^= Zobrist.default.psq.get(dst).get(src_piece);
		z ^= Zobrist.default.psq.get(dst.shift(stm.forward().flip(), 1)).get(their_pawn);
	} else if (move.flag == .promote) {
		const our_pawn = misc.types.Piece.fromPtype(stm, .pawn);
		const our_promotion = misc.types.Piece.fromPtype(stm, move.promotion());

		std.debug.assert(src_piece == our_pawn);
		z ^= Zobrist.default.psq.get(dst).get(our_promotion);
	} else if (move.flag == .castle) {
		const is_k = dst.file() == .file_g;
		const is_q = dst.file() == .file_c;
		std.debug.assert(is_k or is_q);

		const home = stm.homeRank();
		const rook_dst = misc.types.Square.fromCoord(home,
		  if (is_k) misc.types.File.file_f else misc.types.File.file_d);
		const rook_src = misc.types.Square.fromCoord(home,
		  if (is_k) misc.types.File.file_h else misc.types.File.file_a);
		const our_king = misc.types.Piece.fromPtype(stm, .king);
		const our_rook = misc.types.Piece.fromPtype(stm, .rook);

		std.debug.assert(dst_piece == .nil);
		std.debug.assert(src_piece == our_king);
		std.debug.assert(self.getSquare(rook_dst) == .nil);
		std.debug.assert(self.getSquare(rook_src) == our_rook);

		z ^= Zobrist.default.psq.get(dst).get(src_piece)
		  ^ Zobrist.default.psq.get(rook_src).get(our_rook)
		  ^ Zobrist.default.psq.get(rook_dst).get(our_rook);
	} else unreachable;

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
pub fn allOcc(self: Self) misc.types.BitBoard {
	return self.ptypeOcc(.all);
}

pub fn ssTop(self: Self) Stack {
	return self.ssTopPtrConst()[0];
}

pub fn getSquare(self: Self, s: misc.types.Square) misc.types.Piece {
	return self.squarePtrConst(s).*;
}
pub fn popSquare(self: *Self, s: misc.types.Square, p: misc.types.Piece) void {
	const c = p.color();
	if (p != .nil) {
		std.debug.assert(self.getSquare(s) == p);
		std.debug.assert(self.colorOcc(c).getSquare(s));
		std.debug.assert(self.pieceOcc(p).getSquare(s));

		self.squarePtr(s).* = .nil;
		self.colorOccPtr(c).popSquare(s);
		self.pieceOccPtr(p).popSquare(s);
	}
}
pub fn setSquare(self: *Self, s: misc.types.Square, p: misc.types.Piece) void {
	const c = p.color();
	if (p != .nil) {
		std.debug.assert(self.getSquare(s) == .nil);
		std.debug.assert(!self.colorOcc(c).getSquare(s));
		std.debug.assert(!self.pieceOcc(p).getSquare(s));

		self.squarePtr(s).* = p;
		self.colorOccPtr(c).setSquare(s);
		self.pieceOccPtr(p).setSquare(s);
	}
}

pub fn checkMask(self: Self) misc.types.BitBoard {
	return self.ssTop().chk;
}

pub fn is3peat(self: Self) bool {
	var peat: usize = 0;
	for (0 .. self.ss_ply) |i| {
		peat += if (self.ss[i].key == self.ssTop().key) 1 else 0;
	}
	return peat >= 2;
}

pub fn parseFen(self: *Self, fen: []const u8) FenError!void {
	const backup = self.*;
	self.* = std.mem.zeroes(Self);
	errdefer self.* = backup;

	const sa = [_]misc.types.Square {
		.a8, .b8, .c8, .d8, .e8, .f8, .g8, .h8,
		.a7, .b7, .c7, .d7, .e7, .f7, .g7, .h7,
		.a6, .b6, .c6, .d6, .e6, .f6, .g6, .h6,
		.a5, .b5, .c5, .d5, .e5, .f5, .g5, .h5,
		.a4, .b4, .c4, .d4, .e4, .f4, .g4, .h4,
		.a3, .b3, .c3, .d3, .e3, .f3, .g3, .h3,
		.a2, .b2, .c2, .d2, .e2, .f2, .g2, .h2,
		.a1, .b1, .c1, .d1, .e1, .f1, .g1, .h1,
	};
	var si: usize = 0;
	var step: usize = 0;

	var stm_set = false;
	var cas_set = false;

	var ep_f: ?misc.types.File = null;
	var ep_r: ?misc.types.Rank = null;
	var ep_set = false;

	for (fen, 0 ..) |c, i| {
		if (std.ascii.isWhitespace(c)) {
			_ = i;
			step += 1;
			continue;
		}
		if (step == 0) {
			const p = misc.types.Piece.fromChar(c) orelse .nil;
			if (p != .nil) {
				self.setSquare(sa[si], p);
				si += 1;
			} else si += skip: switch (c) {
				'1' ... '8' => c - '0',
				'/' => if (si % misc.types.File.num != 0) continue :skip '\n' else break :skip 0,
				else => return error.InvalidPiece,
			};
		} else if (step == 1) {
			if (stm_set) {
				return error.InvalidStm;
			}
			self.stm = misc.types.Color.fromChar(c) orelse return error.InvalidStm;
			stm_set = true;
		} else if (step == 2) {
			const char_cas = misc.types.Castle.fromChar(c) orelse return error.InvalidCastle;
			switch (char_cas) {
				.nil => {
					if (self.ss[0].castle != .nil or cas_set) {
						return error.InvalidCastle;
					}
				},
				.wk, .wq, .bk, .bq => |v| {
					if (self.ss[0].castle.bitAnd(v) != .nil) {
						return error.InvalidCastle;
					}
					self.ss[0].castle = self.ss[0].castle.bitOr(v);
				},
				else => return error.InvalidCastle,
			}
			cas_set = true;
		} else if (step == 3) {
			sw: switch (c) {
				'a' ... 'h' => {
					if (ep_f != null or ep_r != null or ep_set) {
						continue :sw '\n';
					}
					ep_f = misc.types.File.fromChar(c) orelse continue :sw '\n';
				},
				'1' ... '8' => {
					if (ep_f == null or ep_r != null or ep_set) {
						continue :sw '\n';
					}
					ep_r = misc.types.Rank.fromChar(c) orelse continue :sw '\n';

					self.ss[0].en_pas = misc.types.Square.fromCoord(ep_r.?, ep_f.?);
					ep_set = true;
				},
				'-' => {
					if (ep_f != null or ep_r != null or ep_set) {
						continue :sw '\n';
					}

					self.ss[0].en_pas = null;
					ep_set = true;
				},
				else => return error.InvalidEnPassant,
			}
		} else if (step == 4) {
		} else if (step == 5) {
		} else return error.InvalidFen;
	}

	self.ss[0].chk = self.genChk();
	self.ss[0].key = self.genKey();
}

pub fn doMove(self: *Self, move: movegen.Move) MoveError!void {
	const stm = self.stm;
	const dst = move.dst;
	const src = move.src;
	const dst_piece = self.getSquare(dst);
	const src_piece = self.getSquare(src);

	const next_cas = self.casAfterMove(move);
	const next_key = self.keyAfterMove(move);

	self.ss_ply += 1;
	self.popSquare(src, src_piece);
	self.popSquare(dst, dst_piece);
	if (move.flag == .nil) {
		self.setSquare(dst, src_piece);
	} else if (move.flag == .en_passant) {
		const our_pawn = misc.types.Piece.fromPtype(stm, .pawn);
		const their_pawn = misc.types.Piece.fromPtype(stm.flip(), .pawn);

		std.debug.assert(dst_piece == .nil);
		std.debug.assert(src_piece == our_pawn);
		self.setSquare(dst, src_piece);
		self.popSquare(dst.shift(stm.forward().flip(), 1), their_pawn);
	} else if (move.flag == .promote) {
		const our_pawn = misc.types.Piece.fromPtype(stm, .pawn);
		const our_promotion = misc.types.Piece.fromPtype(stm, move.promotion());

		std.debug.assert(src_piece == our_pawn);
		self.setSquare(dst, our_promotion);
	} else if (move.flag == .castle) {
		const is_k = dst.file() == .file_g;
		const is_q = dst.file() == .file_c;
		std.debug.assert(is_k or is_q);

		const home = stm.homeRank();
		const rook_dst = misc.types.Square.fromCoord(home,
		  if (is_k) misc.types.File.file_f else misc.types.File.file_d);
		const rook_src = misc.types.Square.fromCoord(home,
		  if (is_k) misc.types.File.file_h else misc.types.File.file_a);
		const our_king = misc.types.Piece.fromPtype(stm, .king);
		const our_rook = misc.types.Piece.fromPtype(stm, .rook);

		std.debug.assert(dst_piece == .nil);
		std.debug.assert(src_piece == our_king);
		std.debug.assert(self.getSquare(rook_dst) == .nil);
		std.debug.assert(self.getSquare(rook_src) == our_rook);

		self.setSquare(dst, src_piece);
		self.popSquare(rook_src, our_rook);
		self.setSquare(rook_dst, our_rook);
	} else unreachable;
	const is_legal = self.genChk() == .all;

	self.stm = self.stm.flip();
	self.ssTopPtr()[0].castle = next_cas;
	self.ssTopPtr()[0].chk = self.genChk();
	self.ssTopPtr()[0].en_pas
	  = if (src_piece.ptype() == .pawn and dst.shift(stm.forward().flip(), 2) == src)
		dst.shift(stm.forward().flip(), 1) else null;
	self.ssTopPtr()[0].key = next_key;

	self.ssTopPtr()[0].move = move;
	self.ssTopPtr()[0].dst_piece = dst_piece;
	self.ssTopPtr()[0].src_piece = src_piece;

	if (!is_legal) {
		self.undoMove();
		return error.InvalidMove;
	}
}

pub fn undoMove(self: *Self) void {
	self.stm = self.stm.flip();
	const move = self.ssTop().move;
	const dst_piece = self.ssTop().dst_piece;
	const src_piece = self.ssTop().src_piece;
	const dst = move.dst;
	const src = move.src;
	const stm = self.stm;

	if (move.flag == .nil) {
		@branchHint(.likely);
		self.popSquare(dst, src_piece);
	} else if (move.flag == .en_passant) {
		const our_pawn = misc.types.Piece.fromPtype(stm, .pawn);
		const their_pawn = misc.types.Piece.fromPtype(stm.flip(), .pawn);

		std.debug.assert(dst_piece == .nil);
		std.debug.assert(src_piece == our_pawn);
		self.setSquare(dst.shift(stm.forward().flip(), 1), their_pawn);
		self.popSquare(dst, src_piece);
	} else if (move.flag == .promote) {
		const our_pawn = misc.types.Piece.fromPtype(stm, .pawn);
		const our_promotion = misc.types.Piece.fromPtype(stm, move.promotion());

		std.debug.assert(src_piece == our_pawn);
		self.popSquare(dst, our_promotion);
	} else if (move.flag == .castle) {
		const is_k = dst.file() == .file_g;
		const is_q = dst.file() == .file_c;
		std.debug.assert(is_k or is_q);

		const home = stm.homeRank();
		const rook_dst = misc.types.Square.fromCoord(home,
		  if (is_k) misc.types.File.file_f else misc.types.File.file_d);
		const rook_src = misc.types.Square.fromCoord(home,
		  if (is_k) misc.types.File.file_h else misc.types.File.file_a);
		const our_king = misc.types.Piece.fromPtype(stm, .king);
		const our_rook = misc.types.Piece.fromPtype(stm, .rook);

		std.debug.assert(dst_piece == .nil);
		std.debug.assert(src_piece == our_king);
		std.debug.assert(self.getSquare(rook_dst) == our_rook);
		std.debug.assert(self.getSquare(rook_src) == .nil);

		self.popSquare(rook_dst, our_rook);
		self.setSquare(rook_src, our_rook);
		self.popSquare(dst, src_piece);
	} else unreachable;
	self.setSquare(dst, dst_piece);
	self.setSquare(src, src_piece);

	self.ss_ply -= 1;
}

pub fn printSelf(self: Self) !void {
	const in_test = builtin.is_test;
	const stdout = std.io.getStdOut();

	const rank_arr = [_]misc.types.Rank {
		.rank_8, .rank_7, .rank_6, .rank_5, .rank_4, .rank_3, .rank_2, .rank_1,
	};

	const board_format = "\t{c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}";
	const coord_format = "\t{c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}";
	const coord_args = .{' ', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'};

	if (in_test) {
		std.log.defaultLog(.debug, .printSelf, coord_format, coord_args);
	} else {
		try stdout.writer().print(coord_format, coord_args);
		try stdout.writer().print("\n", .{});
	}
	for (rank_arr) |r| {
		const board_args = .{
			r.char() orelse unreachable,
			self.getSquare(misc.types.Square.fromCoord(r, .file_a)).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, .file_b)).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, .file_c)).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, .file_d)).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, .file_e)).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, .file_f)).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, .file_g)).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, .file_h)).char() orelse '.',
		};

		if (in_test) {
			std.log.defaultLog(.debug, .printSelf, board_format, board_args);
		} else {
			try stdout.writer().print(board_format, board_args);
			try stdout.writer().print("\n", .{});
		}
	}
	if (in_test) {
		std.log.defaultLog(.debug, .printSelf, coord_format, coord_args);
	} else {
		try stdout.writer().print(coord_format, coord_args);
		try stdout.writer().print("\n", .{});
	}
}

test {
	var pos = std.mem.zeroes(Self);

	try pos.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
	try pos.doMove(movegen.Move.gen(.nil, .nil, .e2, .e4));
	try std.testing.expectEqual(genKey(pos), pos.ssTop().key);
}
