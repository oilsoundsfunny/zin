const std = @import("std");
const types = @import("types");

pub fn genAtk(comptime pt: types.Ptype, s: types.Square, b: types.Square.Set) types.Square.Set {
    const dirs: []const types.Direction = switch (pt) {
        .knight => &.{
            .northnorthwest, .westnorthwest, .southsouthwest, .westsouthwest,
            .northnortheast, .eastnortheast, .southsoutheast, .eastsoutheast,
        },
        .bishop => &.{ .northwest, .northeast, .southwest, .southeast },
        .rook => &.{ .north, .west, .south, .east },
        .king => &.{
            .north, .northwest, .west, .southwest, .south, .southeast, .east, .northeast,
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
