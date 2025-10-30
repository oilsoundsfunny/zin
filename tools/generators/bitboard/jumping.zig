const base = @import("base");
const std = @import("std");

const misc = @import("misc.zig");

pub var n_atk = std.EnumArray(base.types.Square, base.types.Square.Set).initFill(.none);
pub var k_atk = std.EnumArray(base.types.Square, base.types.Square.Set).initFill(.none);

fn nAtkInit() void {
	for (base.types.Square.values) |s| {
		n_atk.set(s, misc.genAtk(.knight, s, .none));
	}
}

fn kAtkInit() void {
	for (base.types.Square.values) |s| {
		k_atk.set(s, misc.genAtk(.king, s, .none));
	}
}

pub fn init() void {
	nAtkInit();
	kAtkInit();
}
