const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const evaluation = @import("evaluation.zig");
const Thread = @import("Thread.zig");
const uci = @import("uci.zig");

const RootMove = struct {
    line: bounded_array.BoundedArray(Move, capacity) = .{
        .buffer = .{@as(Move, .{})} ** capacity,
        .len = 0,
    },
    score: isize = evaluation.score.none,

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

    pub fn update(
        self: *RootMove,
        score: evaluation.score.Int,
        move: Move,
        line: []const Move,
    ) void {
        self.score = score;
        self.line.resize(0) catch unreachable;
        self.line.appendAssumeCapacity(move);
        self.line.appendSliceAssumeCapacity(line);
    }
};

const RootMoveList = struct {
    array: bounded_array.BoundedArray(RootMove, capacity) = .{
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

    pub fn init(board: *Board) RootMoveList {
        const is_drawn = board.isDrawn();
        const is_terminal = board.isTerminal();
        if (is_drawn or is_terminal) {
            @branchHint(.cold);
            return .{};
        }

        var root_moves: RootMoveList = .{};
        var gen_moves: Move.Scored.List = .{};

        _ = gen_moves.genNoisy(board.top());
        _ = gen_moves.genQuiet(board.top());
        for (gen_moves.constSlice()) |sm| {
            if (!board.top().isMoveLegal(sm.move)) {
                continue;
            }

            var rm: RootMove = .{};
            defer root_moves.push(rm);

            rm.push(sm.move);
            rm.score = evaluation.score.draw;
        }
        return root_moves;
    }
};

const ScoredMove = struct {
    move: Move = .{},
    score: std.meta.Int(.signed, @bitSizeOf(Move)) = evaluation.score.none,

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
    array: bounded_array.BoundedArray(ScoredMove, capacity) = .{
        .buffer = .{@as(ScoredMove, .{})} ** capacity,
        .len = 0,
    },

    const capacity = 256 - @sizeOf(usize) / @sizeOf(ScoredMove);

    fn push(self: *ScoredMoveList, sm: ScoredMove) void {
        self.array.appendAssumeCapacity(sm);
    }

    fn genCastle(
        self: *ScoredMoveList,
        pos: *const Board.Position,
        comptime flag: Move.Flag,
    ) usize {
        const len = self.slice().len;
        const stm = pos.stm;
        const occ = pos.bothOcc();

        const is_q = switch (flag) {
            .q_castle => true,
            .k_castle => false,
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
        self.push(.{
            .move = .{ .flag = flag, .src = s, .dst = d },
            .score = evaluation.score.draw,
        });
        return self.slice().len - len;
    }

    fn genEnPas(self: *ScoredMoveList, pos: *const Board.Position) usize {
        const len = self.slice().len;
        const stm = pos.stm;
        const enp = pos.en_pas orelse return self.slice().len - len;

        const src = pos.pieceOcc(types.Piece.init(.pawn, stm));
        const dst = enp.toSet();

        const ea = bitboard.pAtkEast(src, stm).bwa(dst);
        if (ea.lowSquare()) |d| {
            const s = d.shift(stm.forward().add(.east).flip(), 1);
            self.push(.{
                .move = .{ .flag = .en_passant, .src = s, .dst = d },
                .score = evaluation.score.draw,
            });
        }

        const wa = bitboard.pAtkWest(src, stm).bwa(dst);
        if (wa.lowSquare()) |d| {
            const s = d.shift(stm.forward().add(.west).flip(), 1);
            self.push(.{
                .move = .{ .flag = .en_passant, .src = s, .dst = d },
                .score = evaluation.score.draw,
            });
        }

        return self.slice().len - len;
    }

    fn genPawnMoves(
        self: *ScoredMoveList,
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
                self.push(.{
                    .move = .{ .flag = if (is_promote) flag else .noisy, .src = s, .dst = d },
                    .score = evaluation.score.draw,
                });
            }

            var wa = bitboard.pAtkWest(src, stm).bwa(dst);
            while (wa.lowSquare()) |d| : (wa.popLow()) {
                const s = d.shift(stm.forward().add(.west).flip(), 1);
                self.push(.{
                    .move = .{ .flag = if (is_promote) flag else .noisy, .src = s, .dst = d },
                    .score = evaluation.score.draw,
                });
            }
        } else {
            var push1 = bitboard.pPush1(src, occ, stm).bwa(dst);
            while (push1.lowSquare()) |d| : (push1.popLow()) {
                const s = d.shift(stm.forward().flip(), 1);
                self.push(.{
                    .move = .{ .flag = if (is_promote) flag else .none, .src = s, .dst = d },
                    .score = evaluation.score.draw,
                });
            }

            var push2 = bitboard.pPush2(src, occ, stm).bwa(dst);
            while (push2.lowSquare()) |d| : (push2.popLow()) {
                const s = d.shift(stm.forward().flip(), 2);
                self.push(.{
                    .move = .{ .flag = if (is_promote) flag else .torped, .src = s, .dst = d },
                    .score = evaluation.score.draw,
                });
            }
        }

        return self.slice().len - len;
    }

    fn genPtMoves(
        self: *ScoredMoveList,
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
                self.push(.{
                    .move = .{ .flag = if (noisy) .noisy else .none, .src = s, .dst = d },
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

    pub fn genNoisy(self: *ScoredMoveList, pos: *const Board.Position) usize {
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

    pub fn genQuiet(self: *ScoredMoveList, pos: *const Board.Position) usize {
        var cnt: usize = 0;

        cnt += self.genPawnMoves(pos, .queen, false);
        cnt += self.genPawnMoves(pos, .rook, false);
        cnt += self.genPawnMoves(pos, .bishop, false);
        cnt += self.genPawnMoves(pos, .knight, false);

        cnt += self.genPawnMoves(pos, null, false);

        cnt += self.genCastle(pos, .q_castle);
        cnt += self.genCastle(pos, .k_castle);

        cnt += self.genPtMoves(pos, .knight, false);
        cnt += self.genPtMoves(pos, .bishop, false);
        cnt += self.genPtMoves(pos, .rook, false);
        cnt += self.genPtMoves(pos, .queen, false);
        cnt += self.genPtMoves(pos, .king, false);

        return cnt;
    }
};

pub const Move = packed struct(u16) {
    flag: Flag = .none,
    src: types.Square = @enumFromInt(0),
    dst: types.Square = @enumFromInt(0),

    pub const Flag = enum(u4) {
        none = 0b0000,
        torped = 0b0001,

        q_castle = 0b0010,
        k_castle = 0b0011,

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
            return self == .q_castle or self == .k_castle;
        }

        pub fn isPromote(self: Flag) bool {
            return self.promoted() != null;
        }

        pub fn isNoisy(self: Flag) bool {
            return self.int() & 0b1000 != 0;
        }

        pub fn isQuiet(self: Flag) bool {
            return self.int() & 0b1000 == 0;
        }

        pub fn castle(self: Flag, c: types.Color) ?types.Castle {
            return switch (self) {
                .q_castle => if (c == .white) .wq else .bq,
                .k_castle => if (c == .white) .wk else .bk,
                else => null,
            };
        }

        pub fn promoted(self: Flag) ?types.Ptype {
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
        array: bounded_array.BoundedArray(Move, capacity) = .{
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
                .white => if (self.flag == .q_castle) .wq else .wk,
                .black => if (self.flag == .q_castle) .bq else .bk,
            };
            const castle = board.bottom().castles.getAssertContains(right);

            const s = if (frc) castle.rs else castle.kd;
            break :castle .{ s.file().char(), s.rank().char() };
        } else .{ self.dst.file().char(), self.dst.rank().char() };
        buf[4] = if (self.flag.promoted()) |pt| pt.char() else buf[4];

        return buf;
    }

    pub fn toStringLen(self: Move) usize {
        return if (self.flag.promoted()) |_| 5 else 4;
    }
};

pub const Picker = struct {
    board: *const Board,
    thread: *const Thread,

    skip_quiets: bool,
    stage: Stage,

    excluded: Move = .{},
    ttm: Move = .{},

    noisy_list: Move.Scored.List = .{},
    quiet_list: Move.Scored.List = .{},

    bad_noisy_list: Move.Scored.List = .{},
    bad_quiet_list: Move.Scored.List = .{},

    pub const Stage = union(Tag) {
        ttm: void,
        gen_noisy: void,
        good_noisy: usize,
        gen_quiet: void,
        good_quiet: usize,
        bad_noisy: usize,
        bad_quiet: usize,

        const Tag = enum {
            ttm,
            gen_noisy,
            good_noisy,
            gen_quiet,
            good_quiet,
            bad_noisy,
            bad_quiet,
        };

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
        const num, const slice = switch (self.stage) {
            .good_noisy => |*n| .{ n, self.noisy_list.slice() },
            .good_quiet => |*n| .{ n, self.quiet_list.slice() },
            .bad_noisy => |*n| .{ n, self.bad_noisy_list.slice() },
            .bad_quiet => |*n| .{ n, self.bad_quiet_list.slice() },
            else => return null,
        };
        const first = if (num.* < slice.len) num.* else return null;
        var best: ?*Move.Scored = null;

        for (slice[first..]) |*sm| {
            best = if (best == null or sm.score > best.?.score) sm else best;
        }

        return if (best) |found| blk: {
            num.* += 1;
            std.mem.swap(Move.Scored, &slice[first], found);

            const sm = slice[first];
            const m = sm.move;
            break :blk if (!m.isNone() and m != self.ttm and m != self.excluded) sm else special: {
                @branchHint(.unlikely);
                break :special self.pick();
            };
        } else null;
    }

    fn scoreNoisy(self: *const Picker, move: Move) Thread.hist.Int {
        return if (move == self.ttm or move == self.excluded) evaluation.score.mate else blk: {
            const mvv = if (move.flag == .en_passant)
                params.values.see_ordering_pawn
            else switch (self.board.top().getSquare(move.dst).ptype()) {
                .king => std.debug.panic("found king capture", .{}),
                inline else => |e| @field(params.values, "see_ordering_" ++ @tagName(e)),
            };

            const hist = self.thread.getNoisyHist(move);
            break :blk @intCast(@divTrunc(mvv * 7 + hist, 2));
        };
    }

    fn scoreQuiet(self: *const Picker, move: Move) Thread.hist.Int {
        return if (move == self.ttm or move == self.excluded) evaluation.score.mate else blk: {
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
        var mp: Picker = .{
            .board = &thread.board,
            .thread = thread,

            .skip_quiets = false,
            .stage = .gen_noisy,
        };

        const pos = mp.board.top();
        if (!ttm.isNone() and pos.isMovePseudoLegal(ttm)) {
            mp.ttm = ttm;
            mp.stage = .ttm;
        }

        return mp;
    }

    pub fn next(self: *Picker) ?Move.Scored {
        if (self.stage == .ttm) {
            self.stage = .gen_noisy;
            if (!self.ttm.isNone()) {
                return .{
                    .move = self.ttm,
                    .score = self.scoreQuiet(self.ttm),
                };
            }
        }

        if (self.stage == .gen_noisy) {
            self.stage = .{ .good_noisy = 0 };
            _ = self.noisy_list.genNoisy(self.board.top());

            const slice = self.noisy_list.slice();
            for (slice) |*sm| {
                sm.score = self.scoreNoisy(sm.move);
            }
        }

        good_noisy_loop: while (self.stage == .good_noisy) {
            const sm = self.pick() orelse {
                self.stage = .gen_quiet;
                break :good_noisy_loop;
            };
            if (sm.score < evaluation.score.draw) {
                self.bad_noisy_list.push(sm);
                continue;
            }

            return sm;
        }

        if (self.stage == .gen_quiet) gen_quiet: {
            self.stage = .{ .good_quiet = 0 };
            if (self.skip_quiets) {
                break :gen_quiet;
            }

            _ = self.quiet_list.genQuiet(self.board.top());
            const slice = self.quiet_list.slice();
            for (slice) |*sm| {
                sm.score = self.scoreQuiet(sm.move);
            }
        }

        good_quiet_loop: while (self.stage == .good_quiet) {
            const picked = self.pick();
            if (self.skip_quiets or picked == null) {
                self.stage = .{ .bad_noisy = 0 };
                break :good_quiet_loop;
            }

            const sm = picked.?;
            if (sm.score < evaluation.score.draw) {
                self.bad_quiet_list.push(sm);
                continue;
            }

            return sm;
        }

        if (self.stage == .bad_noisy) bad_noisy: {
            const sm = self.pick() orelse {
                self.stage = .{ .bad_quiet = 0 };
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
