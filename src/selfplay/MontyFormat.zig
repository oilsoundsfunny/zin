const engine = @import("engine");
const std = @import("std");
const types = @import("types");

head: Head,
line: Move.Root.List.Line,

const Castle = extern struct {
    frc: bool,
    mask: [types.Square.num]u8,
    files: [types.Color.num][2]u8,
};

const Position = extern struct {
    occ: [types.Ptype.num + types.Color.num]types.Square.Set,
    stm: types.Color,
    en_pas: u8,
    rights: u8,
    ply: u8,
    moves: u16,
    key: engine.zobrist.Int,
};

pub const Head = extern struct {
    pos: Position = .{},
    castle: Castle,
    result: f32,
};

pub const Move = packed struct(u16) {};
