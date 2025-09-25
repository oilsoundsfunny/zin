const base = @import("base");
const std = @import("std");

const misc = @import("misc.zig");

var n_atk_tbl = std.EnumArray(base.types.Square, misc.Set).initFill(.nul);
var k_atk_tbl = std.EnumArray(base.types.Square, misc.Set).initFill(.nul);

pub fn prefetch() void {
	@prefetch(&n_atk_tbl, .{});
	@prefetch(&k_atk_tbl, .{});

	@prefetch(&nAtk, .{.cache = .instruction});
	@prefetch(&kAtk, .{.cache = .instruction});
}

pub fn nAtkInit() !void {
	for (base.types.Square.values) |s| {
		n_atk_tbl.set(s, misc.genAtk(.knight, s, .nul));
	}
}

pub fn kAtkInit() !void {
	for (base.types.Square.values) |s| {
		k_atk_tbl.set(s, misc.genAtk(.king, s, .nul));
	}
}

pub fn nAtk(s: base.types.Square) misc.Set {
	return n_atk_tbl.getPtrConst(s).*;
}

pub fn kAtk(s: base.types.Square) misc.Set {
	return k_atk_tbl.getPtrConst(s).*;
}
