const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const builtin = @import("builtin");
const nnue = @import("nnue");
const params = @import("params");
const root = @import("root");
const std = @import("std");
const types = @import("types");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const search = @import("search.zig");
const zobrist = @import("zobrist.zig");

const Board = @This();

frc:	bool = false,
last_clean:	usize = 0,

ss:	bounded_array.BoundedArray(One, capacity + offset) = .{
	.buffer = .{@as(One, .{})} ** (capacity + offset),
	.len = offset + 1,
},

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
	atk:	types.Square.Set,
	occ:	types.Square.Set,

	ks:	types.Square,
	kd:	types.Square,

	rs:	types.Square,
	rd:	types.Square,
};

pub const One = struct {
	by_color:	std.EnumArray(types.Color, types.Square.Set)
	  = std.EnumArray(types.Color, types.Square.Set).initFill(.none),
	by_ptype:	std.EnumArray(types.Ptype, types.Square.Set)
	  = std.EnumArray(types.Ptype, types.Square.Set).initFill(.none),
	by_square:	std.EnumArray(types.Square, types.Piece)
	  = std.EnumArray(types.Square, types.Piece).initFill(.none),
	castles:	std.EnumMap(types.Castle, Castle) = std.EnumMap(types.Castle, Castle).init(.{}),

	stm:	types.Color = .white,
	move:	movegen.Move = .{},
	src_piece:	types.Piece = .none,
	dst_piece:	types.Piece = .none,

	checks:	 types.Square.Set = .full,
	en_pas:	?types.Square = null,
	rule50:	 u8 = 0,
	key:	 zobrist.Int = 0,

	corr_eval:	evaluation.score.Int = evaluation.score.none,
	stat_eval:	evaluation.score.Int = evaluation.score.none,
	accumulator:	nnue.Accumulator = .{},

	pv:	movegen.Move.Root = .{},

	pub const startpos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
	pub const kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";

	pub const see = @import("see.zig").func;

	fn colorOccPtr(self: *One, c: types.Color) *types.Square.Set {
		return self.by_color.getPtr(c);
	}

	fn ptypeOccPtr(self: *One, c: types.Ptype) *types.Square.Set {
		return self.by_ptype.getPtr(c);
	}

	fn colorOccPtrConst(self: *const One, c: types.Color) *const types.Square.Set {
		return self.by_color.getPtrConst(c);
	}

	fn ptypeOccPtrConst(self: *const One, c: types.Ptype) *const types.Square.Set {
		return self.by_ptype.getPtrConst(c);
	}

	fn popSq(self: *One, s: types.Square, p: types.Piece) void {
		if (p == .none) {
			return;
		}

		const c = p.color();
		const t = p.ptype();
		self.by_square.set(s, .none);
		self.colorOccPtr(c).pop(s);
		self.ptypeOccPtr(t).pop(s);

		const z = zobrist.psq(s, p);
		self.key ^= z;
	}

	fn setSq(self: *One, s: types.Square, p: types.Piece) void {
		if (p == .none) {
			return;
		}

		const c = p.color();
		const t = p.ptype();
		self.by_square.set(s, p);
		self.colorOccPtr(c).set(s);
		self.ptypeOccPtr(t).set(s);

		const z = zobrist.psq(s, p);
		self.key ^= z;
	}

	fn popCastle(self: *One, c: types.Castle) void {
		if (self.castles.fetchRemove(c)) |_| {
			self.key ^= zobrist.cas(c);
		}
	}

	fn setCastle(self: *One, c: types.Castle, info: Castle) void {
		if (self.castles.fetchPut(c, info)) |_| {
		} else {
			self.key ^= zobrist.cas(c);
		}
	}

	fn genCheckMask(self: *const One) types.Square.Set {
		const occ = self.bothOcc();
		const stm = self.stm;

		const kb = self.pieceOcc(types.Piece.init(stm, .king));
		const ks = kb.lowSquare() orelse std.debug.panic("invalid position", .{});
		const atkers = self.squareAtkers(ks).bwa(self.colorOcc(stm.flip()));
		var ka = atkers;

		const kba = bitboard.bAtk(ks, occ);
		const diag = types.Square.Set
		  .none
		  .bwo(self.ptypeOcc(.bishop))
		  .bwo(self.ptypeOcc(.queen))
		  .bwa(atkers);
		if (diag.lowSquare()) |s| {
			ka.setOther(bitboard.bAtk(s, occ).bwa(kba));
		}

		const kra = bitboard.rAtk(ks, occ);
		const line = types.Square.Set
		  .none
		  .bwo(self.ptypeOcc(.rook))
		  .bwo(self.ptypeOcc(.queen))
		  .bwa(atkers);
		if (line.lowSquare()) |s| {
			ka.setOther(bitboard.rAtk(s, occ).bwa(kra));
		}

		return if (ka != .none) ka else .full;
	}

	pub fn down(self: anytype, dist: usize) switch (@TypeOf(self)) {
		*One, *const One => |T| T,
		else => |T| @compileError("unexpected type " ++ @typeName(T)),
	} {
		return @ptrCast(self[0 .. 1].ptr - dist);
	}

	pub fn up(self: anytype, dist: usize) switch (@TypeOf(self)) {
		*One, *const One => |T| T,
		else => |T| @compileError("unexpected type " ++ @typeName(T)),
	} {
		return @ptrCast(self[0 .. 1].ptr + dist);
	}

	pub fn bothOcc(self: *const One) types.Square.Set {
		const wo = self.colorOcc(.white);
		const bo = self.colorOcc(.black);
		return @TypeOf(wo, bo).bwo(wo, bo);
	}

	pub fn colorOcc(self: *const One, c: types.Color) types.Square.Set {
		return self.colorOccPtrConst(c).*;
	}

	pub fn ptypeOcc(self: *const One, p: types.Ptype) types.Square.Set {
		return self.ptypeOccPtrConst(p).*;
	}

	pub fn pieceOcc(self: *const One, p: types.Piece) types.Square.Set {
		const c = p.color();
		const t = p.ptype();

		const co = self.colorOcc(c);
		const to = self.ptypeOcc(t);
		return @TypeOf(co, to).bwa(co, to);
	}

	pub fn getSquare(self: *const One, s: types.Square) types.Piece {
		return self.by_square.getPtrConst(s).*;
	}

	pub fn parseFen(self: *One, fen: []const u8) FenError!void {
		var tokens = std.mem.tokenizeAny(u8, fen, &std.ascii.whitespace);
		for (0 .. 6) |_| {
			if (tokens.next() == null) {
				return error.InvalidFen;
			}
		}

		tokens.reset();
		return self.parseFenTokens(&tokens);
	}

	pub fn parseFenTokens(self: *One, tokens: *std.mem.TokenIterator(u8, .any)) FenError!void {
		const backup = self.*;
		self.* = .{};
		errdefer self.* = backup;

		const sa = [types.Square.cnt]types.Square {
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
		var rooks = std.EnumMap(types.Castle, types.Square).init(.{});
		var kings = std.EnumMap(types.Color, types.Square).init(.{});

		const psq_token = tokens.next() orelse return error.InvalidFen;
		if (psq_token.len < 17 or psq_token.len > 71) {
			return error.InvalidFen;
		}
		for (psq_token) |c| {
			const s = sa[si];
			const from_c = types.Piece.fromChar(c);
			si += if (from_c) |p| blk: {
				self.setSq(s, p);

				self.accumulator.add(.white, .{.piece = p, .square = s});
				self.accumulator.add(.black, .{.piece = p, .square = s});

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
						if (mirrored) {
							self.accumulator.mirror(.white, self);
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
						if (mirrored) {
							self.accumulator.mirror(.black, self);
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

			if (si > types.Square.cnt) {
				return error.InvalidSquare;
			}
			if (si < types.Square.cnt
			  and sa[si].rank() != s.rank()
			  and sa[si].file() != .file_a) {
				return error.InvalidSquare;
			}
		}

		const stm_token = tokens.next() orelse return error.InvalidFen;
		if (stm_token.len > 1) {
			return error.InvalidFen;
		}
		self.stm = types.Color.fromChar(stm_token[0]) orelse return error.InvalidSideToMove;
		if (self.stm == .white) {
			self.key ^= zobrist.stm();
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
				break;
			}
			const cas = types.Castle.fromChar(c) orelse sw: switch (c) {
				'A' ... 'H', 'a' ... 'h' => {
					const is_lower = std.ascii.isLower(c);
					const to_lower = std.ascii.toLower(c);

					const kf = kings.getAssertContains(if (is_lower) .white else .black).file();
					const rf = types.File.fromChar(to_lower) orelse unreachable;

					const kfi: isize = @intFromEnum(kf);
					const rfi: isize = @intFromEnum(rf);
					const ei: isize = std.math.sign(types.Direction.west.tag());
					const is_k = std.math.sign(rfi - kfi) == ei;

					if (is_lower) {
						break :sw if (is_k) types.Castle.bk else types.Castle.bq;
					} else {
						break :sw if (is_k) types.Castle.wk else types.Castle.wq;
					}
				},
				else => return error.InvalidCastle,
			};

			const ks = kings.getAssertContains(cas.color());
			const rs = rooks.getAssertContains(cas);

			const kd = types.Square.init(cas.color().homeRank(),
			  if (cas.ptype() == .queen) .file_c else .file_g);
			const rd = types.Square.init(cas.color().homeRank(),
			  if (cas.ptype() == .queen) .file_d else .file_f);

			const kb = if (ks != kd) types.Square.Set
			  .full
			  .bwa(bitboard.rAtk(ks, kd.toSet()))
			  .bwa(bitboard.rAtk(kd, ks.toSet()))
			  .bwo(kd.toSet())
			  else .none;
			const rb = if (rs != rd) types.Square.Set
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
				self.en_pas = null;
			},
			2 => {
				const r = types.Rank.fromChar(enp_token[1]) orelse return error.InvalidEnPassant;
				const f = types.File.fromChar(enp_token[0]) orelse return error.InvalidEnPassant;
				self.en_pas = types.Square.init(r, f);
			},
			else => return error.InvalidFen,
		}

		const ply_token = tokens.next() orelse return error.InvalidFen;
		self.rule50 = std.fmt.parseUnsigned(u8, ply_token, 10)
		  catch return error.InvalidPlyClock;

		const move_token = tokens.next() orelse return error.InvalidFen;
		_ = std.fmt.parseUnsigned(usize, move_token, 10)
		  catch return error.InvalidMoveClock;

		self.accumulator.clear();
		self.accumulator.unmark();

		self.checks = self.genCheckMask();
		self.key ^= zobrist.enp(self.en_pas);
	}

	pub fn squareAtkers(self: *const One, s: types.Square) types.Square.Set {
		const occ = self.bothOcc();
		return types.Square.Set
		  .none
		  .bwo(bitboard.pAtk(s.toSet(), .white).bwa(self.pieceOcc(.b_pawn)))
		  .bwo(bitboard.pAtk(s.toSet(), .black).bwa(self.pieceOcc(.w_pawn)))
		  .bwo(bitboard.nAtk(s).bwa(self.ptypeOcc(.knight)))
		  .bwo(bitboard.kAtk(s).bwa(self.ptypeOcc(.king)))
		  .bwo(bitboard.bAtk(s, occ).bwa(self.ptypeOcc(.bishop)))
		  .bwo(bitboard.rAtk(s, occ).bwa(self.ptypeOcc(.rook)))
		  .bwo(bitboard.qAtk(s, occ).bwa(self.ptypeOcc(.queen)));
	}

	pub fn isChecked(self: *const One) bool {
		return self.checks != .full;
	}

	pub fn isMoveNoisy(self: *const One, move: movegen.Move) bool {
		const dp = self.getSquare(move.dst);
		const is_capt = dp != .none and dp.color() != self.stm;

		return is_capt or switch (move.flag) {
			.en_passant => true,
			.promote => blk: {
				const promotion = move.info.promote.toPtype();
				break :blk promotion == .queen or promotion == .knight;
			},
			else => false,
		};
	}

	pub fn isMoveQuiet(self: *const One, move: movegen.Move) bool {
		return !self.isMoveNoisy(move);
	}

	pub fn isMovePseudoLegal(self: *const One, move: movegen.Move) bool {
		const stm = self.stm;
		const occ = self.bothOcc();
		const them = self.colorOcc(stm.flip());

		const s = move.src;
		const d = move.dst;
		const sp = self.getSquare(s);
		const dp = self.getSquare(d);

		const spc = sp.color();
		const dpc = dp.color();

		return sp != .none and spc == stm and switch (move.flag) {
			.none => move.info.none == 0 and none: {
				if (dp != .none and dpc == stm) {
					break :none false;
				}

				const noisy = switch (sp.ptype()) {
					.pawn => bitboard.pAtk(s.toSet(), stm)
					  .bwa(them)
					  .bwa(stm.promotionRank().toSet().flip()),
					else => |pt| bitboard.ptAtk(pt, s, occ).bwa(them),
				};
				const quiet = switch (sp.ptype()) {
					.pawn => types.Square.Set.none
					  .bwo(bitboard.pPush1(s.toSet(), occ, stm))
					  .bwo(bitboard.pPush2(s.toSet(), occ, stm))
					  .bwa(stm.promotionRank().toSet().flip()),
					else => |pt| bitboard.ptAtk(pt, s, occ).bwa(occ.flip()),
				};

				break :none if (dp == .none) quiet.get(d) else noisy.get(d);
			},

			.en_passant => move.info.en_passant == 0
			  and sp.ptype() == .pawn
			  and dp == .none
			  and bitboard.pAtk(s.toSet(), stm).get(d)
			  and self.en_pas != null
			  and self.en_pas.? == d
			  and en_passant: {
				const capt = d.shift(stm.forward().flip(), 1);
				const their_pawn = types.Piece.init(stm.flip(), .pawn);
				break :en_passant self.getSquare(capt) == their_pawn;
			},

			.castle => castle: {
				const info = self.castles.getPtrConst(move.info.castle) orelse break :castle false;
				const ks = info.ks;
				const rs = info.rs;

				const is_checked = self.isChecked();
				var between = occ.bwa(info.occ);
				between.pop(ks);
				between.pop(rs);

				const rook = types.Piece.init(stm, .rook);
				const king = types.Piece.init(stm, .king);

				const illegal = is_checked or between != .none
				  or !self.castles.contains(move.info.castle)
				  or s != ks or sp != king
				  or d != rs or dp != rook;
				break :castle !illegal;
			},

			.promote => promote: {
				const noisy = bitboard.pAtk(s.toSet(), stm).bwa(them);
				const quiet = types.Square.Set.none
				  .bwo(bitboard.pPush1(s.toSet(), occ, stm))
				  .bwo(bitboard.pPush2(s.toSet(), occ, stm));

				break :promote sp.ptype() == .pawn
				  and d.rank() == stm.promotionRank()
				  and !(dp == .none and !quiet.get(d))
				  and !(dp != .none and !noisy.get(d));
			},
		};
	}

	fn updateAccumulator(self: *One) void {
		nnue.Accumulator.update(self);
	}

	fn evaluate(self: *const One) evaluation.score.Int {
		const inferred = nnue.net.embed.infer(self);
		const scaled = @divTrunc(inferred * (100 - self.rule50), 100);

		const min = evaluation.score.lose + 1;
		const max = evaluation.score.win - 1;
		return std.math.clamp(scaled, min, max);
	}
};

pub const capacity = 1024 - offset;
pub const offset = 8;

fn updateAccumulators(self: *Board) void {
	for (self.ss.slice()[offset ..]) |*pos| {
		if (pos.accumulator.dirty) {
			@branchHint(.unlikely);
			pos.updateAccumulator();
		}
	}
}

pub fn bottom(self: anytype) switch (@TypeOf(self)) {
	*Board => *One,
	*const Board => *const One,
	else => |T| @compileError("unexpected type " ++ @typeName(T)),
} {
	return &self.ss.slice()[offset];
}

pub fn top(self: anytype) switch (@TypeOf(self)) {
	*Board => *One,
	*const Board => *const One,
	else => |T| @compileError("unexpected type " ++ @typeName(T)),
} {
	const sl = self.ss.slice();
	return &sl[sl.len - 1];
}

pub fn ply(self: *const Board) usize {
	return self.top() - self.bottom();
}

pub fn doMove(self: *Board, move: movegen.Move) MoveError!void {
	const stm = self.top().stm;
	const s = move.src;
	const d = move.dst;
	const sp = self.top().getSquare(s);
	const dp = self.top().getSquare(d);

	self.top().move = move;
	self.top().src_piece = sp;
	self.top().dst_piece = dp;

	const pos = self.ss.addOneAssumeCapacity();
	pos.* = pos.down(1).*;
	pos.en_pas = null;
	pos.rule50 += 1;

	pos.accumulator.clear();
	pos.accumulator.mark();

	switch (move.flag) {
		.none => {
			@branchHint(.likely);
			pos.popSq(s, sp);
			pos.popSq(d, dp);
			pos.setSq(d, sp);

			if (dp == .none) {
				pos.accumulator.queueAddSub(
				  .{.piece = sp, .square = d},
				  .{.piece = sp, .square = s},
				);
			} else {
				pos.accumulator.queueAddSubSub(
				  .{.piece = sp, .square = d},
				  .{.piece = sp, .square = s},
				  .{.piece = dp, .square = d},
				);
			}
		},

		.en_passant => {
			const our_pawn = types.Piece.init(stm, .pawn);
			const their_pawn = types.Piece.init(stm.flip(), .pawn);
			const enp_target = d.shift(stm.forward().flip(), 1);

			pos.popSq(s, our_pawn);
			pos.setSq(d, our_pawn);
			pos.popSq(enp_target, their_pawn);

			pos.accumulator.queueAddSubSub(
			  .{.piece = our_pawn, .square = d},
			  .{.piece = our_pawn, .square = s},
			  .{.piece = their_pawn, .square = enp_target},
			);
		},

		.promote => {
			const our_pawn = types.Piece.init(stm, .pawn);
			const our_promotion = types.Piece.init(stm, move.info.promote.toPtype());

			pos.popSq(s, our_pawn);
			pos.popSq(d, dp);
			pos.setSq(d, our_promotion);

			if (dp == .none) {
				pos.accumulator.queueAddSub(
				  .{.piece = our_promotion, .square = d},
				  .{.piece = our_pawn, .square = s},
				);
			} else {
				pos.accumulator.queueAddSubSub(
				  .{.piece = our_promotion, .square = d},
				  .{.piece = our_pawn, .square = s},
				  .{.piece = dp, .square = d},
				);
			}
		},

		.castle => {
			const info = pos.castles.getAssertContains(move.info.castle);
			const our_rook = types.Piece.init(stm, .rook);
			const our_king = types.Piece.init(stm, .king);

			pos.popSq(info.ks, our_king);
			pos.popSq(info.rs, our_rook);

			pos.setSq(info.kd, our_king);
			pos.setSq(info.rd, our_rook);

			pos.accumulator.queueAddAddSubSub(
			  .{.piece = our_king, .square = info.kd},
			  .{.piece = our_rook, .square = info.rd},
			  .{.piece = our_king, .square = info.ks},
			  .{.piece = our_rook, .square = info.rs},
			);
		},
	}

	{
		const king = types.Piece.init(stm, .king);
		const kb = pos.pieceOcc(king);
		const ks = kb.lowSquare() orelse {
			self.undoMove();
			return error.InvalidMove;
		};

		const atkers = pos.squareAtkers(ks);
		const them = pos.colorOcc(stm.flip());
		if (atkers.bwa(them) != .none) {
			self.undoMove();
			return error.InvalidMove;
		}
	}

	switch (sp) {
		.w_pawn, .b_pawn => {
			pos.rule50 = 0;

			// TODO: check en passant (pseudo-)legality
			if (d.shift(stm.forward().flip(), 2) == s) {
				pos.en_pas = d.shift(stm.forward().flip(), 1);
			}
		},

		.w_rook, .b_rook => {
			var iter = pos.castles.iterator();
			while (iter.next()) |entry| {
				const k = entry.key;
				const v = entry.value;

				if (s == v.rs) {
					pos.popCastle(k);
					break;
				}
			}
		},

		.w_king, .b_king => {
			defer pos.popCastle(if (stm == .white) .wk else .bk);
			defer pos.popCastle(if (stm == .white) .wq else .bq);

			const ks = switch (move.flag) {
				.castle => pos.castles.getPtrConstAssertContains(move.info.castle).ks,
				else => s,
			};
			const kd = switch (move.flag) {
				.castle => pos.castles.getPtrConstAssertContains(move.info.castle).kd,
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
			if (is_s_mirrored != is_d_mirrored) {
				pos.accumulator.queueMirror(stm);
			}
		},

		else => {},
	}

	switch (dp) {
		.w_rook, .b_rook => {
			var iter = pos.castles.iterator();
			while (iter.next()) |entry| {
				const k = entry.key;
				const v = entry.value;

				if (d == v.rs) {
					pos.popCastle(k);
					break;
				}
			}
		},
		else => {},
	}

	pos.stm = stm.flip();
	pos.checks = pos.genCheckMask();
	pos.key ^= zobrist.stm()
	  ^ zobrist.enp(pos.down(1).en_pas)
	  ^ zobrist.enp(pos.en_pas);
}

pub fn doNull(self: *Board) MoveError!void {
	if (self.top().isChecked()) {
		return error.InvalidMove;
	}

	self.top().move = .{};
	self.top().src_piece = .none;
	self.top().dst_piece = .none;

	const pos = self.ss.addOneAssumeCapacity();
	pos.* = pos.down(1).*;
	pos.en_pas = null;
	pos.rule50 = 0;

	pos.accumulator.clear();
	pos.accumulator.mark();

	pos.stm = pos.stm.flip();
	pos.checks = .full;
	pos.key ^= zobrist.stm()
	  ^ zobrist.enp(pos.down(1).en_pas)
	  ^ zobrist.enp(pos.en_pas);
}

pub fn undoMove(self: *Board) void {
	_ = self.ss.pop();
}

pub fn undoNull(self: *Board) void {
	self.undoMove();
}

pub fn getRepeat(self: *const Board) usize {
	const key = self.top().key;
	var peat: usize = 0;

	for (self.ss.slice()[offset ..]) |*p| {
		const key_matched = p.key == key;
		peat += @intFromBool(key_matched);
	}
	return peat;
}

pub fn is3peat(self: *const Board) bool {
	return self.getRepeat() >= 3;
}

pub fn isDrawn(self: *const Board) bool {
	return self.top().rule50 >= 100 or self.is3peat() or self.isTerminal();
}

pub fn isTerminal(self: *const Board) bool {
	return self.ss.len >= capacity + offset;
}

pub fn evaluate(self: *Board) evaluation.score.Int {
	self.updateAccumulators();
	return self.top().evaluate();
}
