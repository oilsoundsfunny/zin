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

		var list = std.mem.zeroes(Move.List);
		var sum:  u64 = 0;
		var this: u64 = 0;

		_ = list.genNoisy(pos.*);
		_ = list.genQuiet(pos.*);
		for (list.constSlice()) |move| {
			pos.doMove(move) catch continue;
			this = div_recursive(pos, depth, rc + 1);
			pos.undoMove();

			if (rc == 0) {
				std.log.defaultLog(.debug, .div_recursive,
				  "{s}:\t{d}", .{move.print()[0 ..], this});
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

const ScoredMove = packed struct(u32) {
	move:	Move,
	score:	evaluation.score.Int,

	pub const List = struct {
		array:	std.BoundedArray(ScoredMove, 256 - 2 * @sizeOf(usize) / @sizeOf(ScoredMove))
		  = std.BoundedArray(ScoredMove, 256 - 2 * @sizeOf(usize) / @sizeOf(ScoredMove)).init(0)
		  catch unreachable,
		index:	usize = 0,

		pub const Int = usize;

		pub fn append(self: *List, sm: ScoredMove) void {
			self.array.append(sm) catch unreachable;
		}
		pub fn resize(self: *List, len: usize) void {
			self.array.resize(len) catch unreachable;
		}

		pub fn constSlice(self: *const List) []const ScoredMove {
			return self.array.constSlice();
		}
		pub fn slice(self: *List) []ScoredMove {
			return self.array.slice();
		}

		pub fn sort(self: *List) void {
			sortSlice(self.slice());
		}
	};

	pub fn desc(_: void, a: ScoredMove, b: ScoredMove) bool {
		return a.score > b.score;
	}
	pub fn sortSlice(slice: []ScoredMove) void {
		std.sort.insertion(ScoredMove, slice, {}, desc);
	}
};
test {
	try std.testing.expectEqual(@sizeOf(ScoredMove) * 256, @sizeOf(ScoredMove.List));
}

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

	pub const List = struct {
		array:	std.BoundedArray(Move, 256 - @sizeOf(usize) / @sizeOf(Move))
		  = std.BoundedArray(Move, 256 - @sizeOf(usize) / @sizeOf(Move)).init(0)
		  catch unreachable,

		pub const Int = usize;

		fn genCastle(self: *List, pos: Position, comptime side: misc.types.Ptype) void {
			const occ = pos.allOcc();
			const stm = pos.stm;

			const cas = switch (side) {
				.king  => if (stm == .white) misc.types.Castle.wk else misc.types.Castle.bk,
				.queen => if (stm == .white) misc.types.Castle.wq else misc.types.Castle.bq,
				else => @compileError("unexpected tag " ++ @tagName(side)),
			};
			if (pos.checkMask() != .all
			  or pos.ssTop().castle.bitAnd(cas) == .nil) {
				return;
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
					return;
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
				return;
			}

			const s = misc.types.Square.fromCoord(stm.homeRank(), .file_e);
			const d = s.shift(switch (side) {
				.king  => .east,
				.queen => .west,
				else => unreachable,
			}, 2);
			self.append(Move.gen(.castle, .nil, s, d));
		}

		fn genEnPassant(self: *List, pos: Position) void {
			const en_pas = pos.ssTop().en_pas orelse return;
			const stm = pos.stm;
			const src = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .pawn));
			const dst = en_pas.bb();

			var east_atk = bitboard.pAtkEast(src, stm).bitAnd(dst);
			while (east_atk != .nil) : (east_atk.popLow()) {
				const d = east_atk.lowSquare();
				const s = d.shift(stm.forward().add(.east).flip(), 1);
				self.append(Move.gen(.en_passant, .nil, s, d));
			}

			var west_atk = bitboard.pAtkWest(src, stm).bitAnd(dst);
			while (west_atk != .nil) : (west_atk.popLow()) {
				const d = west_atk.lowSquare();
				const s = d.shift(stm.forward().add(.west).flip(), 1);
				self.append(Move.gen(.en_passant, .nil, s, d));
			}
		}

		fn genPromotion(self: *List, pos: Position,
		  comptime ptype: misc.types.Ptype,
		  comptime noisy: bool) void {
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
					self.append(Move.gen(.promote, ptype, s, d));
				}

				var west_atk = bitboard.pAtkWest(src, stm).bitAnd(dst);
				while (west_atk != .nil) : (west_atk.popLow()) {
					const d = west_atk.lowSquare();
					const s = d.shift(stm.forward().add(.west).flip(), 1);
					self.append(Move.gen(.promote, ptype, s, d));
				}
			} else {
				var push = bitboard.pPush1(src, occ, stm).bitAnd(dst);
				while (push != .nil) : (push.popLow()) {
					const d = push.lowSquare();
					const s = d.shift(stm.forward().flip(), 1);
					self.append(Move.gen(.promote, ptype, s, d));
				}

				push = bitboard.pPush2(src, occ, stm).bitAnd(dst);
				while (push != .nil) : (push.popLow()) {
					const d = push.lowSquare();
					const s = d.shift(stm.forward().flip(), 2);
					self.append(Move.gen(.promote, ptype, s, d));
				}
			}
		}

		fn genPawnMoves(self: *List, pos: Position, comptime noisy: bool) void {
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
					self.append(Move.gen(.nil, .nil, s, d));
				}

				var west_atk = bitboard.pAtkWest(src, stm).bitAnd(dst);
				while (west_atk != .nil) : (west_atk.popLow()) {
					const d = west_atk.lowSquare();
					const s = d.shift(stm.forward().add(.west).flip(), 1);
					self.append(Move.gen(.nil, .nil, s, d));
				}
			} else {
				var push = bitboard.pPush1(src, occ, stm).bitAnd(dst);
				while (push != .nil) : (push.popLow()) {
					const d = push.lowSquare();
					const s = d.shift(stm.forward().flip(), 1);
					self.append(Move.gen(.nil, .nil, s, d));
				}

				push = bitboard.pPush2(src, occ, stm).bitAnd(dst);
				while (push != .nil) : (push.popLow()) {
					const d = push.lowSquare();
					const s = d.shift(stm.forward().flip(), 2);
					self.append(Move.gen(.nil, .nil, s, d));
				}
			}
		}

		fn genPieceMoves(self: *List, pos: Position,
		  comptime ptype: misc.types.Ptype,
		  comptime noisy: bool) void {
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
					self.append(Move.gen(.nil, .nil, s, d));
				}
			}
		}

		pub fn genNoisy(self: *List, pos: Position) Int {
			const len = self.array.len;
			self.genPromotion(pos, .queen,  true);
			self.genPromotion(pos, .rook,   true);
			self.genPromotion(pos, .bishop, true);
			self.genPromotion(pos, .knight, true);
			self.genPromotion(pos, .queen,  false);
			self.genPromotion(pos, .knight, false);
			self.genEnPassant(pos);
			self.genPawnMoves(pos, true);
			self.genPieceMoves(pos, .knight, true);
			self.genPieceMoves(pos, .bishop, true);
			self.genPieceMoves(pos, .rook,   true);
			self.genPieceMoves(pos, .queen,  true);
			self.genPieceMoves(pos, .king,   true);
			return self.array.len - len;
		}
		pub fn genQuiet(self: *List, pos: Position) Int {
			const len = self.array.len;
			self.genPromotion(pos, .rook,   false);
			self.genPromotion(pos, .bishop, false);
			self.genPawnMoves(pos, false);
			self.genCastle(pos, .king);
			self.genCastle(pos, .queen);
			self.genPieceMoves(pos, .knight, false);
			self.genPieceMoves(pos, .bishop, false);
			self.genPieceMoves(pos, .rook,   false);
			self.genPieceMoves(pos, .queen,  false);
			self.genPieceMoves(pos, .king,   false);
			return self.array.len - len;
		}

		pub fn append(self: *List, move: Move) void {
			self.array.append(move) catch unreachable;
		}
		pub fn resize(self: *List, len: usize) void {
			self.array.resize(len) catch unreachable;
		}

		pub fn slice(self: *List) []Move {
			return self.array.slice();
		}
		pub fn constSlice(self: *const List) []const Move {
			return self.array.constSlice();
		}
	};

	pub const Scored = ScoredMove;

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
test {
	try std.testing.expectEqual(@sizeOf(Move) * 256, @sizeOf(Move.List));
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
			self.array.append(rm) catch unreachable;
		}
		pub fn init(len: usize) !List {
			return .{
				.array = try std.BoundedArray(RootMove, 256).init(len),
			};
		}
		pub fn clear(self: *List) void {
			self.array.len = 0;
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
			var list = std.mem.zeroes(Move.List);
			_ = list.genNoisy(info.pos);
			_ = list.genQuiet(info.pos);
			for (list.constSlice()) |move| {
				info.pos.doMove(move) catch continue;
				defer info.pos.undoMove();

				const tt_fetch = transposition.Table.global.fetch(info.pos.ssTop().key);
				const tte = tt_fetch[0];
				const hit = tt_fetch[1];

				var score: evaluation.score.Int = evaluation.score.lose;
				if (hit) {
					score = tte.?.score;
				}

				var rm: RootMove = undefined;
				rm.line = @TypeOf(rm.line).init(0) catch unreachable;
				rm.line.append(move) catch unreachable;
				rm.score = score;
				array.append(rm);
			}

			array.sort();
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
	list:	Move.Scored.List = .{},
	noisy_list:	Move.List = .{},
	quiet_list:	Move.List = .{},
	info:	*search.Info = undefined,

	noisy:	bool = false,
	stage:	Stage = .ttm,

	ttm:	Move = Move.zero,
	killer0:	Move = Move.zero,
	killer1:	Move = Move.zero,

	noisy_cnt:	usize = 0,
	quiet_cnt:	usize = 0,
	bad_noisy_cnt:	usize = 0,
	bad_quiet_cnt:	usize = 0,

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

	pub const order = struct {
		pub const ttm = 40;

		pub const noisy_max
		  = evaluation.Taper.pts.get(.queen).avg() * 2
		  - evaluation.Taper.pts.get(.pawn).avg();

		pub const killer0 = 20;
		pub const killer1 = 10;
		pub const cm_bonus = 5;
	};

	fn pick(self: *Picker) ?Move.Scored {
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

	fn scoreNoisy(self: *Picker, move: Move) isize {
		if (move == self.ttm) {
			return order.noisy_max + order.ttm;
		} else {
			const dst_ptype = self.info.pos.getSquare(move.dst).ptype();
			return evaluation.Taper.pts.get(dst_ptype).avg() * 4
			  + self.info.getCaptHist(move);
		}
	}

	fn scoreQuiet(self: *Picker, move: Move) isize {
		if (move == self.ttm) {
			return order.noisy_max + order.ttm;
		} else if (move == self.killer0) {
			return order.noisy_max + order.killer0;
		} else if (move == self.killer1) {
			return order.noisy_max + order.killer1;
		} else if (move == self.info.getCounterMove()) {
			return order.noisy_max + order.cm_bonus;
		} else {
			return self.info.getCutHist(move)
			  + self.info.getCounterMoveHist(move);
		}
	}

	pub fn init(info: *search.Info, ttm: Move, killer0: Move, killer1: Move, noisy: bool) Picker {
		return .{
			.info = info,
			.noisy = noisy,
			.stage = if (!ttm.isZero()) .ttm else .gen_noisy,
			.ttm = ttm,
			.killer0 = killer0,
			.killer1 = killer1,
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
			self.list = .{};
			self.noisy_cnt = self.noisy_list.genNoisy(self.info.pos);

			for (self.constAllNoisyMoves()) |move| {
				const score = self.scoreNoisy(move);
				self.list.append(.{
					.move  = move,
					.score = @intCast(std.math.clamp(score,
					  evaluation.score.lose, evaluation.score.win)),
				});
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
				self.quiet_cnt = self.quiet_list.genQuiet(self.info.pos);
				for (self.constAllQuietMoves()) |move| {
					const score = self.scoreQuiet(move);
					self.list.append(.{
						.move  = move,
						.score = @intCast(std.math.clamp(score,
						  evaluation.score.lose, evaluation.score.win)),
					});
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

	pub fn allNoisyMoves(self: *Picker) []Move {
		return self.noisy_list.slice();
	}
	pub fn allQuietMoves(self: *Picker) []Move {
		return self.quiet_list.slice();
	}

	pub fn constAllNoisyMoves(self: *const Picker) []const Move {
		return self.noisy_list.constSlice();
	}
	pub fn constAllQuietMoves(self: *const Picker) []const Move {
		return self.quiet_list.constSlice();
	}

	pub fn isNoisy(self: Picker) bool {
		return self.stage == .good_noisy or self.stage == .bad_noisy;
	}
	pub fn isQuiet(self: Picker) bool {
		return self.stage == .good_quiet or self.stage == .bad_quiet;
	}
};

pub fn see(pos: Position, move: Move) isize {
	var gain = std.BoundedArray(isize, misc.types.Square.num).init(0) catch unreachable;

	const src = move.src;
	const dst = move.dst;
	const src_ptype = pos.getSquare(src).ptype();
	const dst_ptype = pos.getSquare(dst).ptype();
	const promotion = move.promotion();

	gain.append(evaluation.Taper.pts.get(dst_ptype).avg()
	  + evaluation.Taper.pts.get(promotion).avg()) catch unreachable;
	gain.append(evaluation.Taper.pts.get(src_ptype).avg() - gain.buffer[0]) catch unreachable;

	const diag = pos.ptypeOcc(.queen).bitOr(pos.ptypeOcc(.bishop));
	const line = pos.ptypeOcc(.queen).bitOr(pos.ptypeOcc(.rook));
	var atk = pos.squareAtkers(dst);
	var occ = pos.allOcc().bitXor(src.bb()).bitXor(dst.bb());
	var stm = pos.stm;

	while (true) {
		atk = atk.bitAnd(occ);
		stm = stm.flip();

		const this_gain = gain.buffer[gain.constSlice().len - 1];
		const our_atker = atk.bitAnd(pos.colorOcc(stm));
		const their_atker = atk.bitXor(our_atker);

		if (our_atker == .nil) {
			break;
		}

		const our_pieces = std.EnumArray(misc.types.Ptype, misc.types.BitBoard).init(.{
			.nil = .nil,
			.pawn   = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .pawn)),
			.knight = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .knight)),
			.bishop = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .bishop)),
			.rook   = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .rook)),
			.queen  = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .queen)),
			.king   = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .king)),
			.all = .nil,
		});

		if (our_atker.bitAnd(our_pieces.get(.pawn)) != .nil) {
			gain.append(evaluation.Taper.pts.get(.pawn).avg() - this_gain) catch unreachable;

			const least = our_atker.bitAnd(our_pieces.get(.pawn));
			occ = occ.bitXor(least.getLow());
			atk = atk.bitOr(bitboard.bAtk(dst, occ).bitAnd(diag));
		} else if (our_atker.bitAnd(our_pieces.get(.knight)) != .nil) {
			gain.append(evaluation.Taper.pts.get(.knight).avg() - this_gain) catch unreachable;

			const least = our_atker.bitAnd(our_pieces.get(.knight));
			occ = occ.bitXor(least.getLow());
		} else if (our_atker.bitAnd(our_pieces.get(.bishop)) != .nil) {
			gain.append(evaluation.Taper.pts.get(.bishop).avg() - this_gain) catch unreachable;

			const least = our_atker.bitAnd(our_pieces.get(.bishop));
			occ = occ.bitXor(least.getLow());
			atk = atk.bitOr(bitboard.bAtk(dst, occ).bitAnd(diag));
		} else if (our_atker.bitAnd(our_pieces.get(.rook)) != .nil) {
			gain.append(evaluation.Taper.pts.get(.rook).avg() - this_gain) catch unreachable;

			const least = our_atker.bitAnd(our_pieces.get(.rook));
			occ = occ.bitXor(least.getLow());
			atk = atk.bitOr(bitboard.rAtk(dst, occ).bitAnd(line));
		} else if (our_atker.bitAnd(our_pieces.get(.queen)) != .nil) {
			gain.append(evaluation.Taper.pts.get(.queen).avg() - this_gain) catch unreachable;

			const least = our_atker.bitAnd(our_pieces.get(.queen));
			occ = occ.bitXor(least.getLow());
			atk = atk
			  .bitOr(bitboard.bAtk(dst, occ).bitAnd(diag))
			  .bitOr(bitboard.rAtk(dst, occ).bitAnd(line));
		} else if (their_atker == .nil) {
			gain.append(evaluation.Taper.pts.get(.king).avg() - this_gain) catch unreachable;
			break;
		} else break;
	}

	var reverse_gain = std.mem.reverseIterator(gain.slice()[0 .. gain.slice().len - 2]);
	while (reverse_gain.nextPtr()) |p| {
		const s: []isize = @as([*]isize, @ptrCast(p))[0 .. 2];
		s[0] = -@max(-s[0], s[1]);
	}
	return gain.constSlice()[0];
}

test {
	var pos = Position {};

	const move0 = Move.gen(.nil, .nil, .e1, .e5);
	try pos.parseFen("1k1r4/1pp4p/p7/4p3/8/P5P1/1PP4P/2K1R3 w - - 0 1");
	try std.testing.expectEqual(see(pos, move0), evaluation.Taper.pts.get(.pawn).avg());

	const move1 = Move.gen(.nil, .nil, .d3, .e5);
	try pos.parseFen("1k1r3q/1ppn3p/p4b2/4p3/8/P2N2P1/1PP1R1BP/2K1Q3 w - - 0 1");
	try std.testing.expectEqual(see(pos, move1),
	  evaluation.Taper.pts.get(.pawn).avg() - evaluation.Taper.pts.get(.knight).avg());
}
