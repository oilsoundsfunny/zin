const std = @import("std");
const types = @import("types");

const root = @import("root.zig");

var b_incl: [types.Square.num][types.Square.num]types.Square.Set align(std.atomic.cache_line) =
    @splat(@splat(.none));
var r_incl: [types.Square.num][types.Square.num]types.Square.Set align(std.atomic.cache_line) =
    @splat(@splat(.none));
var q_incl: [types.Square.num][types.Square.num]types.Square.Set align(std.atomic.cache_line) =
    @splat(@splat(.none));

fn bInit() void {
    for (types.Square.values) |s| {
        for (types.Square.values) |d| {
            const from_s = root.bAtk(s, d.toSet());
            const from_d = root.bAtk(d, s.toSet());
            if (!from_s.get(d)) {
                continue;
            }

            b_incl[s.int()][d.int()] = from_s.bwa(from_d);
            b_incl[s.int()][d.int()].set(s);
            b_incl[s.int()][d.int()].set(d);
        }
    }
}

fn rInit() void {
    for (types.Square.values) |s| {
        for (types.Square.values) |d| {
            const from_s = root.rAtk(s, d.toSet());
            const from_d = root.rAtk(d, s.toSet());
            if (!from_s.get(d)) {
                continue;
            }

            r_incl[s.int()][d.int()] = from_s.bwa(from_d);
            r_incl[s.int()][d.int()].set(s);
            r_incl[s.int()][d.int()].set(d);
        }
    }
}

pub fn init() !void {
    bInit();
    rInit();
}

pub fn bRayIncl(s: types.Square, d: types.Square) types.Square.Set {
    const p = &b_incl[s.int()][d.int()];
    return p.*;
}

pub fn rRayIncl(s: types.Square, d: types.Square) types.Square.Set {
    const p = &r_incl[s.int()][d.int()];
    return p.*;
}

pub fn bRayExcl(s: types.Square, d: types.Square) types.Square.Set {
    var b = bRayIncl(s, d);
    b.pop(s);
    b.pop(d);
    return b;
}

pub fn rRayExcl(s: types.Square, d: types.Square) types.Square.Set {
    var b = rRayIncl(s, d);
    b.pop(s);
    b.pop(d);
    return b;
}
