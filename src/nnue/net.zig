const base = @import("base");
const engine = @import("engine");
const std = @import("std");

const Accumulator = @import("Accumulator.zig");
const arch = @import("arch.zig");

fn crelu(v: anytype, low: @TypeOf(v), high: @TypeOf(v)) @TypeOf(v) {
	return std.math.clamp(v, low, high);
}

fn screlu(v: anytype, low: @TypeOf(v), high: @TypeOf(v)) @TypeOf(v) {
	const clamped = crelu(v, low, high);
	return clamped *% clamped;
}

pub const Self = extern struct {
	hl0_w:	[arch.inp_len][arch.hl0_len]arch.Int align(64),
	hl0_b:	[arch.hl0_len]arch.Int align(64),

	out_w:	[arch.color_n][arch.hl0_len]arch.Int align(64),
	out_b:	arch.Int align(64),

	pub fn infer(self: *const Self, accumulators: *const Accumulator.Pair) arch.Int {
		const Vec = @Vector(arch.hl0_len, i16);
		const vecs = std.EnumArray(base.types.Color, *align(64) const Vec).init(.{
			.white = @ptrCast(&accumulators.white),
			.black = @ptrCast(&accumulators.black),
		});

		const wgts = std.EnumArray(base.types.Color, *align(64) const Vec).init(.{
			.white = @ptrCast(self.out_w[base.types.Color.white.tag()][0 .. arch.hl0_len]),
			.black = @ptrCast(self.out_w[base.types.Color.black.tag()][0 .. arch.hl0_len]),
		});

		var o: i32 = 0;
		for (base.types.Color.values) |c| {
			const v: @Vector(arch.hl0_len, i32) = vecs.get(c).*;
			const w: @Vector(arch.hl0_len, i32) = wgts.get(c).*;
			o +%= @reduce(.Add, screlu(v, @splat(0), @splat(arch.qa)) *% w);
		}

		o = @divTrunc(o, arch.qa) +% self.out_b;
		o = @divTrunc(o *% arch.scale, arch.qa * arch.qb);

		return @intCast(o);
	}
};
