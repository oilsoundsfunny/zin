const base = @import("base");
const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const builtin = @import("builtin");
const nnue = @import("nnue");
const params = @import("params");
const root = @import("root");
const std = @import("std");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const search = @import("search.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

const Self = @This();

by_square:	std.EnumArray(base.types.Square, base.types.Piece)
  = std.EnumArray(base.types.Square, base.types.Piece).initFill(.none),
by_color:	std.EnumArray(base.types.Color, base.types.Square.Set),
by_ptype:	std.EnumArray(base.types.Ptype, base.types.Square.Set),

stm:	base.types.Color,
castles:	std.EnumMap(base.types.Castle, Castle),
ss:	State.Stack = .{},

pub const FenError = error {
	InvalidPiece,
	InvalidSquare,
	InvalidSideToMove,
	InvalidCastle,
	InvalidEnPassant,
	InvalidPlyClock,
	InvalidMoveClock,
	InvalidFen,
};

pub const MoveError = error {
	InvalidMove,
};

pub const Castle = struct {
	atk:	base.types.Square.Set,
	occ:	base.types.Square.Set,

	ks:	base.types.Square,
	kd:	base.types.Square,

	rs:	base.types.Square,
	rd:	base.types.Square,
};

pub const State = struct {
	move:	movegen.Move = movegen.Move.zero,
	src_piece:	base.types.Piece,
	dst_piece:	base.types.Piece,

	castle:	 base.types.Castle.Set,
	en_pas:	?base.types.Square,
	rule50:	 u8,
	qs_ply:	?u8,

	check_mask:	base.types.Square.Set = .full,

	key:	zobrist.Int,

	corr_eval:	evaluation.score.Int = evaluation.score.none,
	stat_eval:	evaluation.score.Int = evaluation.score.none,
	accumulator:	nnue.Accumulator = .{},

	pv:	movegen.Move.Root,

	pub const Stack = struct {
		array:	bounded_array.BoundedArray(State, 1024) = .{
			.buffer = .{std.mem.zeroInit(State, .{})} ** 1024,
			.len = offset + 1,
		},

		const offset = 8;

		pub const capacity = 1024 - offset;

		pub fn push(self: *Stack, st: State) void {
			self.array.appendAssumeCapacity(st);
		}

		pub fn pop(self: *Stack) void {
			_ = self.array.pop() orelse std.debug.panic("stack underflow", .{});
		}

		pub fn ply(self: *const Stack) usize {
			return self.array.len - (offset + 1);
		}

		pub fn slice(self: anytype) switch (@TypeOf(self)) {
			*Stack => []State,
			*const Stack => []const State,
			else => |T| @compileError("unexpected type " ++ @typeName(T)),
		} {
			return self.array.slice()[offset ..];
		}

		pub fn top(self: anytype) switch (@TypeOf(self)) {
			*Stack => *State,
			*const Stack => *const State,
			else => |T| @compileError("unexpected type " ++ @typeName(T)),
		} {
			return &self.slice()[self.ply()];
		}

		pub fn bottom(self: anytype) switch (@TypeOf(self)) {
			*Stack => *State,
			*const Stack => *const State,
			else => |T| @compileError("unexpected type " ++ @typeName(T)),
		} {
			return &self.slice()[0];
		}

		pub fn isFull(self: *const Stack) bool {
			return self.top() == &self.array.buffer[self.array.buffer.len - 1];
		}
	};

	pub fn down(self: anytype, ply: usize) switch (@TypeOf(self)) {
		*State, *const State => |T| T,
		else => |T| @compileError("unexpected type " ++ @typeName(T)),
	} {
		const many = self[0 .. 1].ptr;
		return @ptrCast(many - ply);
	}

	pub fn up(self: anytype, ply: usize) switch (@TypeOf(self)) {
		*State, *const State => |T| T,
		else => |T| @compileError("unexpected type " ++ @typeName(T)),
	} {
		const many = self[0 .. 1].ptr;
		return @ptrCast(many + ply);
	}
};

pub const startpos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
pub const kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";

fn colorOccPtr(self: *Self, c: base.types.Color) *base.types.Square.Set {
	return self.by_color.getPtr(c);
}

fn ptypeOccPtr(self: *Self, c: base.types.Ptype) *base.types.Square.Set {
	return self.by_ptype.getPtr(c);
}

fn squarePtr(self: *Self, s: base.types.Square) *base.types.Piece {
	return self.by_square.getPtr(s);
}

fn colorOccPtrConst(self: *const Self, c: base.types.Color) *const base.types.Square.Set {
	return self.by_color.getPtrConst(c);
}

fn ptypeOccPtrConst(self: *const Self, c: base.types.Ptype) *const base.types.Square.Set {
	return self.by_ptype.getPtrConst(c);
}

fn squarePtrConst(self: *const Self, s: base.types.Square) *const base.types.Piece {
	return self.by_square.getPtrConst(s);
}

fn popSq(self: *Self, s: base.types.Square, p: base.types.Piece, comptime full: bool) void {
	if (p == .none) {
		return;
	}

	const c = p.color();
	const t = p.ptype();
	self.squarePtr(s).* = .none;
	self.colorOccPtr(c).pop(s);
	self.ptypeOccPtr(t).pop(s);
	if (!full) {
		return;
	}

	const z = zobrist.psq(s, p);
	self.ss.top().key ^= z;
	self.ss.top().accumulator.pop(s, p);
}

fn popSqFull(self: *Self, s: base.types.Square, p: base.types.Piece) void {
	self.popSq(s, p, true);
}

fn popSqLazy(self: *Self, s: base.types.Square, p: base.types.Piece) void {
	self.popSq(s, p, false);
}

fn setSq(self: *Self, s: base.types.Square, p: base.types.Piece, comptime full: bool) void {
	if (p == .none) {
		return;
	}

	const c = p.color();
	const t = p.ptype();
	self.squarePtr(s).* = p;
	self.colorOccPtr(c).set(s);
	self.ptypeOccPtr(t).set(s);
	if (!full) {
		return;
	}

	const z = zobrist.psq(s, p);
	self.ss.top().key ^= z;
	self.ss.top().accumulator.set(s, p);
}

fn setSqFull(self: *Self, s: base.types.Square, p: base.types.Piece) void {
	self.setSq(s, p, true);
}

fn setSqLazy(self: *Self, s: base.types.Square, p: base.types.Piece) void {
	self.setSq(s, p, false);
}

fn popCastle(self: *Self, c: base.types.Castle) void {
	self.ss.top().castle.pop(c);
}

fn setCastle(self: *Self, c: base.types.Castle, info: Castle) void {
	self.castles.put(c, info);
	self.ss.top().castle.set(c);
}

fn genCheckMask(self: *const Self) base.types.Square.Set {
	const occ = self.bothOcc();
	const stm = self.stm;

	const kb = self.pieceOcc(base.types.Piece.init(stm, .king));
	const ks = kb.lowSquare() orelse std.debug.panic("invalid position", .{});
	const atkers = self.squareAtkers(ks).bwa(self.colorOcc(stm.flip()));
	var ka = atkers;

	const kba = bitboard.bAtk(ks, occ);
	var diag = base.types.Square.Set
	  .none
	  .bwo(self.pieceOcc(base.types.Piece.init(stm.flip(), .bishop)))
	  .bwo(self.pieceOcc(base.types.Piece.init(stm.flip(), .queen)))
	  .bwa(atkers);
	while (diag.lowSquare()) |s| : (diag.popLow()) {
		ka.setOther(bitboard.bAtk(s, occ).bwa(kba));
	}

	const kra = bitboard.rAtk(ks, occ);
	var line = base.types.Square.Set
	  .none
	  .bwo(self.pieceOcc(base.types.Piece.init(stm.flip(), .rook)))
	  .bwo(self.pieceOcc(base.types.Piece.init(stm.flip(), .queen)))
	  .bwa(atkers);
	while (line.lowSquare()) |s| : (line.popLow()) {
		ka.setOther(bitboard.rAtk(s, occ).bwa(kra));
	}

	return if (ka != .none) ka else .full;
}

pub fn bothOcc(self: *const Self) base.types.Square.Set {
	const wo = self.colorOcc(.white);
	const bo = self.colorOcc(.black);
	return @TypeOf(wo, bo).bwo(wo, bo);
}

pub fn colorOcc(self: *const Self, c: base.types.Color) base.types.Square.Set {
	return self.colorOccPtrConst(c).*;
}

pub fn ptypeOcc(self: *const Self, p: base.types.Ptype) base.types.Square.Set {
	return self.ptypeOccPtrConst(p).*;
}

pub fn pieceOcc(self: *const Self, p: base.types.Piece) base.types.Square.Set {
	const c = p.color();
	const t = p.ptype();

	const co = self.colorOcc(c);
	const to = self.ptypeOcc(t);
	return @TypeOf(co, to).bwa(co, to);
}

pub fn getSquare(self: *const Self, s: base.types.Square) base.types.Piece {
	return self.squarePtrConst(s).*;
}

pub fn doMove(self: *Self, move: movegen.Move) MoveError!void {
	const s = move.src;
	const d = move.dst;
	const sp = self.getSquare(s);
	const dp = self.getSquare(d);

	self.ss.top().move = move;
	self.ss.top().src_piece = sp;
	self.ss.top().dst_piece = dp;
	self.ss.push(std.mem.zeroInit(State, .{
		.castle = self.ss.top().castle,
		.rule50 = self.ss.top().rule50 + 1,

		.key = self.ss.top().key,
		.accumulator = self.ss.top().accumulator,
	}));

	self.popSqFull(s, sp);
	self.popSqFull(d, dp);
	self.setSqFull(d, sp);

	switch (move.flag) {
		.none => {
			@branchHint(.likely);
		},

		.en_passant => {
			const their_pawn = base.types.Piece.init(self.stm.flip(), .pawn);
			const enp_target = d.shift(self.stm.forward().flip(), 1);

			self.popSqFull(enp_target, their_pawn);
		},

		.promote => {
			const our_pawn = base.types.Piece.init(self.stm, .pawn);
			const our_promotion = base.types.Piece.init(self.stm, move.info.promote.toPtype());

			self.popSqFull(d, our_pawn);
			self.setSqFull(d, our_promotion);
		},

		.castle => {
			const info = self.castles.getAssertContains(move.info.castle);
			const our_rook = base.types.Piece.init(self.stm, .rook);
			const our_king = base.types.Piece.init(self.stm, .king);

			if (uci.options.frc) {
				self.popSqFull(info.rs, our_king);
				self.setSqFull(info.kd, our_king);
				self.setSqFull(info.rd, our_rook);
			} else {
				self.popSqFull(info.rs, our_rook);
				self.setSqFull(info.rd, our_rook);
			}
		},
	}

	switch (sp) {
		.w_pawn, .b_pawn => {
			self.ss.top().rule50 = 0;
			if (d.shift(self.stm.forward().flip(), 2) == s) {
				self.ss.top().en_pas = d.shift(self.stm.forward().flip(), 1);
			}
		},

		.w_rook, .b_rook => {
			var iter = self.castles.iterator();
			while (iter.next()) |entry| {
				const k = entry.key;
				const v = entry.value;

				if (s == v.rs) {
					self.popCastle(k);
					break;
				}
			}
		},

		.w_king, .b_king => {
			self.popCastle(if (self.stm == .white) .wk else .bk);
			self.popCastle(if (self.stm == .white) .wq else .bq);

			const ks = switch (move.flag) {
				.castle => self.castles.getPtrConstAssertContains(move.info.castle).ks,
				else => s,
			};
			const kd = switch (move.flag) {
				.castle => self.castles.getPtrConstAssertContains(move.info.castle).kd,
				else => d,
			};

			const is_s_mirrored = switch (ks.file()) {
				.file_e, .file_f, .file_g, .file_h => true,
				else => false,
			};
			const is_d_mirrored = switch (kd.file()) {
				.file_e, .file_f, .file_g, .file_h => true,
				else => false,
			};
			if (!builtin.is_test and is_s_mirrored != is_d_mirrored) {
				self.ss.top().accumulator.mirror(self, self.stm);
			}
		},

		else => {},
	}

	switch (dp) {
		.w_rook, .b_rook => {
			var iter = self.castles.iterator();
			while (iter.next()) |entry| {
				const k = entry.key;
				const v = entry.value;

				if (d == v.rs) {
					self.popCastle(k);
					break;
				}
			}
		},
		else => {},
	}

	self.stm = self.stm.flip();
	self.ss.top().check_mask = self.genCheckMask();
	self.ss.top().key ^= zobrist.stm()
	  ^ zobrist.cas(self.ss.top().down(1).castle)
	  ^ zobrist.enp(self.ss.top().down(1).en_pas)
	  ^ zobrist.cas(self.ss.top().castle)
	  ^ zobrist.enp(self.ss.top().en_pas);

	const kb = self.pieceOcc(base.types.Piece.init(self.stm.flip(), .king));
	const ks = kb.lowSquare() orelse std.debug.panic("invalid position", .{});
	if (self.squareAtkers(ks).bwa(self.colorOcc(self.stm)) != .none) {
		self.undoMove();
		return error.InvalidMove;
	}
}

pub fn doNull(self: *Self) MoveError!void {
	if (self.isChecked()) {
		return error.InvalidMove;
	}

	self.stm = self.stm.flip();
	self.ss.top().move = .{};
	self.ss.top().src_piece = .none;
	self.ss.top().dst_piece = .none;
	self.ss.push(std.mem.zeroInit(State, .{
		.castle = self.ss.top().castle,

		.key = self.ss.top().key
		  ^ zobrist.stm()
		  ^ zobrist.enp(self.ss.top().en_pas),
		.accumulator = self.ss.top().accumulator,
	}));
}

pub fn undoMove(self: *Self) void {
	const move = self.ss.top().down(1).move;
	const sp = self.ss.top().down(1).src_piece;
	const dp = self.ss.top().down(1).dst_piece;
	const s = move.src;
	const d = move.dst;

	self.stm = self.stm.flip();

	switch (move.flag) {
		.none => {
			@branchHint(.likely);
		},

		.en_passant => {
			const their_pawn = base.types.Piece.init(self.stm.flip(), .pawn);
			const enp_target = d.shift(self.stm.forward().flip(), 1);

			self.setSqLazy(enp_target, their_pawn);
		},

		.promote => {
			const our_pawn = base.types.Piece.init(self.stm, .pawn);
			const our_promotion = base.types.Piece.init(self.stm, move.info.promote.toPtype());

			self.popSqLazy(d, our_promotion);
			self.setSqLazy(d, our_pawn);
		},

		.castle => {
			const info = self.castles.getAssertContains(move.info.castle);
			const our_rook = base.types.Piece.init(self.stm, .rook);
			const our_king = base.types.Piece.init(self.stm, .king);

			if (uci.options.frc) {
				self.popSqLazy(info.rd, our_rook);
				self.popSqLazy(info.kd, our_king);
				self.setSqLazy(info.rs, our_king);
			} else {
				self.popSqLazy(info.rd, our_rook);
				self.setSqLazy(info.rs, our_rook);
			}
		},
	}

	self.popSqLazy(d, sp);
	self.setSqLazy(d, dp);
	self.setSqLazy(s, sp);
	self.ss.pop();
}

pub fn undoNull(self: *Self) void {
	self.stm = self.stm.flip();
	self.ss.pop();
}

pub fn parseFen(self: *Self, fen: []const u8) FenError!void {
	var tokens = std.mem.tokenizeAny(u8, fen, &std.ascii.whitespace);
	for (0 .. 6) |_| {
		if (tokens.next() == null) {
			return error.InvalidFen;
		}
	}

	tokens.reset();
	return self.parseFenTokens(&tokens);
}

pub fn parseFenTokens(self: *Self, tokens: *std.mem.TokenIterator(u8, .any)) FenError!void {
	const backup = self.*;
	self.* = std.mem.zeroInit(Self, .{});
	errdefer self.* = backup;

	const sa = [base.types.Square.cnt]base.types.Square {
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
	var rooks = std.EnumMap(base.types.Castle, base.types.Square).init(.{});
	var kings = std.EnumMap(base.types.Color, base.types.Square).init(.{});

	const psq_token = tokens.next() orelse return error.InvalidFen;
	if (psq_token.len < 17 or psq_token.len > 71) {
		return error.InvalidFen;
	}
	for (psq_token) |c| {
		const s = sa[si];
		const from_c = base.types.Piece.fromChar(c);
		si += if (from_c) |p| blk: {
			self.setSqFull(s, p);

			switch (p) {
				.w_rook => {
					if (kings.contains(.white)) {
						rooks.put(.wk, s);
					} else if (!rooks.contains(.wq)) {
						rooks.put(.wq, s);
					}
				},
				.w_king => {
					if (kings.contains(.white)) {
						return error.InvalidPiece;
					}
					kings.put(.white, s);

					const mirrored = switch (s.file()) {
						.file_e, .file_f, .file_g, .file_h => true,
						else => false,
					};
					if (!builtin.is_test and mirrored) {
						self.ss.top().accumulator.mirror(self, .white);
					}
				},

				.b_rook => {
					if (kings.contains(.black)) {
						rooks.put(.bk, s);
					} else if (!rooks.contains(.bq)) {
						rooks.put(.bq, s);
					}
				},
				.b_king => {
					if (kings.contains(.black)) {
						return error.InvalidPiece;
					}
					kings.put(.black, s);

					const mirrored = switch (s.file()) {
						.file_e, .file_f, .file_g, .file_h => true,
						else => false,
					};
					if (!builtin.is_test and mirrored) {
						self.ss.top().accumulator.mirror(self, .black);
					}
				},

				else => {},
			}

			break :blk 1;
		} else switch (c) {
			'1' ... '8' => c - '0',
			'/' => 0,
			else => return error.InvalidPiece,
		};

		if (si > base.types.Square.cnt) {
			return error.InvalidSquare;
		}
		if (si < base.types.Square.cnt
		  and sa[si].rank() != s.rank()
		  and sa[si].file() != .file_a) {
			return error.InvalidSquare;
		}
	}

	const stm_token = tokens.next() orelse return error.InvalidFen;
	if (stm_token.len > 1) {
		return error.InvalidFen;
	}
	self.stm = base.types.Color.fromChar(stm_token[0]) orelse return error.InvalidSideToMove;
	if (self.stm == .white) {
		self.ss.top().key ^= zobrist.stm();
	}

	const cas_token = tokens.next() orelse return error.InvalidFen;
	if (cas_token.len > 4) {
		return error.InvalidFen;
	}
	for (cas_token) |c| {
		if (c == '-') {
			if (cas_token.len > 1) {
				return error.InvalidCastle;
			}
			self.ss.top().castle = .none;
			self.ss.top().key ^= zobrist.cas(.none);
			break;
		}
		const cas = base.types.Castle.fromChar(c) orelse sw: switch (c) {
			'A' ... 'H', 'a' ... 'h' => {
				const is_lower = std.ascii.isLower(c);
				const to_lower = std.ascii.toLower(c);

				const kf = kings.getAssertContains(if (is_lower) .white else .black).file();
				const rf = base.types.File.fromChar(to_lower) orelse unreachable;

				const kfi: isize = @intFromEnum(kf);
				const rfi: isize = @intFromEnum(rf);
				const ei: isize = std.math.sign(base.types.Direction.west.tag());
				const is_k = std.math.sign(rfi - kfi) == ei;

				if (is_lower) {
					break :sw if (is_k) base.types.Castle.bk else base.types.Castle.bq;
				} else {
					break :sw if (is_k) base.types.Castle.wk else base.types.Castle.wq;
				}
			},
			else => return error.InvalidCastle,
		};

		const ks = kings.getAssertContains(cas.color());
		const rs = rooks.getAssertContains(cas);

		const kd = base.types.Square.init(cas.color().homeRank(),
		  if (cas.ptype() == .queen) .file_c else .file_g);
		const rd = base.types.Square.init(cas.color().homeRank(),
		  if (cas.ptype() == .queen) .file_d else .file_f);

		const kb = if (ks != kd) base.types.Square.Set
		  .full
		  .bwa(bitboard.rAtk(ks, kd.toSet()))
		  .bwa(bitboard.rAtk(kd, ks.toSet()))
		  .bwo(kd.toSet())
		  else .none;
		const rb = if (rs != rd) base.types.Square.Set
		  .full
		  .bwa(bitboard.rAtk(rs, rd.toSet()))
		  .bwa(bitboard.rAtk(rd, rs.toSet()))
		  .bwo(rd.toSet())
		  else .none;

		self.setCastle(cas, .{
			.ks = ks,
			.kd = kd,
			.rs = rs,
			.rd = rd,
			.atk = kb,
			.occ = kb.bwo(rb)
			  .bwa(rs.toSet().flip())
			  .bwa(ks.toSet().flip()),
		});
	}

	const enp_token = tokens.next() orelse return error.InvalidFen;
	switch (enp_token.len) {
		1 => {
			if (enp_token[0] != '-') {
				return error.InvalidEnPassant;
			}
			self.ss.top().en_pas = null;
		},
		2 => {
			const r = base.types.Rank.fromChar(enp_token[0]) orelse return error.InvalidEnPassant;
			const f = base.types.File.fromChar(enp_token[0]) orelse return error.InvalidEnPassant;
			self.ss.top().en_pas = base.types.Square.init(r, f);
		},
		else => return error.InvalidFen,
	}

	const ply_token = tokens.next() orelse return error.InvalidFen;
	self.ss.top().rule50 = std.fmt.parseUnsigned(u8, ply_token, 10)
	  catch return error.InvalidPlyClock;

	const move_token = tokens.next() orelse return error.InvalidFen;
	std.mem.doNotOptimizeAway(std.fmt.parseUnsigned(u8, move_token, 10)
	  catch return error.InvalidMoveClock);

	self.ss.top().check_mask = self.genCheckMask();
}

pub fn squareAtkers(self: *const Self, s: base.types.Square) base.types.Square.Set {
	const occ = self.bothOcc();
	return base.types.Square.Set
	  .none
	  .bwo(bitboard.pAtk(s.toSet(), .white).bwa(self.pieceOcc(.b_pawn)))
	  .bwo(bitboard.pAtk(s.toSet(), .black).bwa(self.pieceOcc(.w_pawn)))
	  .bwo(bitboard.nAtk(s).bwa(self.ptypeOcc(.knight)))
	  .bwo(bitboard.kAtk(s).bwa(self.ptypeOcc(.king)))
	  .bwo(bitboard.bAtk(s, occ).bwa(self.ptypeOcc(.bishop)))
	  .bwo(bitboard.rAtk(s, occ).bwa(self.ptypeOcc(.rook)))
	  .bwo(bitboard.qAtk(s, occ).bwa(self.ptypeOcc(.queen)));
}

pub fn getRepeat(self: *const Self) usize {
	const bot = self.ss.bottom();
	const top = self.ss.top();
	const key = top.key;

	var peat: usize = 1;
	var p = bot;
	while (p != top) : (p = p.up(1)) {
		peat += if (p.key == key) 1 else 0;
	}
	return peat;
}

pub fn is3peat(self: *const Self) bool {
	return self.getRepeat() >= 3;
}

pub fn isChecked(self: *const Self) bool {
	return self.ss.top().check_mask != .full;
}

pub fn isDrawn(self: *const Self) bool {
	return self.ss.top().rule50 >= 100
	  or self.is3peat()
	  or self.ss.array.len >= self.ss.array.capacity();
}

pub fn isMoveNoisy(self: *const Self, move: movegen.Move) bool {
	const dp = self.getSquare(move.dst);
	const is_capt = dp.color() != self.stm and dp.ptype() != .none and dp.ptype() != .full;

	return switch (move.flag) {
		.none => is_capt,
		.en_passant => true,
		.promote => {
			const promotion = move.info.promote.toPtype();
			return is_capt or promotion == .queen or promotion == .knight;
		},
		.castle => false,
	};
}

pub fn isMoveQuiet(self: *const Self, move: movegen.Move) bool {
	return !self.isMoveNoisy(move);
}

pub fn isMovePseudoLegal(self: *const Self, move: movegen.Move) bool {
	const stm = self.stm;
	const occ = self.bothOcc();
	const them = self.colorOcc(stm.flip());

	const s = move.src;
	const d = move.dst;
	const sp = self.getSquare(s);
	const dp = self.getSquare(d);

	const spc = sp.color();
	const dpc = dp.color();

	return switch (move.flag) {
		.none => none: {
			if (sp == .none or spc != stm) {
				break :none false;
			}
			if (dp != .none and dpc == stm) {
				break :none false;
			}

			const noisy = switch (sp.ptype()) {
				.pawn => bitboard.pAtk(s.toSet(), stm).bwa(them),
				else => |pt| bitboard.ptAtk(pt, s, occ).bwa(them),
			};
			const quiet = switch (sp.ptype()) {
				.pawn => base.types.Square.Set.none
				  .bwo(bitboard.pPush1(s.toSet(), occ, stm))
				  .bwo(bitboard.pPush2(s.toSet(), occ, stm)),
				else => |pt| bitboard.ptAtk(pt, s, occ).bwa(occ.flip()),
			};

			break :none switch (dp) {
				.none => quiet.get(d),
				else => noisy.get(d),
			};
		},

		.en_passant => en_passant: {
			if (sp != base.types.Piece.init(stm, .pawn) or dp != .none) {
				break :en_passant false;
			}

			const enp = self.ss.top().en_pas orelse return false;
			if (enp != d) {
				break :en_passant false;
			}

			const capt = d.shift(stm.forward().flip(), 1);
			const their_pawn = base.types.Piece.init(stm.flip(), .pawn);
			if (self.getSquare(capt) != their_pawn) {
				break :en_passant false;
			}

			break :en_passant bitboard.pAtk(s.toSet(), stm).get(d);
		},

		.castle => castle: {
			const info = self.castles.getPtrConst(move.info.castle) orelse return false;
			const our_rook = base.types.Piece.init(stm, .rook);
			const our_king = base.types.Piece.init(stm, .king);

			const illegal = !self.ss.top().castle.get(move.info.castle)
			  or s != info.ks or sp != our_king
			  or (uci.options.frc and d != info.rs)
			  or (uci.options.frc and dp != our_rook)
			  or (!uci.options.frc and d != info.kd)
			  or (!uci.options.frc and dp != .none);
			break :castle !illegal;
		},

		.promote => promote: {
			const noisy = bitboard.pAtk(s.toSet(), stm).bwa(them);
			const quiet = base.types.Square.Set.none
			  .bwo(bitboard.pPush1(s.toSet(), occ, stm))
			  .bwo(bitboard.pPush2(s.toSet(), occ, stm));

			break :promote spc == stm and sp.ptype() == .pawn
			  and d.rank() == stm.promotionRank()
			  and !(dp == .none and !quiet.get(d))
			  and !(dp != .none and !noisy.get(d));
		},
	};
}

pub fn evaluate(self: *const Self) evaluation.score.Int {
	return evaluation.score.fromPosition(self);
}
