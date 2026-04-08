const std = @import("std");
const types = @import("types");

const root = @import("root.zig");

var diag_incl: [types.Square.num][types.Square.num]types.Square.Set align(std.atomic.cache_line) =
    @splat(@splat(.none));
var orth_incl: [types.Square.num][types.Square.num]types.Square.Set align(std.atomic.cache_line) =
    @splat(@splat(.none));

fn diagInit() void {
    for (types.Square.values) |s| {
        for (types.Square.values) |d| {
            const from_s = root.bAtk(s, d.toSet());
            const from_d = root.bAtk(d, s.toSet());
            if (!from_s.get(d)) {
                continue;
            }

            diag_incl[s.int()][d.int()] = from_s.bwa(from_d);
            diag_incl[s.int()][d.int()].set(s);
            diag_incl[s.int()][d.int()].set(d);
        }
    }
}

fn orthInit() void {
    for (types.Square.values) |s| {
        for (types.Square.values) |d| {
            const from_s = root.rAtk(s, d.toSet());
            const from_d = root.rAtk(d, s.toSet());
            if (!from_s.get(d)) {
                continue;
            }

            orth_incl[s.int()][d.int()] = from_s.bwa(from_d);
            orth_incl[s.int()][d.int()].set(s);
            orth_incl[s.int()][d.int()].set(d);
        }
    }
}

pub fn init() !void {
    diagInit();
    orthInit();
}

pub fn diagIncl(s: types.Square, d: types.Square) types.Square.Set {
    const p = &diag_incl[s.int()][d.int()];
    return p.*;
}

pub fn orthIncl(s: types.Square, d: types.Square) types.Square.Set {
    const p = &orth_incl[s.int()][d.int()];
    return p.*;
}

pub fn diagExcl(s: types.Square, d: types.Square) types.Square.Set {
    var b = diagIncl(s, d);
    b.pop(s);
    b.pop(d);
    return b;
}

pub fn orthExcl(s: types.Square, d: types.Square) types.Square.Set {
    var b = orthIncl(s, d);
    b.pop(s);
    b.pop(d);
    return b;
}
