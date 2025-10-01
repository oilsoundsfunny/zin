const base = @import("base");
const std = @import("std");

const n_atk align(64) = @embedFile("n_atk.bin");
const k_atk align(64) = @embedFile("k_atk.bin");

pub fn prefetch() void {
	@prefetch(&n_atk, .{});
	@prefetch(&k_atk, .{});

	@prefetch(&nAtk, .{.cache = .instruction});
	@prefetch(&kAtk, .{.cache = .instruction});
}

pub fn nAtk(s: base.types.Square) base.types.Square.Set {
	const p = std.mem.bytesAsSlice(base.types.Square.Set, n_atk[0 ..]);
	const i = s.tag();
	return p[i];
}

pub fn kAtk(s: base.types.Square) base.types.Square.Set {
	const p = std.mem.bytesAsSlice(base.types.Square.Set, k_atk[0 ..]);
	const i = s.tag();
	return p[i];
}
