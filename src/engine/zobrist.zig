const bitboard = @import("bitboard");
const std = @import("std");
const types = @import("types");

const Keys = struct {
    occ: std.EnumArray(types.Square, std.EnumArray(types.Piece, Int)),
    castle: std.EnumArray(types.Castle, Int),
    en_pas: std.EnumArray(types.File, Int),
    stm: Int,

    var default: Keys = undefined;
};

pub const Int = types.Square.Set.Int;

pub fn init() !void {
    var r = std.Random.Xoroshiro128.init(0xa69f73cca23a9ac5);

    for (types.Square.values) |s| {
        for (types.Piece.w_pieces) |p| {
            Keys.default.occ.getPtr(s).set(p, r.random().int(Int));
        }
        for (types.Piece.b_pieces) |p| {
            Keys.default.occ.getPtr(s).set(p, r.random().int(Int));
        }
    }

    for (types.Castle.values) |e| {
        Keys.default.castle.set(e, r.random().int(Int));
    }

    for (types.File.values) |e| {
        Keys.default.en_pas.set(e, r.random().int(Int));
    }

    Keys.default.stm = r.random().int(Int);
}

pub fn psq(s: types.Square, p: types.Piece) Int {
    return Keys.default.occ.getPtrConst(s).getPtrConst(p).*;
}

pub fn cas(c: types.Castle) Int {
    return Keys.default.castle.getPtrConst(c).*;
}

pub fn enp(e: ?types.Square) Int {
    return if (e) |s| Keys.default.en_pas.getPtrConst(s.file()).* else 0;
}

pub fn stm() Int {
    return Keys.default.stm;
}

pub fn index(key: Int, len: usize) usize {
    const m = std.math.mulWide(usize, key, len);
    const h = std.math.shr(@TypeOf(m), m, @typeInfo(@TypeOf(m)).int.bits / 2);
    return @truncate(h);
}
