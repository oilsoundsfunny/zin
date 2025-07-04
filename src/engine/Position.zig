const bitboard = @import("bitboard");
const misc = @import("misc");
const params = @import("params");
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

pub const Error = error {
	InvalidFen,
	InvalidMove,
};

pub const State = struct {
	castle:	 misc.types.Castle,
	en_pas:	?misc.types.Square,
	rule50:	 u8,

	key:	Zobrist.Int,
	pawn_key:	Zobrist.Int,
	minor_key:	Zobrist.Int,
	major_key:	Zobrist.Int,

	checkers:	misc.types.BitBoard,

	eval:	evaluation.score.Int,
	psqt:	evaluation.Pair,
	pts:	evaluation.Pair,

	move:	movegen.Move = .{},
	dst_piece:	misc.types.Piece = .nil,
	src_piece:	misc.types.Piece = .nil,

	killer0:	movegen.Move = .{},
	killer1:	movegen.Move = .{},

	pub const Stack = struct {
		array:	std.BoundedArray(State, 1024) = .{
			.buffer = .{std.mem.zeroInit(State, .{})} ** 1024,
			.len = offset,
		},

		pub const length = 1024;
		pub const offset = 8;

		pub fn append(self: *Stack, s: State) void {
			self.array.append(s) catch std.debug.panic("do much move engine much panik", .{});
		}

		pub fn pop(self: *Stack) State {
			return self.array.pop() orelse std.debug.panic("undo much move engine much panik", .{});
		}

		pub fn ply(self: Stack) usize {
			return self.top() - &self.array.buffer[offset];
		}

		pub fn top(self: anytype) switch (@TypeOf(self)) {
			*const Stack => *const State,
			*Stack => *State,
			else => @compileError("unexpected type " ++ @typeName(@TypeOf(self))),
		} {
			return &self.array.slice()[self.array.slice().len - 1];
		}
	};

	pub fn down(self: anytype, ply: usize) switch (@TypeOf(self)) {
		*const State => *const State,
		*State => *State,
		else => @compileError("unexpected type " ++ @typeName(@TypeOf(self))),
	} {
		const many = self[0 .. 1].ptr;
		return @ptrCast(many - ply);
	}
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
	  ^ (if (self.side2move == .white) Zobrist.default.stm else 0);

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

fn doMoveLazy(self: *Self, move: movegen.Move) Error!void {
	const stm = self.side2move;
	const dst = move.dst;
	const src = move.src;
	const dst_piece = self.getSquare(dst);
	const src_piece = self.getSquare(src);

	self.ss.top().move = move;
	self.ss.top().dst_piece = dst_piece;
	self.ss.top().src_piece = src_piece;
	self.ss.append(.{
		.castle = self.ss.top().castle,
		.en_pas = null,
		.rule50 = self.ss.top().rule50 + 1,

		.checkers = .all,

		.key = self.ss.top().key,
		.pawn_key = self.ss.top().pawn_key,
		.minor_key = self.ss.top().minor_key,
		.major_key = self.ss.top().major_key,

		.eval = self.ss.top().eval,
		.psqt = self.ss.top().psqt,
		.pts  = self.ss.top().pts,
	});

	self.popSquare(src, src_piece);
	self.popSquare(dst, dst_piece);
	self.setSquare(dst, src_piece);

	switch (move.flag) {
		.nil => {
			@branchHint(.likely);
		},
		.en_passant => {
			const their_pawn = misc.types.Piece.fromPtype(stm.flip(), .pawn);
			const enp = dst.shift(stm.forward().flip(), 1);

			self.popSquare(enp, their_pawn);
		},
		.promote => {
			const our_pawn = misc.types.Piece.fromPtype(stm, .pawn);
			const our_promotion = misc.types.Piece.fromPtype(stm, move.promotion());

			self.popSquare(dst, our_pawn);
			self.setSquare(dst, our_promotion);
		},
		.castle => {
			const dst_file: misc.types.File = switch (dst.file()) {
				.file_c => .file_d,
				.file_g => .file_f,
				else => unreachable,
			};
			const src_file: misc.types.File = switch (dst.file()) {
				.file_c => .file_a,
				.file_g => .file_h,
				else => unreachable,
			};
			const home = stm.homeRank();
			const rook_dst = misc.types.Square.fromCoord(home, dst_file);
			const rook_src = misc.types.Square.fromCoord(home, src_file);
			const our_rook = misc.types.Piece.fromPtype(stm, .rook);

			self.popSquare(rook_src, our_rook);
			self.setSquare(rook_dst, our_rook);
		},
	}

	if (self.genCheckers(stm) != .all) {
		self.undoMoveLazy();
		return error.InvalidMove;
	}
}

fn undoMoveLazy(self: *Self) void {
	_ = self.ss.pop();
	const dst_piece = self.ss.top().dst_piece;
	const src_piece = self.ss.top().src_piece;
	const move = self.ss.top().move;
	const dst = move.dst;
	const src = move.src;
	const stm = self.side2move;

	switch (move.flag) {
		.nil => {
			@branchHint(.likely);
		},

		.en_passant => {
			const their_pawn = misc.types.Piece.fromPtype(stm.flip(), .pawn);
			const enp = dst.shift(stm.forward().flip(), 1);

			self.setSquare(enp, their_pawn);
		},

		.promote => {
			const our_pawn = misc.types.Piece.fromPtype(stm, .pawn);
			const our_promotion = misc.types.Piece.fromPtype(stm, move.promotion());

			self.popSquare(dst, our_promotion);
			self.setSquare(dst, our_pawn);
		},

		.castle => {
			const dst_file: misc.types.File = switch (dst.file()) {
				.file_c => .file_d,
				.file_g => .file_f,
				else => unreachable,
			};
			const src_file: misc.types.File = switch (dst.file()) {
				.file_c => .file_a,
				.file_g => .file_h,
				else => unreachable,
			};
			const home = stm.homeRank();
			const rook_dst = misc.types.Square.fromCoord(home, dst_file);
			const rook_src = misc.types.Square.fromCoord(home, src_file);
			const our_rook = misc.types.Piece.fromPtype(stm, .rook);

			self.popSquare(rook_dst, our_rook);
			self.setSquare(rook_src, our_rook);
		},
	}

	self.popSquare(dst, src_piece);
	self.setSquare(dst, dst_piece);
	self.setSquare(src, src_piece);
}

pub fn allOcc(self: Self) misc.types.BitBoard {
	return self.ptypeOcc(.all);
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

pub fn getSquare(self: Self, s: misc.types.Square) misc.types.Piece {
	return self.squarePtrConst(s).*;
}

pub fn popSquare(self: *Self, s: misc.types.Square, p: misc.types.Piece) void {
	if (p != .nil) {
		const c = p.color();

		self.mailbox.set(s, .nil);
		self.colorOccPtr(c).popSquare(s);
		self.pieceOccPtr(p).popSquare(s);

		switch (c) {
			.white => {
				self.ss.top().psqt.mg -= params.psqt.get(p.ptype()).get(s).mg;
				self.ss.top().psqt.eg -= params.psqt.get(p.ptype()).get(s).eg;

				self.ss.top().pts.mg -= params.pts.get(p.ptype()).mg;
				self.ss.top().pts.eg -= params.pts.get(p.ptype()).eg;
			},
			.black => {
				self.ss.top().psqt.mg += params.psqt.get(p.ptype()).get(s).mg;
				self.ss.top().psqt.eg += params.psqt.get(p.ptype()).get(s).eg;

				self.ss.top().pts.mg += params.pts.get(p.ptype()).mg;
				self.ss.top().pts.eg += params.pts.get(p.ptype()).eg;
			},
		}

		const z = Zobrist.default.psq.get(s).get(p);
		self.ss.top().key ^= z;
		switch (p.ptype()) {
			.pawn, .king => {
				self.ss.top().pawn_key ^= z;
			},
			.knight, .bishop => {
				self.ss.top().minor_key ^= z;
			},
			.rook, .queen => {
				self.ss.top().major_key ^= z;
			},
			else => std.debug.panic("what the hell are we popping", .{}),
		}
	}
}

pub fn setSquare(self: *Self, s: misc.types.Square, p: misc.types.Piece) void {
	if (p != .nil) {
		const c = p.color();

		self.mailbox.set(s, p);
		self.colorOccPtr(c).setSquare(s);
		self.pieceOccPtr(p).setSquare(s);

		switch (c) {
			.white => {
				self.ss.top().psqt.mg += params.psqt.get(p.ptype()).get(s).mg;
				self.ss.top().psqt.eg += params.psqt.get(p.ptype()).get(s).eg;

				self.ss.top().pts.mg += params.pts.get(p.ptype()).mg;
				self.ss.top().pts.eg += params.pts.get(p.ptype()).eg;
			},
			.black => {
				self.ss.top().psqt.mg -= params.psqt.get(p.ptype()).get(s).mg;
				self.ss.top().psqt.eg -= params.psqt.get(p.ptype()).get(s).eg;

				self.ss.top().pts.mg -= params.pts.get(p.ptype()).mg;
				self.ss.top().pts.eg -= params.pts.get(p.ptype()).eg;
			},
		}

		const z = Zobrist.default.psq.get(s).get(p);
		self.ss.top().key ^= z;
		switch (p.ptype()) {
			.pawn, .king => {
				self.ss.top().pawn_key ^= z;
			},
			.knight, .bishop => {
				self.ss.top().minor_key ^= z;
			},
			.rook, .queen => {
				self.ss.top().major_key ^= z;
			},
			else => std.debug.panic("what the hell are we setting", .{}),
		}
	}
}

pub fn doMove(self: *Self, move: movegen.Move) Error!void {
	try self.doMoveLazy(move);
	self.ss.top().checkers = self.genCheckers(self.side2move.flip());
	defer self.side2move = self.side2move.flip();

	const stm = self.side2move;
	const dst = move.dst;
	const src = move.src;
	const dst_ptype = self.ss.top().down(1).dst_piece.ptype();
	const src_ptype = self.ss.top().down(1).src_piece.ptype();

	switch (src_ptype) {
		.pawn => {
			self.ss.top().rule50 = 0;

			if (dst.shift(stm.forward().flip(), 2) == src) {
				self.ss.top().en_pas = dst.shift(stm.forward().flip(), 1);
			}
		},

		.rook => {
			const kc: misc.types.Castle = switch (stm) {
				.white => .wk,
				.black => .bk,
			};
			const qc: misc.types.Castle = switch (stm) {
				.white => .wq,
				.black => .bq,
			};

			const ks = misc.types.Square.fromCoord(stm.homeRank(), .file_h);
			const qs = misc.types.Square.fromCoord(stm.homeRank(), .file_a);

			self.ss.top().castle = self.ss.top().castle.bitAnd(if (src == ks) kc.flip() else .all);
			self.ss.top().castle = self.ss.top().castle.bitAnd(if (src == qs) qc.flip() else .all);
		},

		.king => {
			const sc = stm.castleMask();

			self.ss.top().castle = self.ss.top().castle.bitAnd(sc.flip());
		},

		else => {},
	}

	switch (dst_ptype) {
		.rook => {
			const kc: misc.types.Castle = switch (stm.flip()) {
				.white => .wk,
				.black => .bk,
			};
			const qc: misc.types.Castle = switch (stm.flip()) {
				.white => .wq,
				.black => .bq,
			};

			const ks = misc.types.Square.fromCoord(stm.flip().homeRank(), .file_h);
			const qs = misc.types.Square.fromCoord(stm.flip().homeRank(), .file_a);

			self.ss.top().castle = self.ss.top().castle.bitAnd(if (dst == ks) kc.flip() else .all);
			self.ss.top().castle = self.ss.top().castle.bitAnd(if (dst == qs) qc.flip() else .all);
		},

		else => {
			if (dst_ptype != .nil) {
				self.ss.top().rule50 = 0;
			}
		},
	}
}

pub fn undoMove(self: *Self) void {
	self.side2move = self.side2move.flip();
	self.undoMoveLazy();
}

pub fn parseFen(self: *Self, fen: []const u8) Error!void {
	var tokens = std.mem.tokenizeAny(u8, fen, &.{'\t', ' '});
	try self.parseFenTokens(&tokens);
}

pub fn parseFenTokens(self: *Self, tokens: *std.mem.TokenIterator(u8, .any)) Error!void {
	const backup = self.*;
	self.* = .{};
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
	const psq_token = tokens.next() orelse return error.InvalidFen;
	for (psq_token) |c| {
		const p = misc.types.Piece.fromChar(c) orelse switch (c) {
			'1' ... '8' => {
				si += c - '0';
				continue;
			},
			'/' => {
				continue;
			},
			else => return error.InvalidFen,
		};
		self.setSquare(sa[si], p);
		si += 1;
	}

	const stm_token = tokens.next() orelse return error.InvalidFen;
	if (stm_token.len > 1) {
		return error.InvalidFen;
	} else {
		self.side2move = misc.types.Color.fromChar(stm_token[0]) orelse return error.InvalidFen;
	}

	const castle_token = tokens.next() orelse return error.InvalidFen;
	if (castle_token.len > 4) {
		return error.InvalidFen;
	} else for (castle_token) |c| {
		const cas = misc.types.Castle.fromChar(c) orelse return error.InvalidFen;
		switch (cas) {
			.nil => {
				if (castle_token.len > 1) {
					return error.InvalidFen;
				}
			},
			.wk, .wq, .bk, .bq => {
				if (self.ss.top().castle.bitAnd(cas) != .nil) {
					return error.InvalidFen;
				}
				self.ss.top().castle = self.ss.top().castle.bitOr(cas);
			},
			else => return error.InvalidFen,
		}
	}

	var ef: ?misc.types.File = null;
	var er: ?misc.types.Rank = null;
	const enp_token = tokens.next() orelse return error.InvalidFen;
	if (enp_token.len > 2) {
		return error.InvalidFen;
	} else for (enp_token) |c| {
		self.ss.top().en_pas = switch (c) {
			'a' ... 'h' => file: {
				if (enp_token.len == 1) {
					return error.InvalidFen;
				}
				if (er) |_| {
					return error.InvalidFen;
				}
				ef = misc.types.File.fromChar(c) orelse return error.InvalidFen;
				break :file null;
			},
			'1' ... '8' => rank: {
				if (enp_token.len == 1) {
					return error.InvalidFen;
				}
				if (ef) |_| {
				} else {
					return error.InvalidFen;
				}
				er = misc.types.Rank.fromChar(c) orelse return error.InvalidFen;
				break :rank misc.types.Square.fromCoord(er.?, ef.?);
			},
			'-' => none: {
				if (enp_token.len > 1) {
					return error.InvalidFen;
				}
				break :none null;
			},
			else => return error.InvalidFen,
		};
	}

	const rule50_token = tokens.next() orelse return error.InvalidFen;
	self.ss.top().rule50 = std.fmt.parseUnsigned(@TypeOf(self.ss.top().rule50), rule50_token, 10)
		catch return error.InvalidFen;

	const length_token = tokens.next() orelse return error.InvalidFen;
	self.game_len = std.fmt.parseUnsigned(@TypeOf(self.game_len), length_token, 10)
		catch return error.InvalidFen;
}

pub fn isChecked(self: Self) bool {
	return self.ss.top().checkers != .all;
}

pub fn is3peat(self: Self) bool {
	var peat: usize = 0;
	const key = self.ss.top().key;
	for (self.ss.constSlice()) |s| {
		peat += if (s.key == key) 1 else 0;
	}
	return peat >= 3;
}

pub fn isMoveNoisy(self: Self, move: movegen.Move) bool {
	return switch (move.flag) {
		.nil => nil: {
			@branchHint(.likely);
			const dst_ptype = self.getSquare(move.dst).ptype();
			break :nil dst_ptype != .nil;
		},
		.en_passant => true,
		.promote => pr: {
			const dst_ptype = self.getSquare(move.dst).ptype();
			const promotion = move.promotion();

			break :pr dst_ptype != .nil or promotion == .queen or promotion == .knight;
		},
		.castle => false,
	};
}

pub fn isMoveQuiet(self: Self, move: movegen.Move) bool {
	return !self.isMoveNoisy(move);
}

test {
	var pos = std.mem.zeroes(Self);
	try pos.parseFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");

	try std.testing.expectEqual(misc.types.Piece.w_rook, pos.getSquare(.a1));
	try std.testing.expectEqual(misc.types.Piece.w_rook, pos.getSquare(.h1));
	try std.testing.expectEqual(misc.types.Piece.b_rook, pos.getSquare(.a8));
	try std.testing.expectEqual(misc.types.Piece.b_rook, pos.getSquare(.h8));

	try std.testing.expectEqual(misc.types.Piece.nil, pos.getSquare(.d4));
	try std.testing.expectEqual(misc.types.Piece.w_pawn, pos.getSquare(.e4));
	try std.testing.expectEqual(misc.types.Piece.w_pawn, pos.getSquare(.d5));
	try std.testing.expectEqual(misc.types.Piece.w_knight, pos.getSquare(.e5));

	{
		try pos.doMove(movegen.Move.gen(.nil, .nil, .g2, .h3));
		defer pos.undoMove();

		try std.testing.expectEqual(pos.genKey(), pos.ss.top().key);
	}

	try std.testing.expectEqual(misc.types.Piece.w_rook, pos.getSquare(.a1));
	try std.testing.expectEqual(misc.types.Piece.w_rook, pos.getSquare(.h1));
	try std.testing.expectEqual(misc.types.Piece.b_rook, pos.getSquare(.a8));
	try std.testing.expectEqual(misc.types.Piece.b_rook, pos.getSquare(.h8));

	try std.testing.expectEqual(misc.types.Piece.nil, pos.getSquare(.d4));
	try std.testing.expectEqual(misc.types.Piece.w_pawn, pos.getSquare(.e4));
	try std.testing.expectEqual(misc.types.Piece.w_pawn, pos.getSquare(.d5));
	try std.testing.expectEqual(misc.types.Piece.w_knight, pos.getSquare(.e5));
}
