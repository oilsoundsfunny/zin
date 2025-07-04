const bitboard = @import("bitboard");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const search = @import("search.zig");

const RootMove = struct {
	score:	evaluation.score.Int = evaluation.score.draw,
	line:	std.BoundedArray(Move, length) = .{
		.buffer = .{Move {}} ** length,
		.len = 0,
	},

	pub const List = struct {
		array:	std.BoundedArray(RootMove, 256) = .{
			.buffer = .{RootMove {}} ** 256,
			.len = 0,
		},

		pub fn append(self: *List, rm: RootMove) void {
			self.array.append(rm)
				catch std.debug.panic("too many root moves", .{});
		}

		pub fn constSlice(self: *const List) []const RootMove {
			return self.slice();
		}

		pub fn slice(self: anytype) switch (@TypeOf(self)) {
			*const List => []const RootMove,
			*List => []RootMove,
			else => @compileError("unexpected type " ++ @typeName(@TypeOf(self))),
		} {
			return self.array.slice();
		}

		pub fn fromPosition(pos: *Position) List {
			var list = std.mem.zeroInit(List, .{});
			var sm_list = std.mem.zeroInit(Move.Scored.List, .{});

			_ = sm_list.genNoisy(pos.*);
			_ = sm_list.genQuiet(pos.*);
			for (sm_list.constSlice()) |sm| {
				const move = sm.move;
				pos.doMove(move) catch continue;
				defer pos.undoMove();

				var rm = std.mem.zeroInit(RootMove, .{});
				rm.line.append(move) catch unreachable;
				list.append(rm);
			}

			return list;
		}
	};

	const length = 256 - 2 * @sizeOf(usize) / @sizeOf(Move);

	pub fn sortSlice(slice: []RootMove) void {
		const desc = struct {
			pub fn inner(_: void, a: RootMove, b: RootMove) bool {
				return a.score > b.score;
			}
		}.inner;
		std.sort.insertion(RootMove, slice, {}, desc);
	}
};

const ScoredMove = packed struct(u32) {
	move:	Move = .{},
	score:	evaluation.score.Int = evaluation.score.draw,

	pub const List = struct {
		array:	std.BoundedArray(ScoredMove, capacity) = .{
			.buffer = .{ScoredMove {}} ** capacity,
			.len = 0,
		},
		index:	usize = 0,

		const capacity = 256 - 2 * @sizeOf(usize) / @sizeOf(ScoredMove);

		fn genCastle(self: *List, pos: Position, comptime side: misc.types.Ptype) usize {
			const cnt = self.array.len;
			const stm = pos.side2move;
			const occ = pos.allOcc();

			var atk_mask = misc.types.BitBoard.nil;
			var occ_mask = misc.types.BitBoard.nil;
			switch (side) {
			}
		}

		fn genPromotions(self: *List, pos: Position,
		  comptime promo: misc.types.Ptype,
		  comptime noisy: bool) usize {
			const cnt = self.array.len;
			const stm = pos.side2move;
			const occ = pos.allOcc();
			const src = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .pawn));
			const dst = pos.ss.top().checkers
			  .bitAnd(stm.promotionRank().bb())
			  .bitAnd(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

			if (noisy) {
				var east_atk = bitboard.pAtkEast(src, stm).bitAnd(dst);
				while (east_atk != .nil) : (east_atk.popLow()) {
					const d = east_atk.lowSquare();
					const s = d.shift(stm.forward().add(.east).flip(), 1);
					self.append(.{
						.move = Move.gen(.promote, promo, s, d),
						.score = evaluation.score.draw,
					});
				}

				var west_atk = bitboard.pAtkWest(src, stm).bitAnd(dst);
				while (west_atk != .nil) : (west_atk.popLow()) {
					const d = west_atk.lowSquare();
					const s = d.shift(stm.forward().add(.west).flip(), 1);
					self.append(.{
						.move = Move.gen(.promote, promo, s, d),
						.score = evaluation.score.draw,
					});
				}
			} else {
				var push1 = bitboard.pPush1(src, occ, stm).bitAnd(dst);
				while (push1 != .nil) : (push1.popLow()) {
					const d = push1.lowSquare();
					const s = d.shift(stm.forward().flip(), 1);
					self.append(.{
						.move = Move.gen(.promote, promo, s, d),
						.score = evaluation.score.draw,
					});
				}

				var push2 = bitboard.pPush2(src, occ, stm).bitAnd(dst);
				while (push2 != .nil) : (push2.popLow()) {
					const d = push2.lowSquare();
					const s = d.shift(stm.forward().flip(), 2);
					self.append(.{
						.move = Move.gen(.promote, promo, s, d),
						.score = evaluation.score.draw,
					});
				}
			}

			return self.array.len - cnt;
		}

		fn genPawnMoves(self: *List, pos: Position, comptime noisy: bool) usize {
			const cnt = self.array.len;
			const stm = pos.side2move;
			const occ = pos.allOcc();
			const src = pos.pieceOcc(misc.types.Piece.fromPtype(stm, .pawn));
			const dst = pos.ss.top().checkers
			  .bitAnd(stm.promotionRank().bb().flip())
			  .bitAnd(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

			if (noisy) {
				var east_atk = bitboard.pAtkEast(src, stm).bitAnd(dst);
				while (east_atk != .nil) : (east_atk.popLow()) {
					const d = east_atk.lowSquare();
					const s = d.shift(stm.forward().add(.east).flip(), 1);
					self.append(.{
						.move = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.draw,
					});
				}

				var west_atk = bitboard.pAtkWest(src, stm).bitAnd(dst);
				while (west_atk != .nil) : (west_atk.popLow()) {
					const d = west_atk.lowSquare();
					const s = d.shift(stm.forward().add(.west).flip(), 1);
					self.append(.{
						.move = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.draw,
					});
				}
			} else {
				var push1 = bitboard.pPush1(src, occ, stm).bitAnd(dst);
				while (push1 != .nil) : (push1.popLow()) {
					const d = push1.lowSquare();
					const s = d.shift(stm.forward().flip(), 1);
					self.append(.{
						.move = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.draw,
					});
				}

				var push2 = bitboard.pPush2(src, occ, stm).bitAnd(dst);
				while (push2 != .nil) : (push2.popLow()) {
					const d = push2.lowSquare();
					const s = d.shift(stm.forward().flip(), 2);
					self.append(.{
						.move = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.draw,
					});
				}
			}

			return self.array.len - cnt;
		}

		fn genPtypeMoves(self: *List, pos: Position,
		  comptime ptype: misc.types.Ptype,
		  comptime noisy: bool) usize {
			const cnt = self.array.len;
			const stm = pos.side2move;
			const occ = pos.allOcc();
			const target = misc.types.BitBoard.all
			  .bitAnd(if (ptype != .king) pos.ss.top().checkers else .all)
			  .bitAnd(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

			var src = pos.pieceOcc(misc.types.Piece.fromPtype(stm, ptype));
			while (src != .nil) : (src.popLow()) {
				const s = src.lowSquare();
				var dst = bitboard.ptAtk(ptype, s, occ).bitAnd(target);
				while (dst != .nil) : (dst.popLow()) {
					const d = dst.lowSquare();
					self.append(.{
						.move = Move.gen(.nil, .nil, s, d),
						.score = evaluation.score.draw,
					});
				}
			}

			return self.array.len - cnt;
		}

		pub fn genNoisy(self: *List, pos: Position) usize {
			var cnt: usize = 0;

			cnt += self.genPromotions(pos, .queen,  true);
			cnt += self.genPromotions(pos, .rook,   true);
			cnt += self.genPromotions(pos, .bishop, true);
			cnt += self.genPromotions(pos, .knight, true);

			cnt += self.genPromotions(pos, .queen,  false);
			cnt += self.genPromotions(pos, .knight, false);

			cnt += self.genPtypeMoves(pos, .knight, true);
			cnt += self.genPtypeMoves(pos, .bishop, true);
			cnt += self.genPtypeMoves(pos, .rook,   true);
			cnt += self.genPtypeMoves(pos, .queen,  true);

			return cnt;
		}

		pub fn genQuiet(self: *List, pos: Position) usize {
			var cnt: usize = 0;

			cnt += self.genPromotions(pos, .queen,  false);
			cnt += self.genPromotions(pos, .rook,   false);
			cnt += self.genPromotions(pos, .bishop, false);
			cnt += self.genPromotions(pos, .knight, false);

			cnt += self.genPromotions(pos, .rook,   false);
			cnt += self.genPromotions(pos, .bishop, false);

			cnt += self.genPtypeMoves(pos, .knight, false);
			cnt += self.genPtypeMoves(pos, .bishop, false);
			cnt += self.genPtypeMoves(pos, .rook,   false);
			cnt += self.genPtypeMoves(pos, .queen,  false);

			return cnt;
		}

		pub fn append(self: *List, sm: ScoredMove) void {
			self.array.append(sm)
				catch std.debug.panic("much scored move list no good", .{});
		}

		pub fn get(self: List, i: usize) ScoredMove {
			return self.constSlice()[i];
		}

		pub fn resize(self: *List, len: usize) void {
			self.array.resize(len)
				catch std.debug.panic("much scored move list no good", .{});
		}

		pub fn constSlice(self: *const List) []const ScoredMove {
			return self.slice();
		}

		pub fn slice(self: anytype) switch (@TypeOf(self)) {
			*const List => []const ScoredMove,
			*List => []ScoredMove,
			else => @compileError("unexpected type " ++ @typeName(@TypeOf(self))),
		} {
			return self.array.slice();
		}
	};

	pub fn sortSlice(slice: []ScoredMove) void {
		const desc = struct {
			pub fn inner(_: void, a: ScoredMove, b: ScoredMove) bool {
				return a.score > b.score;
			}
		}.inner;
		std.sort.insertion(ScoredMove, slice, {}, desc);
	}
};

pub const Move = packed struct(u16) {
	flag:	Flag = .nil,
	key:	Flag.Int = 0,
	src:	misc.types.Square = .a1,
	dst:	misc.types.Square = .a1,

	pub const Root = RootMove;
	pub const Scored = ScoredMove;

	pub const Flag = enum(u2) {
		nil,
		en_passant,
		promote,
		castle,

		pub const Int = std.meta.Tag(Flag);
	};

	pub const List = struct {
		array:	std.BoundedArray(Move, capacity) = .{
			.buffer = .{Move {}} ** capacity,
			.len = 0,
		},

		const capacity = 256 - @sizeOf(usize) / @sizeOf(Move);

		pub fn append(self: *List, move: Move) void {
			self.array.append(move)
				catch std.debug.panic("{s} hit the movegen lottery", .{@src().fn_name});
		}
	};

	pub fn gen(comptime flag: Flag, comptime promo: misc.types.Ptype,
	  src: misc.types.Square,
	  dst: misc.types.Square) Move {
		return .{
			.flag = flag,
			.src = src,
			.dst = dst,
			.key = sw: switch (promo) {
				.nil => {
					if (flag == .promote) {
						@compileError("unexpected tag " ++ @tagName(flag));
					}
					break :sw 0;
				},
				.knight, .bishop, .rook, .queen => {
					if (flag != .promote) {
						@compileError("unexpected tag " ++ @tagName(flag));
					}
					break :sw switch (promo) {
						.knight => 0,
						.bishop => 1,
						.rook =>  2,
						.queen => 3,
						else => unreachable,
					};
				},
				else => @compileError("unexpected tag " ++ @tagName(promo)),
			},
		};
	}

	pub fn promotion(self: Move) misc.types.Ptype {
		if (self.flag == .promote) {
			return switch (self.key) {
				0 => .knight,
				1 => .bishop,
				2 => .rook,
				3 => .queen,
			};
		} else return .nil;
	}
};

pub const Picker = struct {
	list:	Move.Scored.List = .{},
	info:	*const search.Info,

	quies:	bool,
	stage:	Stage,

	ttm:	Move,
	killer0:	Move,
	killer1:	Move,

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
		end,

		pub const Int = std.meta.Tag(Stage);

		pub fn int(self: Stage) Int {
			return @intFromEnum(self);
		}

		pub fn inc(self: Stage) Stage {
			return @enumFromInt(self.int() + 1);
		}
	};

	fn scoreNoisy(self: *Picker, move: Move) search.Hist {
		const hist_min = std.math.minInt(search.Hist) / 2;
		const hist_max = -hist_min;

		if (move == self.ttm) {
			return hist_max + 8;
		} else {
			return evaluation.score.draw;
		}
	}

	fn scoreQuiet(self: *Picker, move: Move) search.Hist {
		const hist_min = std.math.minInt(search.Hist) / 2;
		const hist_max = -hist_min;

		if (move == self.ttm) {
			return hist_max + 8;
		} else if (move == self.killer0) {
			return hist_max + 4;
		} else if (move == self.killer1) {
			return hist_max + 2;
		} else {
			return evaluation.score.draw;
		}
	}

	fn pick(self: *Picker) ?Move.Scored {
		while (self.list.index < self.list.array.len) {
			const sm = self.list.array.get(self.list.index);
			self.list.index += 1;

			if (sm.move != self.ttm
			  and sm.move != self.killer0
			  and sm.move != self.killer1) {
				return sm;
			}
		}
		return null;
	}

	pub fn init(info: *search.Info, ttm: Move, killer0: Move, killer1: Move, quies: bool) Picker {
		return .{
			.list = .{},
			.info = info,
			.quies = quies,
			.stage = if (ttm != Move {}) .ttm else .gen_noisy,
			.ttm = ttm,
			.killer0 = killer0,
			.killer1 = killer1,
		};
	}

	pub fn next(self: *Picker) ?Move.Scored {
		if (self.stage == .ttm) {
			self.stage = self.stage.inc();
			if (self.ttm != Move {}) {
				return .{
					.move = self.ttm,
					.score = self.scoreQuiet(self.ttm),
				};
			}
		}

		if (self.stage == .gen_noisy) {
			self.stage = self.stage.inc();
			self.list = .{};
			self.noisy_cnt = self.list.genNoisy(self.info.pos);
			for (self.list.slice()) |*sm| {
				sm.score = self.scoreNoisy(sm.move);
			}
			Move.Scored.sortSlice(self.list.slice());
		}

		while (self.stage == .good_noisy) {
			const sm = self.pick() orelse {
				self.stage = self.stage.inc();
				self.list.resize(self.bad_noisy_cnt);
				self.list.index = self.bad_noisy_cnt;
				break;
			};
			if (sm.score < evaluation.score.draw) {
				self.list.slice()[self.bad_noisy_cnt] = sm;
				self.bad_noisy_cnt += 1;
			} else return sm;
		}

		return null;
	}
};

test {
	try std.testing.expectEqual(@sizeOf(Move) * 256, @sizeOf(Move.Root));
	try std.testing.expectEqual(@sizeOf(Move.Scored) * 256, @sizeOf(Move.Scored.List));
}
