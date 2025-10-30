const base = @import("base");
const std = @import("std");

const misc = @import("misc.zig");

var n_atk align(64) = std.EnumArray(base.types.Square, base.types.Square.Set).initFill(.none);
var k_atk align(64) = std.EnumArray(base.types.Square, base.types.Square.Set).initFill(.none);

fn nAtkInit() !void {
	for (base.types.Square.values) |s| {
		n_atk.set(s, misc.genAtk(.knight, s, .none));
	}
}

fn kAtkInit() !void {
	for (base.types.Square.values) |s| {
		k_atk.set(s, misc.genAtk(.king, s, .none));
	}
}

fn prefetch() void {
	@prefetch(&n_atk, .{});
	@prefetch(&k_atk, .{});

	@prefetch(&nAtk, .{.cache = .instruction});
	@prefetch(&kAtk, .{.cache = .instruction});
}

pub fn init() !void {
	defer prefetch();
	try nAtkInit();
	try kAtkInit();
}

pub fn nAtk(s: base.types.Square) base.types.Square.Set {
	return n_atk.getPtrConst(s).*;
}

pub fn kAtk(s: base.types.Square) base.types.Square.Set {
	return k_atk.getPtrConst(s).*;
}
