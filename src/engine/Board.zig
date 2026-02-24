const bitboard = @import("bitboard");
const builtin = @import("builtin");
const nnue = @import("nnue");
const params = @import("params");
const root = @import("root");
const std = @import("std");
const types = @import("types");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const Thread = @import("Thread.zig");
const zobrist = @import("zobrist.zig");

const Board = @This();

frc: bool = false,
finny_table: nnue.FinnyTable = .{},
perspectives: types.BoundedArray(nnue.Accumulator.Perspective, null, 1024) = .{
    .buffer = @splat(.{}),
    .len = 1,
},
positions: types.BoundedArray(Position, null, 1024) = .{ .buffer = @splat(.{}), .len = 1 },

pub const FenError = error{
    InvalidPiece,
    InvalidSquare,
    InvalidSideToMove,
    InvalidCastle,
    InvalidEnPassant,
    InvalidPlyClock,
    InvalidMoveClock,
    InvalidFen,
};

pub const MoveError = error{
    InvalidMove,
};

pub const Castle = struct {
    atk: types.Square.Set,
    occ: types.Square.Set,

    ks: types.Square,
    kd: types.Square,

    rs: types.Square,
    rd: types.Square,

    fn init(ks: types.Square, kd: types.Square, rs: types.Square, rd: types.Square) Castle {
        const kb = bitboard.rays.rRayIncl(ks, kd);
        const rb = bitboard.rays.rRayIncl(rs, rd);

        var occ = kb.bwo(rb);
        occ.pop(ks);
        occ.pop(rs);

        return .{ .ks = ks, .kd = kd, .rs = rs, .rd = rd, .atk = kb, .occ = occ };
    }
};

pub const Position = struct {
    by_color: std.EnumArray(types.Color, types.Square.Set) = .initFill(.none),
    by_ptype: std.EnumArray(types.Ptype, types.Square.Set) = .initFill(.none),
    by_square: std.EnumArray(types.Square, types.Piece) = .initFill(.none),
    castles: std.EnumMap(types.Castle, Castle) = .init(.{}),

    stm: types.Color = .white,
    move: movegen.Move = .{},
    src_piece: types.Piece = .none,
    dst_piece: types.Piece = .none,

    checks: types.Square.Set = .full,
    en_pas: ?types.Square = null,
    rule50: u8 = 0,

    key: zobrist.Int = 0,
    pawn_key: zobrist.Int = 0,
    minor_key: zobrist.Int = 0,
    major_key: zobrist.Int = 0,
    nonpawn_keys: std.EnumArray(types.Color, zobrist.Int) = .initFill(0),

    corr_eval: evaluation.score.Int = evaluation.score.none,
    stat_eval: evaluation.score.Int = evaluation.score.none,
    pv: movegen.Move.Root = .{},

    pub const startpos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
    pub const kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";

    fn colorOccPtr(self: *Position, c: types.Color) *types.Square.Set {
        return self.by_color.getPtr(c);
    }

    fn ptypeOccPtr(self: *Position, c: types.Ptype) *types.Square.Set {
        return self.by_ptype.getPtr(c);
    }

    fn colorOccPtrConst(self: *const Position, c: types.Color) *const types.Square.Set {
        return self.by_color.getPtrConst(c);
    }

    fn ptypeOccPtrConst(self: *const Position, c: types.Ptype) *const types.Square.Set {
        return self.by_ptype.getPtrConst(c);
    }

    fn popSq(self: *Position, s: types.Square, p: types.Piece) void {
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
        switch (t) {
            .pawn => self.pawn_key ^= z,
            .knight, .bishop => {
                self.minor_key ^= z;
                self.nonpawn_keys.getPtr(c).* ^= z;
            },
            .rook, .queen => {
                self.major_key ^= z;
                self.nonpawn_keys.getPtr(c).* ^= z;
            },
            .king => {
                self.minor_key ^= z;
                self.major_key ^= z;
                self.nonpawn_keys.getPtr(c).* ^= z;
            },
        }
    }

    fn setSq(self: *Position, s: types.Square, p: types.Piece) void {
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
        switch (t) {
            .pawn => self.pawn_key ^= z,
            .knight, .bishop => {
                self.minor_key ^= z;
                self.nonpawn_keys.getPtr(c).* ^= z;
            },
            .rook, .queen => {
                self.major_key ^= z;
                self.nonpawn_keys.getPtr(c).* ^= z;
            },
            .king => {
                self.minor_key ^= z;
                self.major_key ^= z;
                self.nonpawn_keys.getPtr(c).* ^= z;
            },
        }
    }

    fn popCastle(self: *Position, c: types.Castle) void {
        if (self.castles.fetchRemove(c)) |_| {
            self.key ^= zobrist.cas(c);
        }
    }

    fn setCastle(self: *Position, c: types.Castle, info: Castle) void {
        if (self.castles.fetchPut(c, info)) |_| {} else {
            self.key ^= zobrist.cas(c);
        }
    }

    fn genCheckMask(self: *const Position) types.Square.Set {
        const occ = self.bothOcc();
        const stm = self.stm;

        const kb = self.pieceOcc(types.Piece.init(.king, stm));
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

    fn parseFen(self: *Position, fen: []const u8) FenError!void {
        var tokens = std.mem.tokenizeAny(u8, fen, &std.ascii.whitespace);
        for (0..6) |_| {
            if (tokens.next() == null) {
                return error.InvalidFen;
            }
        }

        tokens.reset();
        return self.parseFenTokens(&tokens);
    }

    fn parseFenTokens(self: *Position, tokens: *std.mem.TokenIterator(u8, .any)) FenError!void {
        const backup = self.*;
        self.* = .{};
        errdefer self.* = backup;

        const sa = [types.Square.num]types.Square{
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

                break :blk sw: switch (p) {
                    .w_rook => {
                        const is_home = s.rank() == types.Color.white.homeRank();
                        if (is_home and kings.contains(.white)) {
                            rooks.put(.wk, s);
                        } else if (is_home and !rooks.contains(.wq)) {
                            rooks.put(.wq, s);
                        }
                        break :sw 1;
                    },
                    .w_king => if (kings.fetchPut(.white, s)) |_| return error.InvalidPiece else 1,

                    .b_rook => {
                        const is_home = s.rank() == types.Color.black.homeRank();
                        if (is_home and kings.contains(.black)) {
                            rooks.put(.bk, s);
                        } else if (is_home and !rooks.contains(.bq)) {
                            rooks.put(.bq, s);
                        }
                        break :sw 1;
                    },
                    .b_king => if (kings.fetchPut(.black, s)) |_| return error.InvalidPiece else 1,

                    else => 1,
                };
            } else switch (c) {
                '1'...'8' => c - '0',
                '/' => 0,
                else => return error.InvalidPiece,
            };

            if (si > types.Square.num) {
                return error.InvalidSquare;
            }
            if (si < types.Square.num and sa[si].rank() != s.rank() and sa[si].file() != .file_a) {
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

            const right = types.Castle.fromChar(c) orelse frc: {
                const is_lower = std.ascii.isLower(c);
                const to_lower = std.ascii.toLower(c);
                const color: types.Color = if (is_lower) .black else .white;

                const ks = kings.get(color) orelse return error.InvalidFen;
                if (ks.rank() != color.homeRank()) {
                    return error.InvalidCastle;
                }

                const kf = ks.file();
                const rf = types.File.fromChar(to_lower) orelse return error.InvalidCastle;

                const kfi: i8 = kf.int();
                const rfi: i8 = rf.int();
                const diff = rfi - kfi;
                const west = types.Direction.west.int();
                const is_q = diff * west > 0;

                break :frc switch (color) {
                    .black => if (is_q) types.Castle.bq else types.Castle.bk,
                    .white => if (is_q) types.Castle.wq else types.Castle.wk,
                };
            };
            if (self.castles.contains(right)) {
                return error.InvalidCastle;
            }

            const ks = kings.getAssertContains(right.color());
            const rs = rooks.getAssertContains(right);

            const is_q = right.ptype() == .queen;
            const kd = types.Square.init(right.color().homeRank(), if (is_q) .file_c else .file_g);
            const rd = types.Square.init(right.color().homeRank(), if (is_q) .file_d else .file_f);

            self.setCastle(right, .init(ks, kd, rs, rd));
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
        self.rule50 = std.fmt.parseUnsigned(u8, ply_token, 10) catch return error.InvalidPlyClock;

        const move_token = tokens.next() orelse return error.InvalidFen;
        _ = std.fmt.parseUnsigned(usize, move_token, 10) catch return error.InvalidMoveClock;

        self.checks = self.genCheckMask();
        self.key ^= zobrist.enp(self.en_pas);
    }

    fn tryMove(self: *const Position, move: movegen.Move) MoveError!Position {
        var pos = self.*;
        const stm = pos.stm;
        const s = move.src;
        const d = move.dst;
        const sp = pos.getSquare(s);
        const dp = pos.getSquare(d);

        switch (move.flag) {
            .none, .torped, .promote_n, .promote_b, .promote_r, .promote_q => |f| {
                const add_p = types.Piece.init(f.promotion() orelse sp.ptype(), stm);
                pos.popSq(s, sp);
                pos.setSq(d, add_p);
            },

            .castle_q, .castle_k => |f| {
                const right = f.castle(stm) orelse unreachable;
                const castle = pos.castles.getAssertContains(right);

                const rook = types.Piece.init(.rook, stm);
                const king = types.Piece.init(.king, stm);

                pos.popSq(castle.ks, king);
                pos.popSq(castle.rs, rook);

                pos.setSq(castle.kd, king);
                pos.setSq(castle.rd, rook);
            },

            else => |f| {
                const add_p = types.Piece.init(f.promotion() orelse sp.ptype(), stm);
                const del_p, const del_s = if (f == .en_passant)
                    .{ types.Piece.init(.pawn, stm.flip()), d.shift(stm.forward().flip(), 1) }
                else
                    .{ dp, d };

                pos.popSq(del_s, del_p);
                pos.setSq(d, add_p);
                pos.popSq(s, sp);
            },
        }

        const king = types.Piece.init(.king, stm);
        const kb = pos.pieceOcc(king);
        const ks = kb.lowSquare() orelse return error.InvalidMove;

        const atkers = pos.squareAtkers(ks);
        const them = pos.colorOcc(stm.flip());
        return if (atkers.bwa(them) == .none) pos else error.InvalidMove;
    }

    pub fn before(
        self: anytype,
        dist: usize,
    ) types.SameMutPtr(@TypeOf(self), *Position, *Position) {
        return &(self[0..1].ptr - dist)[0];
    }

    pub fn after(
        self: anytype,
        dist: usize,
    ) types.SameMutPtr(@TypeOf(self), *Position, *Position) {
        return &(self[0..1].ptr + dist)[0];
    }

    pub fn bothOcc(self: *const Position) types.Square.Set {
        const wo = self.colorOcc(.white);
        const bo = self.colorOcc(.black);
        return @TypeOf(wo, bo).bwo(wo, bo);
    }

    pub fn colorOcc(self: *const Position, c: types.Color) types.Square.Set {
        return self.colorOccPtrConst(c).*;
    }

    pub fn ptypeOcc(self: *const Position, p: types.Ptype) types.Square.Set {
        return self.ptypeOccPtrConst(p).*;
    }

    pub fn pieceOcc(self: *const Position, p: types.Piece) types.Square.Set {
        const c = p.color();
        const t = p.ptype();

        const co = self.colorOcc(c);
        const to = self.ptypeOcc(t);
        return @TypeOf(co, to).bwa(co, to);
    }

    pub fn getSquare(self: *const Position, s: types.Square) types.Piece {
        return self.by_square.getPtrConst(s).*;
    }

    pub fn kingSquare(self: *const Position, c: types.Color) types.Square {
        const k: types.Piece = .init(.king, c);
        return self.pieceOcc(k).lowSquare() orelse std.debug.panic("king not found", .{});
    }

    pub fn material(self: *const Position) u8 {
        return self.ptypeOcc(.pawn).count() +
            self.ptypeOcc(.knight).count() * 3 +
            self.ptypeOcc(.knight).count() * 3 +
            self.ptypeOcc(.rook).count() * 5 +
            self.ptypeOcc(.queen).count() * 9;
    }

    pub fn squareAtkers(self: *const Position, s: types.Square) types.Square.Set {
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

    pub fn isChecked(self: *const Position) bool {
        return self.checks != .full;
    }

    pub fn isMoveLegal(self: *const Position, move: movegen.Move) bool {
        return if (self.tryMove(move)) |_| true else |_| false;
    }

    pub fn isMovePseudoLegal(self: *const Position, move: movegen.Move) bool {
        const stm = self.stm;
        const occ = self.bothOcc();
        const us = self.colorOcc(stm);
        const them = self.colorOcc(stm.flip());

        const s = move.src;
        const d = move.dst;
        if (!us.get(s)) {
            return false;
        }

        const sp = self.getSquare(s);
        const dp = self.getSquare(d);

        const atk, const push1, const push2 = switch (sp.ptype()) {
            .pawn => .{
                bitboard.pAtk(s.toSet(), stm),
                bitboard.pPush1(s.toSet(), occ, stm),
                bitboard.pPush2(s.toSet(), occ, stm),
            },
            else => |pt| .{ bitboard.ptAtk(pt, s, occ), .none, .none },
        };
        const promote_bb = stm.promotionRank().toSet();

        return switch (move.flag) {
            .none => none: {
                const bb = switch (sp.ptype()) {
                    .pawn => push1.bwa(promote_bb.flip()),
                    else => atk.bwa(occ.flip()),
                };
                break :none bb.get(d);
            },

            .torped => sp.ptype() == .pawn and push2.get(d),

            .castle_q, .castle_k => |f| castle: {
                const right = f.castle(stm) orelse unreachable;
                const castle = self.castles.get(right) orelse break :castle false;

                const is_checked = self.isChecked();
                const between = occ.bwa(castle.occ);

                const rook = types.Piece.init(.rook, stm);
                const king = types.Piece.init(.king, stm);

                break :castle !is_checked and
                    between == .none and
                    s == castle.ks and sp == king and
                    d == castle.rs and dp == rook;
            },

            .promote_n,
            .promote_b,
            .promote_r,
            .promote_q,
            => sp.ptype() == .pawn and push1.bwa(promote_bb).bwa(them).get(d),

            .noisy => noisy: {
                const bb = switch (sp.ptype()) {
                    .pawn => atk.bwa(promote_bb.flip()),
                    else => atk,
                };
                break :noisy bb.bwa(them).get(d);
            },

            .en_passant => if (self.en_pas) |ep|
                sp.ptype() == .pawn and ep == d and atk.get(ep)
            else
                false,

            else => sp.ptype() == .pawn and atk.bwa(promote_bb).bwa(them).get(d),
        };
    }

    pub fn see(
        self: *const Position,
        comptime mode: @import("see.zig").Mode,
        move: movegen.Move,
        min: evaluation.score.Int,
    ) bool {
        return @import("see.zig").func(mode, self, move, min);
    }
};

pub fn parseFen(self: *Board, fen: []const u8) FenError!void {
    const backup = self.*;
    errdefer self.* = backup;
    self.* = .{};

    const position = self.positions.last();
    try position.parseFen(fen);
    self.finny_table = .init(position);
}

pub fn parseFenTokens(self: *Board, tokens: *std.mem.TokenIterator(u8, .any)) FenError!void {
    const backup = self.*;
    errdefer self.* = backup;
    self.* = .{};

    const position = self.positions.last();
    try position.parseFenTokens(tokens);
    self.finny_table = .init(position);
}

pub fn doMove(self: *Board, move: movegen.Move) void {
    const stm = self.positions.last().stm;
    const s = move.src;
    const d = move.dst;
    const sp = self.positions.last().getSquare(s);
    const dp = self.positions.last().getSquare(d);

    self.positions.last().move = move;
    self.positions.last().src_piece = sp;
    self.positions.last().dst_piece = dp;

    const pos = self.positions.addOneUnchecked();
    pos.* = pos.before(1).tryMove(move) catch std.debug.panic("unchecked move", .{});
    pos.en_pas = null;
    pos.rule50 = if (sp.ptype() != .pawn and !move.flag.isNoisy()) pos.rule50 + 1 else 0;

    const perspective = self.perspectives.addOneUnchecked();
    perspective.dirty = .initFill(true);

    if (sp.ptype() == .pawn) {
        // TODO: check en passant (pseudo-)legality
        if (move.flag == .torped) {
            pos.en_pas = d.shift(stm.forward().flip(), 1);
        }
    } else if (sp.ptype() == .rook) {
        var iter = pos.castles.iterator();
        while (iter.next()) |entry| {
            const k = entry.key;
            const v = entry.value;
            if (s == v.rs) {
                pos.popCastle(k);
                break;
            }
        }
    } else if (sp.ptype() == .king) {
        defer {
            pos.popCastle(if (stm == .white) .wk else .bk);
            pos.popCastle(if (stm == .white) .wq else .bq);
        }

        const ks, const kd = if (move.flag.isCastle()) castle: {
            const right = move.flag.castle(stm) orelse unreachable;
            const castle = pos.castles.getAssertContains(right);
            break :castle .{ castle.ks, castle.kd };
        } else .{ s, d };

        const hms = switch (ks.file()) {
            .file_a, .file_b, .file_c, .file_d => false,
            else => true,
        };
        const hmd = switch (kd.file()) {
            .file_a, .file_b, .file_c, .file_d => false,
            else => true,
        };
        if (hms != hmd) {
            self.finny_table.load(stm, perspective, pos);
        }
    }

    if (dp != .none and dp.ptype() == .rook) {
        var iter = pos.castles.iterator();
        while (iter.next()) |entry| {
            const k = entry.key;
            const v = entry.value;
            if (d == v.rs) {
                pos.popCastle(k);
                break;
            }
        }
    }

    pos.stm = stm.flip();
    pos.checks = pos.genCheckMask();
    pos.key ^= zobrist.stm() ^ zobrist.enp(pos.before(1).en_pas) ^ zobrist.enp(pos.en_pas);
}

pub fn doNull(self: *Board) void {
    self.positions.last().move = .{};
    self.positions.last().src_piece = .none;
    self.positions.last().dst_piece = .none;

    const perspective = self.perspectives.addOneUnchecked();
    perspective.dirty = .initFill(true);

    const pos = self.positions.addOneUnchecked();
    pos.* = pos.before(1).*;
    pos.en_pas = null;
    pos.rule50 = 0;

    pos.stm = pos.stm.flip();
    pos.checks = .full;
    pos.key ^= zobrist.stm() ^ zobrist.enp(pos.before(1).en_pas) ^ zobrist.enp(pos.en_pas);
}

pub fn undoMove(self: *Board) void {
    _ = self.perspectives.pop();
    _ = self.positions.pop();
}

pub fn undoNull(self: *Board) void {
    self.undoMove();
}

pub fn getRepeat(self: *const Board) usize {
    const key = self.positions.last().key;
    var peat: usize = 0;

    for (self.positions.slice()) |*p| {
        const key_matched = p.key == key;
        peat += @intFromBool(key_matched);
    }
    return peat;
}

pub fn is3peat(self: *const Board) bool {
    return self.getRepeat() >= 3;
}

pub fn isDrawn(self: *const Board) bool {
    return self.positions.last().rule50 >= 100 or self.is3peat();
}

pub fn isTerminal(self: *const Board) bool {
    return self.positions.len >= self.positions.buffer.len;
}

pub fn evaluate(self: *Board) evaluation.score.Int {
    const perspective = self.perspectives.last();
    const position = self.positions.last();

    for (types.Color.values) |c| {
        if (perspective.dirty.get(c)) {
            self.finny_table.load(c, perspective, position);
        }
    }

    const inferred = nnue.network.verbatim.infer(perspective, position);
    const scaled = @divTrunc(inferred * (100 - position.rule50), 100);
    const min = evaluation.score.lose + 1;
    const max = evaluation.score.win - 1;
    return std.math.clamp(scaled, min, max);
}
