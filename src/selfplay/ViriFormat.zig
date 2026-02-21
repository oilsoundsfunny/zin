const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

head: Head,
line: Move.Scored.Line,

const Piece = enum(u4) {
    w_pawn = 0,
    w_knight,
    w_bishop,
    w_rook,
    w_queen,
    w_king,
    w_castle,

    b_pawn = 8,
    b_knight,
    b_bishop,
    b_rook,
    b_queen,
    b_king,
    b_castle,

    pub const Int = std.meta.Tag(Piece);
    pub const int_info = @typeInfo(Int).int;

    fn init(pos: *const engine.Board.Position, s: types.Square) Piece {
        var iter = @constCast(pos).castles.iterator();

        return switch (pos.getSquare(s)) {
            .w_rook => loop: while (iter.next()) |entry| {
                const k = entry.key;
                const v = entry.value;

                if (pos.castles.contains(k) and v.rs == s) {
                    break :loop Piece.w_castle;
                }
            } else Piece.w_rook,

            .b_rook => loop: while (iter.next()) |entry| {
                const k = entry.key;
                const v = entry.value;

                if (pos.castles.contains(k) and v.rs == s) {
                    break :loop Piece.b_castle;
                }
            } else Piece.b_rook,

            .none => std.debug.panic("invalid piece", .{}),
            inline else => |e| @field(Piece, @tagName(e)),
        };
    }

    fn fromInt(i: Int) Piece {
        return @enumFromInt(i);
    }

    fn int(self: Piece) Int {
        return @intFromEnum(self);
    }
};

pub const Result = enum(u8) {
    black,
    draw,
    white,
    none,
};

pub const Head = extern struct {
    occ: types.Square.Set,
    pieces: u128 align(8) = 0,
    flag: u8 = 0,
    ply: u8,
    moves: u16 = 1,
    score: i16,
    result: Result = .none,
    pad: u8 = 0,

    pub fn init(board: *engine.Board) Head {
        const pos = board.positions.last();
        const mat = pos.material();
        const eval = board.evaluate();
        const norm = engine.evaluation.score.normalize(eval, mat);

        var occ = pos.bothOcc();
        var self: Head = .{
            .occ = occ,
            .ply = pos.rule50,
            .score = @intCast(switch (pos.stm) {
                .white => norm,
                .black => -norm,
            }),
        };

        var i: usize = 0;
        while (occ.lowSquare()) |s| : ({
            i += 1;
            occ.popLow();
        }) {
            const t = Piece.init(pos, s).int();
            self.pieces |= std.math.shl(u128, t, i * Piece.int_info.bits);
        }

        self.flag = if (pos.en_pas) |s| s.int() else types.Square.num;
        if (pos.stm == .black) {
            self.flag |= 1 << 7;
        }

        return self;
    }
};

pub const Move = packed struct(u16) {
    src: types.Square,
    dst: types.Square,
    promotion: u2,
    flag: u2,

    pub const Scored = extern struct {
        move: Move = .init(.{}),
        score: i16 = engine.evaluation.score.draw,

        pub const Line = types.BoundedArray(Move.Scored, null, 1024);
    };

    pub fn init(m: engine.movegen.Move) Move {
        return .{
            .src = m.src,
            .dst = m.dst,
            .promotion = if (m.flag.promotion()) |pt| switch(pt) {
                .knight => 0,
                .bishop => 1,
                .rook => 2,
                .queen => 3,
                else => std.debug.panic("invalid promotion", .{}),
            } else 0,
            .flag = switch (m.flag) {
                .en_passant => 1,
                .castle_k, .castle_q => 2,
                .promote_n,
                .promote_b,
                .promote_r,
                .promote_q,
                .noisy_promote_n,
                .noisy_promote_b,
                .noisy_promote_r,
                .noisy_promote_q,
                => 3,
                else => 0,
            },
        };
    }
};
