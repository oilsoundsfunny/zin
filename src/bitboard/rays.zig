const std = @import("std");
const types = @import("types");

const root = @import("root.zig");

const Table = [types.Square.num][types.Square.num]types.Square.Set;

var diag_incl: Table align(std.atomic.cache_line) = @splat(@splat(.none));
var orth_incl: Table align(std.atomic.cache_line) = @splat(@splat(.none));

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
    return diag_incl[s.int()][d.int()];
}

pub fn orthIncl(s: types.Square, d: types.Square) types.Square.Set {
    return orth_incl[s.int()][d.int()];
}

pub fn diagExcl(s: types.Square, d: types.Square) types.Square.Set {
    return diagIncl(s, d)
        .bwa(s.toSet().flip())
        .bwa(d.toSet().flip());
}

pub fn orthExcl(s: types.Square, d: types.Square) types.Square.Set {
    return orthIncl(s, d)
        .bwa(s.toSet().flip())
        .bwa(d.toSet().flip());
}
