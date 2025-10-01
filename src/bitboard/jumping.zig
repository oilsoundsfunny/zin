const base = @import("base");
const std = @import("std");

const n_atk = n_init: {
	const bin = @embedFile("n_atk.bin");
	var tbl = std.EnumArray(base.types.Square, base.types.Square.Set).initFill(.nul);

	@memcpy(std.mem.sliceAsBytes(tbl.values[0 ..]), bin[0 ..]);
	break :n_init n_atk;
};

const k_atk = k_init: {
	const bin = @embedFile("k_atk.bin");
	var tbl = std.EnumArray(base.types.Square, base.types.Square.Set).initFill(.nul);

	@memcpy(std.mem.sliceAsBytes(tbl.values[0 ..]), bin[0 ..]);
	break :k_init k_atk;
};

pub fn prefetch() void {
	@prefetch(&n_atk, .{});
	@prefetch(&k_atk, .{});

	@prefetch(&nAtk, .{.cache = .instruction});
	@prefetch(&kAtk, .{.cache = .instruction});
}

pub fn nAtk(s: base.types.Square) base.types.Square.Set {
	return n_atk.getPtrConst(s).*;
}

pub fn kAtk(s: base.types.Square) base.types.Square.Set {
	return k_atk.getPtrConst(s).*;
}
