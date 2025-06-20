const bitboard = @import("bitboard");
const builtin = @import("builtin");
const misc = @import("misc");
const std = @import("std");

const Zobrist = @import("Zobrist.zig");
const movegen = @import("movegen.zig");

const Self = @This();

mailbox:	std.EnumArray(misc.types.Square, misc.types.Piece)
	= std.EnumArray(misc.types.Square, misc.types.Piece).initFill(.nil),

piece_occ:	std.EnumArray(misc.types.Piece,  misc.types.BitBoard)
	= std.EnumArray(misc.types.Piece,  misc.types.BitBoard).initFill(.nil),

stm:	misc.types.Color = .white,

game_len:	usize = 1,
ss:	Stack.Array = Stack.Array.default,

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
	move:	movegen.Move = movegen.Move.zero,
	src_piece:	misc.types.Piece = .nil,
	dst_piece:	misc.types.Piece = .nil,

	castle:	misc.types.Castle = .nil,
	chk:	misc.types.BitBoard = .all,
	en_pas:	?misc.types.Square = null,
	key:	Zobrist.Int = 0,
	rule50:	u8 = 0,

	pub const Array = struct {
		buffer:	std.BoundedArray(Stack, 512),

		pub const default = blk: {
			var arr: Array = undefined;
			arr.buffer = @TypeOf(arr.buffer).init(0) catch unreachable;
			arr.buffer.appendNTimes(.{}, arr.buffer.buffer[0 ..].len) catch unreachable;
			arr.buffer = @TypeOf(arr.buffer).init(1) catch unreachable;
			break :blk arr;
		};

		pub fn append(self: *Array, stack: Stack) void {
			self.buffer.append(stack) catch unreachable;
		}
		pub fn pop(self: *Array) Stack {
			return self.buffer.pop() orelse unreachable;
		}
	};
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

fn colorOccPtrConst(self: *const Self, c: misc.types.Color) *const misc.types.BitBoard {
	return self.pieceOccPtrConst(misc.types.Piece.fromPtype(c, .all));
}
fn pieceOccPtrConst(self: *const Self, p: misc.types.Piece) *const misc.types.BitBoard {
	return self.piece_occ.getPtrConst(p);
}
fn squarePtrConst(self: *const Self, s: misc.types.Square) *const misc.types.Piece {
	return self.mailbox.getPtrConst(s);
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

pub fn keyAfterMove(self: Self, move: movegen.Move) Zobrist.Int {
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

	var z = self.ssTop().key ^ Zobrist.default.stm.get(.white)
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

pub fn ssTopPtr(self: *Self) [*]Stack {
	return self.ss.buffer.slice()[self.ssPly() ..].ptr;
}
pub fn ssTopPtrConst(self: *const Self) [*]const Stack {
	return self.ss.buffer.constSlice()[self.ssPly() ..].ptr;
}
pub fn ssTop(self: Self) Stack {
	return self.ssTopPtrConst()[0];
}
pub fn ssPly(self: Self) usize {
	return self.ss.buffer.len - 1;
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
	for (0 .. self.ss.buffer.len) |i| {
		peat += if (self.ss.buffer.constSlice()[i].key == self.ssTop().key) 1 else 0;
	}
	return peat >= 3;
}

pub fn parseFen(self: *Self, fen: []const u8) FenError!void {
	var tokens = std.mem.tokenizeAny(u8, fen, &.{'\t', '\n', '\r', ' '});
	try self.parseFenTokens(&tokens);
}

pub fn parseFenTokens(self: *Self, tokens: *std.mem.TokenIterator(u8, .any)) FenError!void {
	const backup = self.*;
	self.* = Self {};
	errdefer self.* = backup;

	const psq_token = tokens.next() orelse return error.InvalidFen;
	var si: usize = 0;
	for (psq_token) |c| {
		const p = misc.types.Piece.fromChar(c) orelse .nil;
		self.setSquare(misc.types.Square.book_order[si], p);
		si += if (p != .nil) 1 else switch (c) {
			'1' ... '8' => c - '0',
			'/' => skip: {
				if (si % misc.types.File.num != 0) {
					return error.InvalidSquare;
				}
				break :skip 0;
			},
			else => return error.InvalidSquare,
		};
	}

	const stm_token = tokens.next() orelse return error.InvalidFen;
	if (stm_token.len != 1) {
		return error.InvalidStm;
	}
	self.stm = misc.types.Color.fromChar(stm_token[0]) orelse return error.InvalidStm;

	const castle_token = tokens.next() orelse return error.InvalidFen;
	if (castle_token.len > 4) {
		return error.InvalidCastle;
	}
	for (castle_token, 0 ..) |c, i| {
		const castle = misc.types.Castle.fromChar(c) orelse return error.InvalidCastle;
		switch (castle) {
			.nil => {
				if (self.ssTop().castle != .nil or i != 0) {
					return error.InvalidCastle;
				}
			},
			.wk, .wq, .bk, .bq => {
				if (self.ssTop().castle.bitAnd(castle) != .nil) {
					return error.InvalidCastle;
				}
				self.ssTopPtr()[0].castle = self.ssTop().castle.bitOr(castle);
			},
			else => return error.InvalidCastle,
		}
	}

	const en_passant_token = tokens.next() orelse return error.InvalidFen;
	var en_passant_file: ?misc.types.File = null;
	var en_passant_rank: ?misc.types.Rank = null;
	if (en_passant_token.len > 2) {
		return error.InvalidEnPassant;
	}
	for (en_passant_token, 0 ..) |c, i| {
		switch (c) {
			'a' ... 'h' => {
				if (en_passant_token.len != 2 or i != 0) {
					return error.InvalidEnPassant;
				}
				en_passant_file = misc.types.File.fromChar(c) orelse unreachable;
			},
			'1' ... '8' => {
				if (en_passant_token.len != 2 or i != 1) {
					return error.InvalidEnPassant;
				}
				en_passant_rank = misc.types.Rank.fromChar(c) orelse unreachable;

				self.ssTopPtr()[0].en_pas
				  = misc.types.Square.fromCoord(en_passant_rank.?, en_passant_file.?);
			},
			'-' => {
				if (en_passant_token.len != 1) {
					return error.InvalidEnPassant;
				}
				self.ssTopPtr()[0].en_pas = null;
			},
			else => return error.InvalidEnPassant,
		}
	}

	const half_move_token = tokens.next();
	if (half_move_token != null) {
		self.ssTopPtr()[0].rule50 = std.fmt.parseUnsigned(@TypeOf(self.ssTopPtr()[0].rule50),
		  half_move_token.?, 10) catch return error.InvalidHalfMoveClock;
	} else {
		self.ssTopPtr()[0].rule50 = 0;
	}

	const move_token = tokens.next();
	if (move_token != null) {
		self.game_len = std.fmt.parseUnsigned(@TypeOf(self.game_len),
		  move_token.?, 10) catch return error.InvalidMoveClock;
	} else {
		self.game_len = 1;
	}

	if (tokens.peek()) |token| {
		if (!std.mem.eql(u8, token, "moves")) {
			return error.InvalidFen;
		}
	}

	self.ssTopPtr()[0].chk = self.genChk();
	self.ssTopPtr()[0].key = self.genKey();
}

pub fn doMove(self: *Self, move: movegen.Move) MoveError!void {
	const stm = self.stm;
	const dst = move.dst;
	const src = move.src;
	const dst_piece = self.getSquare(dst);
	const src_piece = self.getSquare(src);

	const next_cas = self.casAfterMove(move);
	const next_key = self.keyAfterMove(move);
	const ply_clock = self.ssTop().rule50;

	self.ss.append(.{
		.castle = next_cas,
		.en_pas = if (src_piece.ptype() != .pawn or dst.shift(stm.forward().flip(), 2) != src) null
			else dst.shift(stm.forward().flip(), 1),
		.key = next_key,
		.rule50 = if (src_piece.ptype() == .pawn or dst_piece.ptype() != .nil) 0 else ply_clock + 1,

		.move = move,
		.src_piece = src_piece,
		.dst_piece = dst_piece,
	});

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
	self.ssTopPtr()[0].chk = self.genChk();
	self.game_len += if (self.stm == .white) 1 else 0;

	if (!is_legal) {
		self.undoMove();
		return error.InvalidMove;
	}
}

pub fn doNullMove(self: *Self) MoveError!void {
	if (self.checkMask() != .all) {
		return error.InvalidMove;
	}

	const ss = self.ssTop();
	self.ss.append(.{
		.castle = self.ssTop().rule50,
		.chk = .all,
		.en_pas = null,
		.key = self.ssTop().key,
		.move = movegen.Move.zero,
		.src_piece = .nil,
		.dst_piece = .nil,
	});
	self.stm = self.stm.flip();
	self.game_len += if (self.stm == .white) 1 else 0;

	self.ssTopPtr()[0].key ^= Zobrist.default.stm.get(.white);
	self.ssTopPtr()[0].key ^= if (ss.en_pas) |s| Zobrist.default.en_pas.get(s.file()) else 0;
}

pub fn undoMove(self: *Self) void {
	self.stm = self.stm.flip();
	self.game_len -= if (self.stm == .black) 1 else 0;

	const stack = self.ss.pop();
	const move = stack.move;
	const dst_piece = stack.dst_piece;
	const src_piece = stack.src_piece;
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
}

pub fn undoNullMove(self: *Self) void {
	self.game_len -= if (self.stm == .white) 1 else 0;
	self.stm = self.stm.flip();
	_ = self.ss.pop();
}

pub fn printSelf(self: Self) !void {
	const in_test = builtin.is_test;
	const output = if (in_test) std.io.getStdErr() else std.io.getStdOut();

	const coord_format = if (in_test) "\t{c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}"
		else "\t{c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}\n";
	const coord_args = .{' ', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'};

	if (in_test) {
		std.log.defaultLog(.debug, .printSelf, coord_format, coord_args);
	} else {
		try output.writer().print(coord_format, coord_args);
	}

	const rank_arr = [_]misc.types.Rank {
		.rank_8, .rank_7, .rank_6, .rank_5, .rank_4, .rank_3, .rank_2, .rank_1,
	};
	const file_arr = [_]misc.types.File {
		.file_a, .file_b, .file_c, .file_d, .file_e, .file_f, .file_g, .file_h,
	};
	for (rank_arr) |r| {
		const board_format = if (in_test) "\t{c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}"
		  else "\t{c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}  {c}\n";
		const board_args = .{
			r.char() orelse unreachable,
			self.getSquare(misc.types.Square.fromCoord(r, file_arr[0])).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, file_arr[1])).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, file_arr[2])).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, file_arr[3])).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, file_arr[4])).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, file_arr[5])).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, file_arr[6])).char() orelse '.',
			self.getSquare(misc.types.Square.fromCoord(r, file_arr[7])).char() orelse '.',
			r.char() orelse unreachable,
		};

		if (in_test) {
			std.log.defaultLog(.debug, .printSelf, board_format, board_args);
		} else {
			try output.writer().print(board_format, board_args);
		}
	}

	if (in_test) {
		std.log.defaultLog(.debug, .printSelf, coord_format, coord_args);
	} else {
		try output.writer().print(coord_format, coord_args);
	}
}

test {
	var pos = Self {};

	try pos.parseFen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");
	try std.testing.expectEqual(misc.types.Piece.w_pawn, pos.getSquare(.g2));
	try std.testing.expectEqual(misc.types.Piece.b_pawn, pos.getSquare(.c7));

	try pos.doMove(movegen.Move.gen(.nil, .nil, .b4, .f4));
	var chk = misc.types.BitBoard.fromSlice(misc.types.Square, &.{.f4, .g4});
	var key = genKey(pos);
	try std.testing.expectEqual(chk, pos.ssTop().chk);
	try std.testing.expectEqual(key, pos.ssTop().key);

	try pos.doMove(movegen.Move.gen(.nil, .nil, .h4, .g3));
	chk = misc.types.BitBoard.all;
	key = genKey(pos);
	try std.testing.expectEqual(chk, pos.ssTop().chk);
	try std.testing.expectEqual(key, pos.ssTop().key);
}

test {
	_ = Self;
	_ = Stack;
}
