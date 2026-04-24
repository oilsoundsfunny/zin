const bitboard = @import("bitboard");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const evaluation = @import("evaluation.zig");
const Thread = @import("Thread.zig");
const uci = @import("uci.zig");

pub const RootMove = struct {
    line: types.BoundedArray(Move, null, capacity) = .{},
    score: isize = evaluation.score.none,
    nodes: usize = 0,

    pub const List = struct {
        array: types.BoundedArray(RootMove, null, capacity) = .{
            .buffer = .{@as(RootMove, .{})} ** capacity,
            .len = 0,
        },

        pub fn constSlice(self: *const List) []const RootMove {
            return self.slice();
        }

        pub fn slice(self: anytype) switch (@TypeOf(self.array.slice())) {
            []RootMove, []const RootMove => |T| T,
            else => |T| @compileError("unexpected type " ++ @typeName(T)),
        } {
            return self.array.slice();
        }

        pub fn resize(self: *List, len: usize) !void {
            try self.array.resize(len);
        }

        pub fn find(self: anytype, m: Move) ?types.SameMutPtr(@TypeOf(self), *List, *RootMove) {
            return loop: for (self.slice()) |*rm| {
                if (rm.constSlice()[0] == m) {
                    break :loop rm;
                }
            } else null;
        }

        pub fn init(board: *Board) List {
            const pos = board.positions.last();
            var root_moves: List = .{};
            var gen_moves: Move.List = .{};

            _ = gen_moves.genNoisy(pos);
            _ = gen_moves.genQuiet(pos);
            for (gen_moves.constSlice()) |m| {
                if (!pos.isMoveLegal(m)) {
                    continue;
                }

                var rm: RootMove = .{};
                defer root_moves.array.pushUnchecked(rm);

                rm.line.pushUnchecked(m);
                rm.score = evaluation.score.draw;
            }
            return root_moves;
        }
    };

    pub const capacity = 256 - @sizeOf(usize) * 3 / @sizeOf(Move);

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
        std.sort.pdq(RootMove, s, {}, desc);
    }

    pub fn update(
        self: *RootMove,
        score: evaluation.score.Int,
        move: Move,
        line: []const Move,
    ) void {
        self.score = score;
        self.line.resize(0) catch unreachable;
        self.line.pushUnchecked(move);
        self.line.pushSliceUnchecked(line);
    }
};

pub const Move = packed struct(u16) {
    flag: Flag = .none,
    src: types.Square = @enumFromInt(0),
    dst: types.Square = @enumFromInt(0),

    pub const Flag = enum(u4) {
        none = 0b0000,
        torped = 0b0001,

        castle_k = 0b0010,
        castle_q = 0b0011,

        promote_n = 0b0100,
        promote_b = 0b0101,
        promote_r = 0b0110,
        promote_q = 0b0111,

        noisy = 0b1000,
        en_passant = 0b1001,

        noisy_promote_n = 0b1100,
        noisy_promote_b = 0b1101,
        noisy_promote_r = 0b1110,
        noisy_promote_q = 0b1111,

        fn int(self: Flag) std.meta.Tag(Flag) {
            return @intFromEnum(self);
        }

        pub fn isCastle(self: Flag) bool {
            return self == .castle_q or self == .castle_k;
        }

        pub fn isPromote(self: Flag) bool {
            return self.promotion() != null;
        }

        pub fn isNoisy(self: Flag) bool {
            return self.int() & 0b1000 != 0;
        }

        pub fn isQuiet(self: Flag) bool {
            return self.int() & 0b1000 == 0;
        }

        pub fn castle(self: Flag, c: types.Color) ?types.Castle {
            return switch (self) {
                .castle_q => if (c == .white) .wq else .bq,
                .castle_k => if (c == .white) .wk else .bk,
                else => null,
            };
        }

        pub fn promotion(self: Flag) ?types.Ptype {
            return switch (self) {
                .promote_n, .noisy_promote_n => .knight,
                .promote_b, .noisy_promote_b => .bishop,
                .promote_r, .noisy_promote_r => .rook,
                .promote_q, .noisy_promote_q => .queen,
                else => null,
            };
        }
    };

    pub const List = struct {
        array: types.BoundedArray(Move, null, capacity) = .{
            .buffer = .{@as(Move, .{})} ** capacity,
            .len = 0,
        },

        pub const capacity = 256 - @sizeOf(usize) / @sizeOf(Move);

        fn genCastle(self: *List, pos: *const Board.Position, comptime flag: Move.Flag) usize {
            const len = self.slice().len;
            const stm = pos.stm;
            const occ = pos.bothOcc();

            const is_q = switch (flag) {
                .castle_q => true,
                .castle_k => false,
                else => @compileError("unexpected enum tag " ++ @tagName(flag)),
            };
            const right: types.Castle = switch (stm) {
                .white => if (is_q) .wq else .wk,
                .black => if (is_q) .bq else .bk,
            };
            const castle = pos.castles.get(right) orelse return self.slice().len - len;

            if (pos.isChecked() or occ.bwa(castle.occ) != .none) {
                return self.slice().len - len;
            }

            var am = castle.atk;
            while (am.lowSquare()) |s| : (am.popLow()) {
                const atkers = pos.squareAtkers(s);
                const theirs = pos.colorOcc(stm.flip());
                if (atkers.bwa(theirs) != .none) {
                    return self.slice().len - len;
                }
            }

            const s = castle.ks;
            const d = castle.rs;
            self.array.pushUnchecked(.{ .flag = flag, .src = s, .dst = d });
            return self.slice().len - len;
        }

        fn genEnPas(self: *List, pos: *const Board.Position) usize {
            const len = self.slice().len;
            const stm = pos.stm;
            const enp = pos.en_pas orelse return self.slice().len - len;

            const src = pos.pieceOcc(types.Piece.init(.pawn, stm));
            const dst = enp.toSet();

            const ea = bitboard.pAtkEast(src, stm).bwa(dst);
            if (ea.lowSquare()) |d| {
                const s = d.shift(stm.forward().add(.east).flip(), 1);
                self.array.pushUnchecked(.{ .flag = .en_passant, .src = s, .dst = d });
            }

            const wa = bitboard.pAtkWest(src, stm).bwa(dst);
            if (wa.lowSquare()) |d| {
                const s = d.shift(stm.forward().add(.west).flip(), 1);
                self.array.pushUnchecked(.{ .flag = .en_passant, .src = s, .dst = d });
            }

            return self.slice().len - len;
        }

        fn genPawnMoves(
            self: *List,
            pos: *const Board.Position,
            comptime promo: ?types.Ptype,
            comptime noisy: bool,
        ) usize {
            const flag: Move.Flag = if (promo) |p|
                switch (p) {
                    .knight => if (noisy) .noisy_promote_n else .promote_n,
                    .bishop => if (noisy) .noisy_promote_b else .promote_b,
                    .rook => if (noisy) .noisy_promote_r else .promote_r,
                    .queen => if (noisy) .noisy_promote_q else .promote_q,
                    else => @compileError("unexpected enum tag " ++ @tagName(p)),
                }
            else
                .none;
            const is_promote = flag.isPromote();

            const len = self.slice().len;
            const stm = pos.stm;
            const occ = pos.bothOcc();
            const promotion_bb = stm.promotionRank().toSet();

            const src = pos.pieceOcc(types.Piece.init(.pawn, stm));
            const dst = pos.checks
                .bwa(if (is_promote) promotion_bb else promotion_bb.flip())
                .bwa(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

            if (noisy) {
                var ea = bitboard.pAtkEast(src, stm).bwa(dst);
                while (ea.lowSquare()) |d| : (ea.popLow()) {
                    const s = d.shift(stm.forward().add(.east).flip(), 1);
                    self.array.pushUnchecked(.{
                        .flag = if (is_promote) flag else .noisy,
                        .src = s,
                        .dst = d,
                    });
                }

                var wa = bitboard.pAtkWest(src, stm).bwa(dst);
                while (wa.lowSquare()) |d| : (wa.popLow()) {
                    const s = d.shift(stm.forward().add(.west).flip(), 1);
                    self.array.pushUnchecked(.{
                        .flag = if (is_promote) flag else .noisy,
                        .src = s,
                        .dst = d,
                    });
                }
            } else {
                var push1 = bitboard.pPush1(src, occ, stm).bwa(dst);
                while (push1.lowSquare()) |d| : (push1.popLow()) {
                    const s = d.shift(stm.forward().flip(), 1);
                    self.array.pushUnchecked(.{
                        .flag = if (is_promote) flag else .none,
                        .src = s,
                        .dst = d,
                    });
                }

                var push2 = bitboard.pPush2(src, occ, stm).bwa(dst);
                while (push2.lowSquare()) |d| : (push2.popLow()) {
                    const s = d.shift(stm.forward().flip(), 2);
                    self.array.pushUnchecked(.{
                        .flag = if (is_promote) flag else .torped,
                        .src = s,
                        .dst = d,
                    });
                }
            }

            return self.slice().len - len;
        }

        fn genPtMoves(
            self: *List,
            pos: *const Board.Position,
            comptime ptype: types.Ptype,
            comptime noisy: bool,
        ) usize {
            const len = self.slice().len;
            const stm = pos.stm;
            const occ = pos.bothOcc();
            const target = types.Square.Set
                .full
                .bwa(if (ptype != .king) pos.checks else .full)
                .bwa(if (noisy) pos.colorOcc(stm.flip()) else occ.flip());

            var src = pos.pieceOcc(types.Piece.init(ptype, stm));
            while (src.lowSquare()) |s| : (src.popLow()) {
                var dst = bitboard.ptAtk(ptype, s, occ).bwa(target);
                while (dst.lowSquare()) |d| : (dst.popLow()) {
                    self.array.pushUnchecked(.{
                        .flag = if (noisy) .noisy else .none,
                        .src = s,
                        .dst = d,
                    });
                }
            }

            return self.slice().len - len;
        }

        pub fn genNoisy(self: *List, pos: *const Board.Position) usize {
            var cnt: usize = 0;

            cnt += self.genPawnMoves(pos, .queen, true);
            cnt += self.genPawnMoves(pos, .rook, true);
            cnt += self.genPawnMoves(pos, .bishop, true);
            cnt += self.genPawnMoves(pos, .knight, true);

            cnt += self.genPawnMoves(pos, null, true);
            cnt += self.genEnPas(pos);

            cnt += self.genPtMoves(pos, .knight, true);
            cnt += self.genPtMoves(pos, .bishop, true);
            cnt += self.genPtMoves(pos, .rook, true);
            cnt += self.genPtMoves(pos, .queen, true);
            cnt += self.genPtMoves(pos, .king, true);

            return cnt;
        }

        pub fn genQuiet(self: *List, pos: *const Board.Position) usize {
            var cnt: usize = 0;

            cnt += self.genPawnMoves(pos, .queen, false);
            cnt += self.genPawnMoves(pos, .rook, false);
            cnt += self.genPawnMoves(pos, .bishop, false);
            cnt += self.genPawnMoves(pos, .knight, false);

            cnt += self.genPawnMoves(pos, null, false);

            cnt += self.genCastle(pos, .castle_q);
            cnt += self.genCastle(pos, .castle_k);

            cnt += self.genPtMoves(pos, .knight, false);
            cnt += self.genPtMoves(pos, .bishop, false);
            cnt += self.genPtMoves(pos, .rook, false);
            cnt += self.genPtMoves(pos, .queen, false);
            cnt += self.genPtMoves(pos, .king, false);

            return cnt;
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

        pub fn resize(self: *List, n: usize) void {
            self.array.resize(n) catch std.debug.panic("stack overflow", .{});
        }
    };

    pub const Root = RootMove;

    pub const Scored = packed struct(u32) {
        move: Move = .{},
        score: evaluation.score.Small = evaluation.score.none,
    };

    pub fn isNone(self: Move) bool {
        return self == @as(Move, .{});
    }

    pub fn toString(self: Move, board: *const Board) [8]u8 {
        var buf: [8]u8 = undefined;

        buf[0], buf[1] = .{ self.src.file().char(), self.src.rank().char() };
        buf[2], buf[3] = if (self.flag.isCastle()) castle: {
            const frc = board.frc;
            const stm: types.Color = switch (self.src.rank()) {
                .rank_1 => .white,
                .rank_8 => .black,
                else => std.debug.panic("invalid castle rank", .{}),
            };

            const right: types.Castle = switch (stm) {
                .white => if (self.flag == .castle_q) .wq else .wk,
                .black => if (self.flag == .castle_q) .bq else .bk,
            };
            const castle = board.positions.last().castles.getAssertContains(right);

            const s = if (frc) castle.rs else castle.kd;
            break :castle .{ s.file().char(), s.rank().char() };
        } else .{ self.dst.file().char(), self.dst.rank().char() };
        buf[4] = if (self.flag.promotion()) |pt| pt.char() else buf[4];

        return buf;
    }

    pub fn toStringLen(self: Move) usize {
        return if (self.flag.promotion()) |_| 5 else 4;
    }
};

pub const Picker = struct {
    board: *const Board,
    thread: *const Thread,

    excluded: Move,
    ttm: Move = .{},

    skip_quiets: bool = false,
    stage: Stage = .gen_noisy,

    moves: Move.List = .{},
    scores: evaluation.score.List = .{},

    first: usize = 0,
    last: usize = 0,
    bad_noisy_n: usize = 0,
    bad_quiet_n: usize = 0,

    pub const Stage = enum {
        ttm,
        gen_noisy,
        good_noisy,
        gen_quiet,
        good_quiet,
        bad_noisy,
        bad_quiet,

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

    fn shouldSkip(self: *const Picker, m: Move) bool {
        return m == self.ttm or m == self.excluded;
    }

    fn pick(self: *Picker) ?Move.Scored {
        const len = if (self.last > self.first) self.last - self.first else return null;
        const moves = self.moves.array.buffer[self.first..][0..len];
        const scores = self.scores.array.buffer[self.first..][0..len];

        const simd_len = evaluation.score.simd_len;
        var i: u32 = 0;
        var indices = std.simd.iota(u32, simd_len);
        var bests: @TypeOf(indices) = @splat(0);

        while (i + simd_len < scores.len) : ({
            i += simd_len;
            indices +%= @splat(simd_len);
        }) {
            const rhs = evaluation.score.withIndices(scores[i..][0..simd_len].*, indices);
            bests = @max(bests, rhs);
        }

        var best = @reduce(.Max, bests);
        while (i < scores.len) : (i += 1) {
            best = @max(best, evaluation.score.withIndex(scores[i], i));
        }

        const best_i = best % 256;
        std.mem.swap(Move, &moves[0], &moves[best_i]);
        std.mem.swap(evaluation.score.Int, &scores[0], &scores[best_i]);

        self.first += 1;
        return if (self.shouldSkip(moves[0])) blk: {
            @branchHint(.cold);
            break :blk self.pick();
        } else .{ .move = moves[0], .score = @intCast(scores[0]) };
    }

    fn scoreNoisy(self: *const Picker, move: Move) Thread.hist.Int {
        return if (self.shouldSkip(move)) evaluation.score.mate else blk: {
            const mvv = if (move.flag == .en_passant)
                params.values.see_ordering_pawn
            else switch (self.board.positions.last().getSq(move.dst).ptype()) {
                .pawn => params.values.see_ordering_pawn,
                .knight => params.values.see_ordering_knight,
                .bishop => params.values.see_ordering_bishop,
                .rook => params.values.see_ordering_rook,
                .queen => params.values.see_ordering_queen,
                .king => std.debug.panic("found king capture", .{}),
            };

            const hist = self.thread.getNoisyHist(move);
            break :blk @intCast(@divTrunc(mvv * 7 + hist, 2));
        };
    }

    fn scoreQuiet(self: *const Picker, move: Move) Thread.hist.Int {
        return if (self.shouldSkip(move)) evaluation.score.mate else blk: {
            const score = @as(evaluation.score.Int, self.thread.getQuietHist(move)) +
                @as(evaluation.score.Int, self.thread.getContHist(move, 1)) * 2 +
                @as(evaluation.score.Int, self.thread.getContHist(move, 2)) +
                @as(evaluation.score.Int, self.thread.getContHist(move, 4)) +
                @as(evaluation.score.Int, self.thread.getContHist(move, 6));
            const scaled = @divTrunc(score, 6);
            break :blk @intCast(scaled);
        };
    }

    pub fn init(thread: *const Thread, ttm: Move) Picker {
        const pos = thread.board.positions.last();
        var mp: Picker = .{
            .board = &thread.board,
            .thread = thread,

            .excluded = pos.excluded,
        };

        const is_excluded = !ttm.isNone() and ttm == mp.excluded;
        const is_legal = !ttm.isNone() and pos.isMovePseudoLegal(ttm) and pos.isMoveLegal(ttm);
        if (is_excluded or is_legal) {
            mp.ttm = ttm;
            mp.stage = if (!is_excluded) .ttm else .gen_noisy;
        }

        return mp;
    }

    pub fn next(self: *Picker) ?Move.Scored {
        if (self.stage == .ttm) {
            self.stage = .gen_noisy;

            if (!self.ttm.isNone()) {
                std.debug.assert(self.ttm != self.excluded);
                return .{
                    .move = self.ttm,
                    .score = self.scoreQuiet(self.ttm),
                };
            }
        }

        if (self.stage == .gen_noisy) {
            self.stage = .good_noisy;
            self.first = 0;
            self.last += self.moves.genNoisy(self.board.positions.last());

            const len = self.last - self.first;
            const moves = self.moves.constSlice()[0..len];
            const scores = self.scores.array.addManyUnchecked(len);

            for (moves, scores) |m, *s| {
                s.* = self.scoreNoisy(m);
            }
        }

        good_noisy_loop: while (self.stage == .good_noisy) {
            const sm = self.pick() orelse {
                self.stage = .gen_quiet;
                break :good_noisy_loop;
            };

            if (sm.score < evaluation.score.draw) {
                self.moves.array.buffer[self.bad_noisy_n] = sm.move;
                self.scores.array.buffer[self.bad_noisy_n] = sm.score;
                self.bad_noisy_n += 1;
                continue :good_noisy_loop;
            }

            return sm;
        }

        if (self.stage == .gen_quiet) gen_quiet: {
            self.stage = .good_quiet;
            self.first = self.last;
            self.last += if (!self.skip_quiets)
                self.moves.genQuiet(self.board.positions.last())
            else
                break :gen_quiet;

            const len = self.last - self.first;
            const moves = self.moves.constSlice()[self.first..][0..len];
            const scores = self.scores.array.addManyUnchecked(len);

            for (moves, scores) |m, *s| {
                s.* = self.scoreQuiet(m);
            }
        }

        good_quiet_loop: while (self.stage == .good_quiet) {
            const picked = self.pick();
            if (self.skip_quiets or picked == null) {
                self.stage = .bad_noisy;
                self.first = 0;
                self.last = self.bad_noisy_n;
                break :good_quiet_loop;
            }

            const sm = picked.?;
            if (sm.score < evaluation.score.draw) {
                self.moves.array.buffer[self.bad_noisy_n + self.bad_quiet_n] = sm.move;
                self.scores.array.buffer[self.bad_noisy_n + self.bad_quiet_n] = sm.score;
                self.bad_quiet_n += 1;
                continue :good_quiet_loop;
            }

            return sm;
        }

        if (self.stage == .bad_noisy) bad_noisy: {
            const sm = self.pick() orelse {
                self.stage = .bad_quiet;
                self.first = self.bad_noisy_n;
                self.last += self.bad_quiet_n;
                break :bad_noisy;
            };
            return sm;
        }

        return self.pick();
    }

    pub fn skipQuiets(self: *Picker) void {
        self.skip_quiets = true;
    }
};

comptime {
    std.debug.assert(@sizeOf(RootMove) == @sizeOf(Move) * 256);
}
