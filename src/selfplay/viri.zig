const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Piece = enum(u4) {
    w_pawn = 0,
    w_knight = 1,
    w_bishop = 2,
    w_rook = 3,
    w_queen = 4,
    w_king = 5,
    w_castle = 6,

    b_pawn = 8,
    b_knight = 9,
    b_bishop = 10,
    b_rook = 11,
    b_queen = 12,
    b_king = 13,
    b_castle = 14,

    pub const Int = std.meta.Tag(Piece);
    pub const int_info = @typeInfo(Int).int;

    fn fromSquare(pos: *const engine.Board.Position, s: types.Square) Piece {
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

pub const Line = bounded_array.BoundedArray(Move.Scored, 1024);

pub const Move = packed struct(u16) {
    src: types.Square = @enumFromInt(0),
    dst: types.Square = @enumFromInt(0),
    flag: u4 = 0b0000,

    pub const Scored = extern struct {
        move: Move = .{},
        score: i16 = engine.evaluation.score.draw,
    };

    pub const zero: Move = .{};

    pub fn fromMove(move: engine.movegen.Move) Move {
        return .{
            .flag = switch (move.flag) {
                .q_castle, .k_castle => 0b1000,
                .promote_n, .noisy_promote_n => 0b1100,
                .promote_b, .noisy_promote_b => 0b1101,
                .promote_r, .noisy_promote_r => 0b1110,
                .promote_q, .noisy_promote_q => 0b1111,
                .en_passant => 0b0100,
                else => 0b0000,
            },
            .src = move.src,
            .dst = move.dst,
        };
    }
};

pub const Result = enum(u8) {
    black,
    draw,
    white,
    none,
};

pub const Data = extern struct {
    occ: types.Square.Set = .none,
    pieces: u128 align(8) = 0,

    flag: u8 = 0,

    ply: u8 = 0,
    length: u16 = 0,
    score: i16 = 0,

    result: Result = .draw,
    pad: u8 = 0,

    pub fn fromBoard(board: *engine.Board) Data {
        var self: Data = .{};
        const pos = board.top();
        const eval = board.evaluate();

        self.ply = pos.rule50;
        self.length = 0;
        self.score = @intCast(switch (pos.stm) {
            .white => eval,
            .black => -eval,
        });

        var i: usize = 0;
        var occ = pos.bothOcc();
        self.occ = occ;
        while (occ.lowSquare()) |s| : ({
            i += 1;
            occ.popLow();
        }) {
            const t = Piece.fromSquare(pos, s).int();
            self.pieces |= std.math.shl(u128, t, i * Piece.int_info.bits);
        }

        self.flag = if (pos.en_pas) |s| s.int() else types.Square.num;
        if (pos.stm == .black) {
            self.flag |= 1 << 7;
        }

        return self;
    }
};
