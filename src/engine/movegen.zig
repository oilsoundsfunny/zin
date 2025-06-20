const bitboard = @import("bitboard");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const search = @import("search.zig");
const transposition = @import("transposition.zig");

const Perft = struct {
	fen:	[]const u8,
	result:	[6]usize,

	pub const suite = [_]Perft {
		.{
			.fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
			.result = .{20,  400,  8902,  197281,   4865609,  119060324},
		}, .{
			.fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
			.result = .{48, 2039, 97862, 4085603, 193690690, 8031647685},
		}, .{
			.fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
			.result = .{14,  191,  2812,   43238,    674624,   11030083},
		}, .{
			.fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
			.result = .{ 6,  264,  9467,  422333,  15833292,  706045033},
		}, .{
			.fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
			.result = .{44, 1486, 62379, 2103487,  89941194, 3048196529},
		}, .{
			.fen = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
			.result = .{46, 2079, 89890, 3894594, 164075551, 6923051137},
		}, .{
			.fen = "n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1",
			.result = .{24,  496,  9483,  182838,   3605103,   71179139},
		},
	};

	fn div_recursive(pos: *Position, depth: usize, rc: usize) u64 {
		if (rc >= depth) {
			return 1;
		}

		var list = std.mem.zeroes(ScoredMove.List);
		var sum:  u64 = 0;
		var this: u64 = 0;

		_ = list.gen(pos.*, true);
		_ = list.gen(pos.*, false);
		for (list.constSlice()) |sm| {
			pos.doMove(sm.move) catch continue;
			this = div_recursive(pos, depth, rc + 1);
			pos.undoMove();

			if (rc == 0) {
				std.log.defaultLog(.debug, .div_recursive,
				  "{s}:\t{d}", .{sm.move.print()[0 ..], this});
			}

			sum += this;
		}
		return sum;
	}

	pub fn div(pos: *Position, depth: usize) u64 {
		const ret = div_recursive(pos, depth, 0);
		std.log.defaultLog(.debug, .div, "perft {d}:\t{d}", .{depth, ret});
		return ret;
	}
};

pub const Move = packed struct(u16) {
	flag:	Flag,
	promo:	Flag.Int,
	src:	misc.types.Square,
	dst:	misc.types.Square,

	pub const Flag = enum(u2) {
		nil,
		en_passant,
		promote,
		castle,

		pub const Int = @typeInfo(Flag).@"enum".tag_type;
	};

	pub const zero = std.mem.zeroes(Move);

	pub fn gen(comptime f: Flag, comptime p: misc.types.Ptype,
	  s: misc.types.Square, d: misc.types.Square) Move {
		return .{
			.flag = f,
			.promo = map: switch (p) {
				.nil => {
					if (f == .promote) {
						@compileError("unexpected tag " ++ @tagName(f));
					}
					break :map 0;
				},
				.knight, .bishop, .rook, .queen => {
					if (f != .promote) {
						@compileError("unexpected tag " ++ @tagName(f));
					}
					break :map switch (p) {
						.knight => 0,
						.bishop => 1,
						.rook   => 2,
						.queen  => 3,
						else => unreachable,
					};
				},
				else => @compileError("unexpected tag " ++ @tagName(p)),
			},
			.src = s,
			.dst = d,
		};
	}

	pub fn eql(self: Move, other: Move) bool {
		return self.flag == other.flag
		  and self.promo == other.promo
		  and self.src == other.src
		  and self.dst == other.dst;
	}
	pub fn isZero(self: Move) bool {
		return self.eql(Move.zero);
	}

	pub fn promotion(self: Move) misc.types.Ptype {
		if (self.flag != .promote) {
			std.debug.assert(self.promo == 0);
			return .nil;
		} else return switch (self.promo) {
			0 => .knight,
			1 => .bishop,
			2 => .rook,
			3 => .queen,
		};
	}

	pub fn print(self: Move) [8]u8 {
		var buf = std.mem.zeroes([8]u8);
		buf[0] = self.src.file().char() orelse unreachable;
		buf[1] = self.src.rank().char() orelse unreachable;
		buf[2] = self.dst.file().char() orelse unreachable;
		buf[3] = self.dst.rank().char() orelse unreachable;
		buf[4] = if (self.promotion() != .nil) self.promotion().char() orelse unreachable else 0;
		return buf;
	}
};

pub const ScoredMove = packed struct(u32) {
	move:	Move,
	score:	evaluation.score.Int,

	pub const List = struct {
		array:	std.BoundedArray(ScoredMove, 256 - 2 * @sizeOf(usize) / @sizeOf(ScoredMove)),
		index:	usize,

		pub const Int = usize;

		fn genCastle(self: *List, pos: Position, comptime side: misc.types.Ptype) Int {
			const len = self.constSlice().len;
			const occ = pos.allOcc();
			const stm = pos.stm;

			const cas = switch (side) {
				.king  => if (stm == .white) misc.types.Castle.wk else misc.types.Castle.bk,
				.queen => if (stm == .white) misc.types.Castle.wq else misc.types.Castle.bq,
				else => @compileError("unexpected tag " ++ @tagName(side)),
			};
			if (pos.checkMask() != .all
			  or pos.ssTop().castle.bitAnd(cas) == .nil) {
				return self.constSlice().len - len;
			}

			const their_pieces = std.EnumArray(misc.types.Ptype, misc.types.BitBoard).init(.{
				.nil = .nil,
				.pawn   = pos.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .pawn)),
				.knight = pos.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .knight)),
				.bishop = pos.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .bishop)),
				.rook   = pos.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .rook)),
				.queen  = pos.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .queen)),
				.king   = pos.pieceOcc(misc.types.Piece.fromPtype(stm.flip(), .king)),
				.all = .nil,
			});
			var atk_mask = (switch (side) {
				.king  => misc.types.BitBoard.fromSlice(misc.types.File, &.{.file_f, .file_g}),
				.queen => misc.types.BitBoard.fromSlice(misc.types.File, &.{.file_c, .file_d}),
				else => unreachable,
			}).bitAnd(stm.homeRank().bb());
			while (atk_mask != .nil) : (atk_mask.popLow()) {
				const s = atk_mask.lowSquare();
				const a = bitboard.pAtk(s.bb(), stm).bitAnd(their_pieces.get(.pawn))
				  .bitOr(bitboard.nAtk(s).bitAnd(their_pieces.get(.knight)))
				  .bitOr(bitboard.kAtk(s).bitAnd(their_pieces.get(.king)))
				  .bitOr(bitboard.bAtk(s, occ).bitAnd(their_pieces.get(.bishop)))
				  .bitOr(bitboard.rAtk(s, occ).bitAnd(their_pieces.get(.rook)))
				  .bitOr(bitboard.qAtk(s, occ).bitAnd(their_pieces.get(.queen)));
				if (a != .nil) {
					return self.constSlice().len - len;
				}
			}

			const occ_mask = (switch (side) {
				.king  => misc.types.BitBoard.fromSlice(misc.types.File,
				  &.{.file_f, .file_g}),
				.queen => misc.types.BitBoard.fromSlice(misc.types.File,
				  &.{.file_b, .file_c, .file_d}),
				else => unreachable,
			}).bitAnd(stm.homeRank().bb());
			if (occ.bitAnd(occ_mask) != .nil) {
				return self.constSlice().len - len;
			}

			const s = misc.types.Square.fromCoord(stm.homeRank(), .file_e);
			const d = s.shift(switch (side) {
				.king  => .east,
				.queen => .west,
				else => unreachable,
			}, 2);
			self.append(.{
				.move  = Move.gen(.castle, .nil, s, d),
				.score = evaluation.score.lose,
			});
			return self.constSlice().len - len;
		}

		fn genEnPassant(self: *List, pos: Position) Int {
			const en_pas = pos.ssTop().en_pas orelse return 0;
			const len = self.constSlice().len;
			const stm = pos.stm;
			const src = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .pawn));
			const dst = en_pas.bb();

			var east_atk = bitboard.pAtkEast(src, stm).bitAnd(dst);
			while (east_atk != .nil) : (east_atk.popLow()) {
				const d = east_atk.lowSquare();
				const s = d.shift(stm.forward().add(.east).flip(), 1);
				self.append(.{
					.move  = Move.gen(.en_passant, .nil, s, d),
					.score = evaluation.score.lose,
				});
			}

			var west_atk = bitboard.pAtkWest(src, stm).bitAnd(dst);
			while (west_atk != .nil) : (west_atk.popLow()) {
				const d = west_atk.lowSquare();
				const s = d.shift(stm.forward().add(.west).flip(), 1);
				self.append(.{
					.move  = Move.gen(.en_passant, .nil, s, d),
					.score = evaluation.score.lose,
				});
			}

			return self.constSlice().len - len;
		}

		fn genPromotion(self: *List, pos: Position,
		  comptime ptype: misc.types.Ptype,
		  comptime noisy: bool) Int {
			const len = self.constSlice().len;
			const occ = pos.allOcc();
			const stm = pos.stm;
			const src = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .pawn));
			const dst = pos.checkMask()
			  .bitAnd(stm.promotionRank().bb())
			  .bitAnd(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

			if (noisy) {
				var east_atk = bitboard.pAtkEast(src, stm).bitAnd(dst);
				while (east_atk != .nil) : (east_atk.popLow()) {
					const d = east_atk.lowSquare();
					const s = d.shift(stm.forward().add(.east).flip(), 1);
					self.append(.{
						.move  = Move.gen(.promote, ptype, s, d),
						.score = evaluation.score.lose,
					});
				}

				var west_atk = bitboard.pAtkWest(src, stm).bitAnd(dst);
				while (west_atk != .nil) : (west_atk.popLow()) {
					const d = west_atk.lowSquare();
					const s = d.shift(stm.forward().add(.west).flip(), 1);
					self.append(.{
						.move  = Move.gen(.promote, ptype, s, d),
						.score = evaluation.score.lose,
					});
				}
			} else {
				var push = bitboard.pPush1(src, occ, stm).bitAnd(dst);
				while (push != .nil) : (push.popLow()) {
					const d = push.lowSquare();
					const s = d.shift(stm.forward().flip(), 1);
					self.append(.{
						.move  = Move.gen(.promote, ptype, s, d),
						.score = evaluation.score.lose,
					});
				}

				push = bitboard.pPush2(src, occ, stm).bitAnd(dst);
				while (push != .nil) : (push.popLow()) {
					const d = push.lowSquare();
					const s = d.shift(stm.forward().flip(), 2);
					self.append(.{
						.move  = Move.gen(.promote, ptype, s, d),
						.score = evaluation.score.lose,
					});
				}
			}

			return self.constSlice().len - len;
		}

		fn genPawnMoves(self: *List, pos: Position, comptime noisy: bool) Int {
			const len = self.constSlice().len;
			const occ = pos.allOcc();
			const stm = pos.stm;
			const src = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .pawn));
			const dst = pos.checkMask()
			  .bitAnd(stm.promotionRank().bb().flip())
			  .bitAnd(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

			if (noisy) {
				var east_atk = bitboard.pAtkEast(src, stm).bitAnd(dst);
				while (east_atk != .nil) : (east_atk.popLow()) {
					const d = east_atk.lowSquare();
					const s = d.shift(stm.forward().add(.east).flip(), 1);
					self.append(.{
						.move  = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.lose,
					});
				}

				var west_atk = bitboard.pAtkWest(src, stm).bitAnd(dst);
				while (west_atk != .nil) : (west_atk.popLow()) {
					const d = west_atk.lowSquare();
					const s = d.shift(stm.forward().add(.west).flip(), 1);
					self.append(.{
						.move  = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.lose,
					});
				}
			} else {
				var push = bitboard.pPush1(src, occ, stm).bitAnd(dst);
				while (push != .nil) : (push.popLow()) {
					const d = push.lowSquare();
					const s = d.shift(stm.forward().flip(), 1);
					self.append(.{
						.move  = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.lose,
					});
				}

				push = bitboard.pPush2(src, occ, stm).bitAnd(dst);
				while (push != .nil) : (push.popLow()) {
					const d = push.lowSquare();
					const s = d.shift(stm.forward().flip(), 2);
					self.append(.{
						.move  = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.lose,
					});
				}
			}

			return self.constSlice().len - len;
		}

		fn genPieceMoves(self: *List, pos: Position,
		  comptime ptype: misc.types.Ptype,
		  comptime noisy: bool) Int {
			const len = self.constSlice().len;
			const occ = pos.allOcc();
			const stm = pos.stm;
			const target = misc.types.BitBoard.all
			  .bitAnd(if (ptype != .king) pos.checkMask() else .all)
			  .bitAnd(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

			var src = pos.pieceOcc(misc.types.Piece.fromPtype(stm, ptype));
			while (src != .nil) : (src.popLow()) {
				const s = src.lowSquare();
				var dst = bitboard.ptAtk(ptype, s, occ).bitAnd(target);
				while (dst != .nil) : (dst.popLow()) {
					const d = dst.lowSquare();
					self.append(.{
						.move  = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.lose,
					});
				}
			}
			return self.constSlice().len - len;
		}

		pub fn append(self: *List, sm: ScoredMove) void {
			self.array.append(sm) catch @panic("hit the movegen lottery");
		}
		pub fn resize(self: *List, len: usize) void {
			self.array.resize(len) catch @panic("hit the movegen lottery");
		}

		pub fn constSlice(self: *const List) []const ScoredMove {
			return self.array.constSlice();
		}
		pub fn slice(self: *List) []ScoredMove {
			return self.array.slice();
		}

		pub fn gen(self: *List, pos: Position, comptime noisy: bool) Int {
			var len: Int = 0;
			if (noisy) {
				len += self.genPromotion(pos, .queen,  true);
				len += self.genPromotion(pos, .rook,   true);
				len += self.genPromotion(pos, .bishop, true);
				len += self.genPromotion(pos, .knight, true);
				len += self.genPromotion(pos, .queen,  false);
				len += self.genPromotion(pos, .knight, false);
				len += self.genEnPassant(pos);
				len += self.genPawnMoves(pos, true);
				len += self.genPieceMoves(pos, .knight, true);
				len += self.genPieceMoves(pos, .bishop, true);
				len += self.genPieceMoves(pos, .rook,   true);
				len += self.genPieceMoves(pos, .queen,  true);
				len += self.genPieceMoves(pos, .king,   true);
			} else {
				len += self.genPromotion(pos, .rook,   false);
				len += self.genPromotion(pos, .bishop, false);
				len += self.genPawnMoves(pos, false);
				len += self.genCastle(pos, .king);
				len += self.genCastle(pos, .queen);
				len += self.genPieceMoves(pos, .knight, false);
				len += self.genPieceMoves(pos, .bishop, false);
				len += self.genPieceMoves(pos, .rook,   false);
				len += self.genPieceMoves(pos, .queen,  false);
				len += self.genPieceMoves(pos, .king,   false);
			}
			return len;
		}

		pub fn sort(self: *List) void {
			std.sort.insertion(ScoredMove, self.slice(), {}, desc);
		}
	};

	pub fn desc(_: void, a: ScoredMove, b: ScoredMove) bool {
		return a.score > b.score;
	}
};
test {
	try std.testing.expectEqual(@sizeOf(ScoredMove) * 256, @sizeOf(ScoredMove.List));
}
test {
	const pos = try std.testing.allocator.create(Position);
	defer std.testing.allocator.destroy(pos);

	for (Perft.suite[0 .. 0]) |ref| {
		try pos.parseFen(ref.fen);
		for (ref.result[0 .. 4], 1 ..) |expected, depth| {
			const actual = Perft.div(pos, depth);
			try std.testing.expectEqual(expected, actual);
		}
	}
}

pub const RootMove = struct {
	line:	std.BoundedArray(Move, 256 - 2 * @sizeOf(usize) / @sizeOf(Move)),
	score:	isize,

	pub const List = struct {
		array:	std.BoundedArray(RootMove, 256),

		pub fn append(self: *List, rm: RootMove) void {
			self.array.append(rm) catch @panic("hit the movegen lottery");
		}
		pub fn init(len: usize) !List {
			return .{
				.array = try std.BoundedArray(RootMove, 256).init(len),
			};
		}

		pub fn constSlice(self: *const List) []const RootMove {
			return self.array.constSlice();
		}
		pub fn slice(self: *List) []RootMove {
			return self.array.slice();
		}
		pub fn pv(self: List) RootMove {
			return self.constSlice()[0];
		}

		pub fn sort(self: *List) void {
			sortSlice(self.slice());
		}

		pub fn fromInfo(info: *search.Info) List {
			var array = List.init(0) catch unreachable;
			var list = std.mem.zeroes(ScoredMove.List);
			_ = list.gen(info.pos, true);
			_ = list.gen(info.pos, false);
			for (list.slice()) |*sm| {
				info.pos.doMove(sm.move) catch {
					sm.* = .{
						.move  = Move.zero,
						.score = evaluation.score.nil,
					};
					continue;
				};
				defer info.pos.undoMove();

				const tt_fetch = transposition.Table.global.fetch(info.pos.ssTop().key);
				const tte = tt_fetch[0];
				const hit = tt_fetch[1];
				if (hit) {
					sm.score = tte.?.score;
				}

				var rm: RootMove = undefined;
				rm.line = @TypeOf(rm.line).init(0) catch unreachable;
				rm.line.append(sm.move) catch unreachable;
				rm.score = sm.score;
				array.append(rm);
			}
			sortSlice(array.slice());

			return array;
		}
	};

	pub fn desc(_: void, a: RootMove, b: RootMove) bool {
		return a.score > b.score;
	}
	pub fn sortSlice(rms: []RootMove) void {
		std.sort.insertion(RootMove, rms, {}, desc);
	}
};
test {
	try std.testing.expectEqual(@sizeOf(RootMove) * 256 + @sizeOf(usize), @sizeOf(RootMove.List));
}

pub const Picker = struct {
	list:	ScoredMove.List,
	info:	*search.Info,

	noisy:	bool,
	stage:	Stage,

	ttm:	Move,
	killer0:	Move,
	killer1:	Move,

	noisy_cnt:	usize,
	quiet_cnt:	usize,
	bad_noisy_cnt:	usize,
	bad_quiet_cnt:	usize,

	pub const Stage = enum(u8) {
		ttm,
		gen_noisy, good_noisy,
		killer0, killer1,
		gen_quiet, good_quiet,
		bad_noisy,
		bad_quiet,

		pub const Int = std.meta.Tag(Stage);

		pub fn int(self: Stage) Int {
			return @intFromEnum(self);
		}
		pub fn inc(self: Stage) Stage {
			return @enumFromInt(self.int() + 1);
		}
	};

	fn pick(self: *Picker) ?ScoredMove {
		while (self.list.index < self.list.constSlice().len) {
			const sm = self.list.constSlice()[self.list.index];
			self.list.index += 1;

			if (!sm.move.eql(self.ttm)
			  and !sm.move.eql(self.killer0)
			  and !sm.move.eql(self.killer1)) {
				return sm;
			}
		}
		return null;
	}

	pub fn init(info: *search.Info, ttm: Move, killer0: Move, killer1: Move, noisy: bool) Picker {
		return .{
			.list = std.mem.zeroes(ScoredMove.List),
			.info = info,
			.noisy = noisy,
			.stage = if (ttm.isZero()) .gen_noisy else .ttm,
			.ttm = ttm,
			.killer0 = killer0,
			.killer1 = killer1,
			.noisy_cnt = 0,
			.quiet_cnt = 0,
			.bad_noisy_cnt = 0,
			.bad_quiet_cnt = 0,
		};
	}

	pub fn next(self: *Picker) ?Move {
		if (self.stage == .ttm) {
			self.stage = self.stage.inc();
			if (!self.ttm.isZero()) {
				return self.ttm;
			}
		}

		if (self.stage == .gen_noisy) {
			self.stage = self.stage.inc();
			self.noisy_cnt = self.list.gen(self.info.pos, true);

			for (self.list.slice()) |*sm| {
				const key = self.info.pos.keyAfterMove(sm.move);
				const tt_fetch = transposition.Table.global.fetch(key);
				const tte = tt_fetch[0] orelse continue;
				const hit = tt_fetch[1];
				if (hit) {
					sm.score = tte.score;
				}
			}
			self.list.sort();
		}

		while (self.stage == .good_noisy) {
			const sm = self.pick() orelse {
				self.stage = self.stage.inc();
				self.list.resize(self.bad_noisy_cnt);
				self.list.index = self.bad_noisy_cnt;
				break;
			};
			if (false) {
				self.list.slice()[self.bad_noisy_cnt] = sm;
				self.bad_noisy_cnt += 1;
			} else return sm.move;
		}

		if (self.stage == .killer0) {
			self.stage = self.stage.inc();
			if (!self.killer0.isZero()
			  and !self.killer0.eql(self.ttm)) {
				return self.killer0;
			}
		}

		if (self.stage == .killer1) {
			self.stage = self.stage.inc();
			if (!self.killer1.isZero()
			  and !self.killer1.eql(self.ttm)
			  and !self.killer1.eql(self.killer0)) {
				return self.killer1;
			}
		}

		if (self.stage == .gen_quiet) {
			self.stage = self.stage.inc();
			if (!self.noisy) {
				self.quiet_cnt = self.list.gen(self.info.pos, false);

				for (self.list.slice()) |*sm| {
					const key = self.info.pos.keyAfterMove(sm.move);
					const tt_fetch = transposition.Table.global.fetch(key);
					const tte = tt_fetch[0] orelse continue;
					const hit = tt_fetch[1];
					if (hit) {
						sm.score = tte.score;
					}
				}
				self.list.sort();
			}
		}

		while (self.stage == .good_quiet) {
			const sm = self.pick() orelse {
				self.stage = self.stage.inc();
				self.list.resize(self.bad_noisy_cnt);
				self.list.index = 0;
				break;
			};
			if (false) {
				self.list.slice()[self.bad_noisy_cnt + self.bad_quiet_cnt] = sm;
				self.bad_quiet_cnt += 1;
			} else return sm.move;
		}

		while (self.stage == .bad_noisy) {
			const sm = self.pick() orelse {
				self.stage = self.stage.inc();
				self.list.resize(self.bad_noisy_cnt + self.bad_quiet_cnt);
				self.list.index = self.bad_noisy_cnt;
				break;
			};
			return sm.move;
		}

		while (self.stage == .bad_quiet) {
			const sm = self.pick() orelse break;
			return sm.move;
		}

		return null;
	}
};

test {
	const seq = [_]Move {
	  Move.gen(.nil, .nil, .g2, .h3),
	  Move.gen(.nil, .nil, .d5, .e6),

	  Move.gen(.nil, .nil, .e5, .g6),
	  Move.gen(.nil, .nil, .e5, .d7),
	  Move.gen(.nil, .nil, .e5, .f7),

	  Move.gen(.nil, .nil, .e2, .a6),

	  Move.gen(.nil, .nil, .f3, .h3),
	  Move.gen(.nil, .nil, .f3, .f6),
	};

	const info = try misc.heap.allocator.create(search.Info);
	try info.pos.parseFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
	defer misc.heap.allocator.destroy(info);

	var noisy_mp = Picker.init(info, Move.zero, Move.zero, Move.zero, true);
	for (seq[0 ..]) |move| {
		try std.testing.expectEqual(move, noisy_mp.next());
	}
}
