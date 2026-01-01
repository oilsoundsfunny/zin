const std = @import("std");
const types = @import("types");

const sliding = @import("sliding.zig");

pub fn genAtk(comptime pt: types.Ptype, s: types.Square, b: types.Square.Set) types.Square.Set {
    const dirs: []const types.Direction = switch (pt) {
        .knight => &.{
            .northnorthwest, .westnorthwest, .southsouthwest, .westsouthwest,
            .northnortheast, .eastnortheast, .southsoutheast, .eastsoutheast,
        },
        .bishop => &.{
            .northwest, .northeast,
            .southwest, .southeast,
        },
        .rook => &.{
            .north, .west, .south, .east,
        },
        .king => &.{
            .north, .northwest, .west, .southwest,
            .south, .southeast, .east, .northeast,
        },
        else => @compileError("unexpected int" ++ @tagName(pt)),
    };
    const max = switch (pt) {
        .knight, .king => 1,
        .bishop, .rook => types.Square.cnt,
        else => @compileError("unexpected int" ++ @tagName(pt)),
    };
    var atk = types.Square.Set.none;

    for (dirs) |d| {
        for (1..max + 1) |i| {
            if (!s.okShift(d, i)) {
                break;
            }

            const shifted = s.shift(d, i);
            atk.set(shifted);

            if (b.get(shifted)) {
                break;
            }
        }
    }
    return atk;
}

pub fn genIdx(comptime pt: types.Ptype, s: types.Square, b: types.Square.Set) types.Square.Set.Int {
    return switch (pt) {
        .knight, .king => s.int(),
        .bishop, .rook => blk: {
            const shr = if (pt == .rook) 64 - 12 else 64 - 9;
            const tbl = if (pt == .rook) &sliding.r_atk else &sliding.b_atk;

            const magic = tbl.getPtrConst(s).magic;
            const nmask = tbl.getPtrConst(s).nmask;

            const mul = b.bwo(nmask).int() *% magic;
            const idx = std.math.shr(@TypeOf(mul), mul, shr);
            break :blk idx;
        },
        else => @compileError("unexpected int" ++ @tagName(pt)),
    };
}
