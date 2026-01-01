const std = @import("std");
const types = @import("types");

const utils = @import("utils.zig");

var n_atk: std.EnumArray(types.Square, types.Square.Set) align(std.atomic.cache_line) =
    .initFill(.none);
var k_atk: std.EnumArray(types.Square, types.Square.Set) align(std.atomic.cache_line) =
    .initFill(.none);

fn nAtkInit() void {
    for (types.Square.values) |s| {
        n_atk.set(s, utils.genAtk(.knight, s, .none));
    }
}

fn kAtkInit() void {
    for (types.Square.values) |s| {
        k_atk.set(s, utils.genAtk(.king, s, .none));
    }
}

pub fn init() !void {
    nAtkInit();
    kAtkInit();
}

pub fn nAtk(s: types.Square) types.Square.Set {
    return n_atk.getPtrConst(s).*;
}

pub fn kAtk(s: types.Square) types.Square.Set {
    return k_atk.getPtrConst(s).*;
}
