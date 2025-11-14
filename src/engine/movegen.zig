const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const evaluation = @import("evaluation.zig");
const Position = @import("Position.zig");
const search = @import("search.zig");
const uci = @import("uci.zig");

const RootMove = struct {
	line:	bounded_array.BoundedArray(Move, capacity) = .{
		.buffer = .{@as(Move, .{})} ** capacity,
		.len = 0,
	},
	score:	isize = evaluation.score.none,

	pub const List = RootMoveList;

	pub const capacity = 256 - @sizeOf(usize) * 2 / @sizeOf(Move);

	pub fn push(self: *RootMove, m: Move) void {
		self.line.appendAssumeCapacity(m);
	}

	pub fn constSlice(self: *const RootMove) []const Move {
		return self.slice();
	}

	pub fn slice(self: anytype) switch (@TypeOf(self.line.slice())) {
		[]Move, []const Move => |T| T,
		else => |T| @compileError("unexpected type " ++ @typeName(T)),
	} {
		return self.line.slice();
	}

	pub fn sortSlice(s: []RootMove) void {
		const desc = struct {
			fn inner(_: void, a: RootMove, b: RootMove) bool {
				return a.score > b.score;
			}
		}.inner;
		std.sort.insertion(RootMove, s, {}, desc);
	}

	pub fn update(self: *RootMove,
	  score: evaluation.score.Int,
	  move: Move,
	  line: []const Move) void {
		self.score = score;
		self.line.resize(0) catch unreachable;
		self.line.appendAssumeCapacity(move);
		self.line.appendSliceAssumeCapacity(line);
	}
};

const RootMoveList = struct {
	array:	bounded_array.BoundedArray(RootMove, capacity) = .{
		.buffer = .{@as(RootMove, .{})} ** capacity,
		.len = 0,
	},

	const capacity = 256;

	pub fn constSlice(self: *const RootMoveList) []const RootMove {
		return self.slice();
	}

	pub fn slice(self: anytype) switch (@TypeOf(self.array.slice())) {
		[]RootMove, []const RootMove => |T| T,
		else => |T| @compileError("unexpected type " ++ @typeName(T)),
	} {
		return self.array.slice();
	}

	pub fn push(self: *RootMoveList, rm: RootMove) void {
		self.array.appendAssumeCapacity(rm);
	}

	pub fn resize(self: *RootMoveList, len: usize) !void {
		try self.array.resize(len);
	}

	pub fn init(pos: *const Position) RootMoveList {
		const is_drawn = pos.isDrawn();
		const is_terminal = pos.ss.isFull();
		if (is_drawn or is_terminal) {
			@branchHint(.cold);
			return .{};
		}

		var root_moves: RootMoveList = .{};
		var gen_moves: Move.Scored.List = .{};

		_ = gen_moves.genNoisy(pos);
		_ = gen_moves.genQuiet(pos);
		for (gen_moves.constSlice()) |sm| {
			var rm: RootMove = .{};
			defer root_moves.push(rm);

			rm.push(sm.move);
			rm.score = evaluation.score.none;
		}
		return root_moves;
	}
};

const ScoredMove = struct {
	move:	Move = .{},
	score:	std.meta.Int(.signed, @bitSizeOf(Move)) = evaluation.score.none,

	pub const List = ScoredMoveList;

	pub fn sortSlice(slice: []ScoredMove) void {
		const desc = struct {
			fn inner(_: void, a: ScoredMove, b: ScoredMove) bool {
				return a.score > b.score;
			}
		}.inner;
		std.sort.insertion(ScoredMove, slice, {}, desc);
	}
};

const ScoredMoveList = struct {
	array:	bounded_array.BoundedArray(ScoredMove, capacity) = .{
		.buffer = .{@as(ScoredMove, .{})} ** capacity,
		.len = 0,
	},
	index:	usize = 0,

	const capacity = 256 - @sizeOf(usize) * 2 / @sizeOf(ScoredMove);

	fn push(self: *ScoredMoveList, sm: ScoredMove) void {
		self.array.appendAssumeCapacity(sm);
	}

	fn genCastle(self: *ScoredMoveList, pos: *const Position, is_k: bool) usize {
		const len = self.slice().len;
		const stm = pos.stm;
		const occ = pos.bothOcc();

		const cas: types.Castle = switch (stm) {
			.white => if (is_k) .wk else .wq,
			.black => if (is_k) .bk else .bq,
		};
		const info = pos.castles.getPtrConst(cas) orelse return self.slice().len - len;

		if (!pos.ss.top().castle.get(cas)
		  or pos.isChecked()
		  or occ.bwa(info.occ) != .none) {
			return self.slice().len - len;
		}

		var am = info.atk;
		while (am.lowSquare()) |s| : (am.popLow()) {
			const atkers = pos.squareAtkers(s);
			const theirs = pos.colorOcc(stm.flip());
			if (atkers.bwa(theirs) != .none) {
				return self.slice().len - len;
			}
		}

		const s = info.ks;
		const d = info.rs;
		self.push(.{
			.move = .{.flag = .castle, .info = .{.castle = cas}, .src = s, .dst = d},
			.score = evaluation.score.draw,
		});
		return self.slice().len - len;
	}

	fn genEnPas(self: *ScoredMoveList, pos: *const Position) usize {
		const len = self.slice().len;
		const stm = pos.stm;
		const enp = pos.ss.top().en_pas orelse return self.slice().len - len;

		const src = pos.pieceOcc(types.Piece.init(stm, .pawn));
		const dst = enp.toSet();

		const ea = bitboard.pAtkEast(src, stm).bwa(dst);
		if (ea.lowSquare()) |d| {
			const s = d.shift(stm.forward().add(.east).flip(), 1);
			self.push(.{
				.move = .{.flag = .en_passant, .info = .{.en_passant = 0}, .src = s, .dst = d},
				.score = evaluation.score.draw,
			});
		}

		const wa = bitboard.pAtkWest(src, stm).bwa(dst);
		if (wa.lowSquare()) |d| {
			const s = d.shift(stm.forward().add(.west).flip(), 1);
			self.push(.{
				.move = .{.flag = .en_passant, .info = .{.en_passant = 0}, .src = s, .dst = d},
				.score = evaluation.score.draw,
			});
		}

		return self.slice().len - len;
	}

	fn genPawnMoves(self: *ScoredMoveList, pos: *const Position,
	  comptime promo: ?types.Ptype,
	  comptime noisy: bool) usize {
		const is_promote = promo != null;
		const flag: Move.Flag = if (!is_promote) .none else .promote;
		const info: Move.Info = if (!is_promote) .{.none = 0}
		  else .{.promote = Move.Promotion.fromPtype(promo.?)};

		const len = self.slice().len;
		const stm = pos.stm;
		const occ = pos.bothOcc();
		const promotion_bb = stm.promotionRank().toSet();

		const src = pos.pieceOcc(types.Piece.init(stm, .pawn));
		const dst = pos.ss.top().check_mask
		  .bwa(if (is_promote) promotion_bb else promotion_bb.flip())
		  .bwa(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

		if (noisy) {
			var ea = bitboard.pAtkEast(src, stm).bwa(dst);
			while (ea.lowSquare()) |d| : (ea.popLow()) {
				const s = d.shift(stm.forward().add(.east).flip(), 1);
				self.push(.{
					.move = .{.flag = flag, .info = info, .src = s, .dst = d},
					.score = evaluation.score.draw,
				});
			}

			var wa = bitboard.pAtkWest(src, stm).bwa(dst);
			while (wa.lowSquare()) |d| : (wa.popLow()) {
				const s = d.shift(stm.forward().add(.west).flip(), 1);
				self.push(.{
					.move = .{.flag = flag, .info = info, .src = s, .dst = d},
					.score = evaluation.score.draw,
				});
			}
		} else {
			var push1 = bitboard.pPush1(src, occ, stm).bwa(dst);
			while (push1.lowSquare()) |d| : (push1.popLow()) {
				const s = d.shift(stm.forward().flip(), 1);
				self.push(.{
					.move = .{.flag = flag, .info = info, .src = s, .dst = d},
					.score = evaluation.score.draw,
				});
			}

			var push2 = bitboard.pPush2(src, occ, stm).bwa(dst);
			while (push2.lowSquare()) |d| : (push2.popLow()) {
				const s = d.shift(stm.forward().flip(), 2);
				self.push(.{
					.move = .{.flag = flag, .info = info, .src = s, .dst = d},
					.score = evaluation.score.draw,
				});
			}
		}

		return self.slice().len - len;
	}

	fn genPtMoves(self: *ScoredMoveList, pos: *const Position,
	  comptime ptype: types.Ptype,
	  comptime noisy: bool) usize {
		const len = self.slice().len;
		const stm = pos.stm;
		const occ = pos.bothOcc();
		const target = types.Square.Set
		  .full
		  .bwa(if (ptype != .king) pos.ss.top().check_mask else .full)
		  .bwa(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

		var src = pos.pieceOcc(types.Piece.init(stm, ptype));
		while (src.lowSquare()) |s| : (src.popLow()) {
			var dst = bitboard.ptAtk(ptype, s, occ).bwa(target);
			while (dst.lowSquare()) |d| : (dst.popLow()) {
				self.push(.{
					.move = .{.flag = .none, .info = .{.none = 0}, .src = s, .dst = d},
					.score = evaluation.score.draw,
				});
			}
		}

		return self.slice().len - len;
	}

	pub fn resize(self: *ScoredMoveList, n: usize) void {
		self.array.resize(n) catch std.debug.panic("stack overflow", .{});
	}

	pub fn constSlice(self: *const ScoredMoveList) []const ScoredMove {
		return self.slice();
	}

	pub fn slice(self: anytype) switch (@TypeOf(self.array.slice())) {
		[]ScoredMove, []const ScoredMove => |T| T,
		else => |T| @compileError("unexpected type " ++ @typeName(T)),
	} {
		return self.array.slice();
	}

	pub fn genNoisy(self: *ScoredMoveList, pos: *const Position) usize {
		var cnt: usize = 0;

		cnt += self.genPawnMoves(pos, .queen, true);
		cnt += self.genPawnMoves(pos, .rook,  true);
		cnt += self.genPawnMoves(pos, .bishop, true);
		cnt += self.genPawnMoves(pos, .knight, true);

		cnt += self.genPawnMoves(pos, .queen,  false);
		cnt += self.genPawnMoves(pos, .knight, false);

		cnt += self.genPawnMoves(pos, null, true);
		cnt += self.genEnPas(pos);

		cnt += self.genPtMoves(pos, .knight, true);
		cnt += self.genPtMoves(pos, .bishop, true);
		cnt += self.genPtMoves(pos, .rook,  true);
		cnt += self.genPtMoves(pos, .queen, true);
		cnt += self.genPtMoves(pos, .king,  true);

		return cnt;
	}

	pub fn genQuiet(self: *ScoredMoveList, pos: *const Position) usize {
		var cnt: usize = 0;

		cnt += self.genPawnMoves(pos, .rook,   false);
		cnt += self.genPawnMoves(pos, .bishop, false);

		cnt += self.genPawnMoves(pos, null, false);

		cnt += self.genCastle(pos, false);
		cnt += self.genCastle(pos, true);

		cnt += self.genPtMoves(pos, .knight, false);
		cnt += self.genPtMoves(pos, .bishop, false);
		cnt += self.genPtMoves(pos, .rook,  false);
		cnt += self.genPtMoves(pos, .queen, false);
		cnt += self.genPtMoves(pos, .king,  false);

		return cnt;
	}
};

pub const Move = packed struct(u16) {
	flag:	Flag = .none,
	info:	Info = .{.none = 0},
	src:	types.Square = @enumFromInt(0),
	dst:	types.Square = @enumFromInt(0),

	pub const Flag = enum(u2) {
		none,
		en_passant,
		castle,
		promote,
	};

	pub const Promotion = enum(u2) {
		knight,
		bishop,
		rook,
		queen,

		fn fromPtype(p: types.Ptype) Promotion {
			const i = @intFromEnum(p);
			const n = @intFromEnum(types.Ptype.knight);
			return @enumFromInt(i - n);
		}

		pub fn toPtype(self: Promotion) types.Ptype {
			const i = @intFromEnum(self);
			const n = types.Ptype.knight.tag();
			return @enumFromInt(n + i);
		}
	};

	pub const Info = packed union {
		none:		u2,
		en_passant:	u2,
		castle:		types.Castle,
		promote:	Promotion,
	};

	pub const List = struct {
		array:	bounded_array.BoundedArray(Move, capacity) = .{
			.buffer = .{@as(Move, .{})} ** capacity,
			.len = 0,
		},

		const capacity = 256 - @sizeOf(usize) / @sizeOf(Move);

		pub fn push(self: *List, m: Move) void {
			self.array.appendAssumeCapacity(m);
		}

		pub fn constSlice(self: *const List) []const Move {
			return self.slice();
		}

		pub fn slice(self: anytype) switch (@TypeOf(self.array.slice())) {
			[]Move, []const Move => |T| T,
			else => |T| @compileError("unexpected type " ++ @typeName(T)),
		} {
			return self.array.slice();
		}
	};

	pub const Root = RootMove;
	pub const Scored = ScoredMove;

	pub fn isNone(self: Move) bool {
		return self == @as(Move, .{});
	}

	pub fn toString(self: Move, pos: *const Position) [8]u8 {
		var buf: [8]u8 = undefined;

		buf[0] = self.src.file().char();
		buf[1] = self.src.rank().char();
		switch (self.flag) {
			.none, .en_passant, .promote => |f| {
				buf[2] = self.dst.file().char();
				buf[3] = self.dst.rank().char();
				if (f == .promote) {
					buf[4] = self.info.promote.toPtype().char();
				}
			},
			.castle => {
				const castle = pos.castles.getPtrConstAssertContains(self.info.castle);
				const s = if (pos.frc) castle.rs else castle.kd;
				buf[2] = s.file().char();
				buf[3] = s.rank().char();
			},
		}

		return buf;
	}

	pub fn toStringLen(self: Move) usize {
		return if (self.flag == .promote) 5 else 4;
	}
};

pub const Picker = struct {
	list:	Move.Scored.List,
	pos:	*const Position,
	thread:	*const search.Thread,

	skip_quiets:	bool,
	stage:	Stage,

	excluded:	Move,
	ttm:	Move,

	noisy_n:	usize,
	quiet_n:	usize,

	bad_noisy_n:	usize,
	bad_quiet_n:	usize,

	pub const Stage = enum(u8) {
		ttm,
		gen_noisy, good_noisy,
		gen_quiet, good_quiet,
		bad_noisy,
		bad_quiet,
		end,

		const Tag = std.meta.Tag(u8);

		fn inc(self: *Stage) void {
			const i = @intFromEnum(self.*);
			self.* = @enumFromInt(i + 1);
		}

		pub fn isNoisy(self: Stage) bool {
			return self == .good_noisy or self == .bad_noisy;
		}

		pub fn isQuiet(self: Stage) bool {
			return self == .good_quiet or self == .bad_quiet;
		}

		pub fn isGood(self: Stage) bool {
			return self == .good_noisy or self == .good_quiet;
		}

		pub fn isBad(self: Stage) bool {
			return self == .bad_noisy or self == .bad_quiet;
		}
	};

	fn pick(self: *Picker) ?Move.Scored {
		return loop: while (self.list.index < self.list.slice().len) {
			const sm = self.list.slice()[self.list.index];
			const m = sm.move;
			self.list.index += 1;

			if (!m.isNone() and m != self.ttm) {
				break :loop sm;
			}
		} else null;
	}

	fn scoreNoisy(self: *const Picker, move: Move) search.hist.Int {
		return if (move == self.ttm or move == self.excluded) search.hist.min - 1
		  else captures: {
			const sp = self.pos.getSquare(move.src);
			const dp = self.pos.getSquare(move.dst);

			const s = if (sp == .none) evaluation.score.draw else sp.ptype().score() * 7;
			const d = if (dp == .none) evaluation.score.draw else dp.ptype().score() * 7;
			break :captures @intCast(d - s);
		};
	}

	fn scoreQuiet(self: *const Picker, move: Move) search.hist.Int {
		return if (move == self.ttm or move == self.excluded) search.hist.min - 1
		  else self.thread.getQuietHist(move);
	}

	pub fn init(thread: *const search.Thread, ttm: Move) Picker {
		var self: Picker = .{
			.list = .{},
			.pos  = &thread.pos,
			.thread = thread,

			.skip_quiets = false,
			.stage = .gen_noisy,

			.excluded = .{},
			.ttm = .{},

			.noisy_n = 0,
			.quiet_n = 0,

			.bad_noisy_n = 0,
			.bad_quiet_n = 0,
		};

		if (!ttm.isNone() and self.pos.isMovePseudoLegal(ttm)) {
			self.ttm = ttm;
			self.stage = .ttm;
		}

		return self;
	}

	pub fn next(self: *Picker) ?Move.Scored {
		if (self.stage == .ttm) {
			self.stage.inc();
			if (!self.ttm.isNone()) {
				return .{
					.move = self.ttm,
					.score = self.scoreQuiet(self.ttm),
				};
			}
		}

		if (self.stage == .gen_noisy) {
			self.stage.inc();

			self.noisy_n = self.list.genNoisy(self.pos);
			const noisy_slice = self.list.slice()[self.list.index ..][0 .. self.noisy_n];
			for (noisy_slice) |*sm| {
				sm.score = self.scoreNoisy(sm.move);
			}
			Move.Scored.sortSlice(noisy_slice);
		}

		good_noisy_loop: while (self.stage == .good_noisy) {
			const sm = self.pick() orelse {
				self.stage.inc();
				self.list.resize(self.bad_noisy_n);
				self.list.index = self.bad_noisy_n;
				break :good_noisy_loop;
			};
			if (sm.score < evaluation.score.draw) {
				self.list.slice()[self.bad_noisy_n] = sm;
				self.bad_noisy_n += 1;
			} else return sm;
		}

		if (self.stage == .gen_quiet) gen_quiet: {
			self.stage.inc();
			if (self.skip_quiets) {
				break :gen_quiet;
			}

			self.quiet_n = self.list.genQuiet(self.pos);
			const quiet_slice = self.list.slice()[self.list.index ..][0 .. self.quiet_n];
			for (quiet_slice) |*sm| {
				sm.score = self.scoreQuiet(sm.move);
			}
			Move.Scored.sortSlice(quiet_slice);
		}

		good_quiet_loop: while (self.stage == .good_quiet) {
			const picked = self.pick();
			if (self.skip_quiets or picked == null) {
				self.stage.inc();
				self.list.resize(self.bad_noisy_n);
				self.list.index = 0;
				break :good_quiet_loop;
			}

			const sm = picked.?;
			if (sm.score < evaluation.score.draw) {
				self.list.slice()[self.bad_noisy_n + self.bad_quiet_n] = sm;
				self.bad_quiet_n += 1;
			} else return sm;
		}

		if (self.stage == .bad_noisy) bad_noisy: {
			const sm = self.pick() orelse {
				self.stage.inc();
				self.list.resize(self.bad_noisy_n + self.bad_quiet_n);
				self.list.index = self.bad_noisy_n;
				break :bad_noisy;
			};
			return sm;
		}

		if (self.stage == .bad_quiet) bad_quiet: {
			const picked = self.pick();
			if (self.skip_quiets or picked == null) {
				self.stage.inc();
				break :bad_quiet;
			}

			return picked.?;
		}

		return null;
	}

	pub fn skipQuiets(self: *Picker) void {
		self.skip_quiets = true;
	}
};
