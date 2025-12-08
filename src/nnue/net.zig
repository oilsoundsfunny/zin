const builtin = @import("builtin");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");
const arch = @import("arch.zig");

pub const Self = extern struct {
	hl0_w:	[arch.inp_len][arch.hl0_len]arch.Int align(64),
	hl0_b:	[arch.hl0_len]arch.Int align(64),

	out_w:	[arch.color_n][arch.hl0_len / 2]arch.Int align(64),
	out_b:	arch.Int align(64),

	pub fn infer(self: *const Self, pos: *const engine.Board.One) engine.evaluation.score.Int {
		const stm = pos.stm;
		const accumulator = &pos.accumulator;

		const vecs = std.EnumArray(types.Color, *align(64) const Accumulator.Vec).init(.{
			.white = accumulator.perspectives.getPtrConst(stm),
			.black = accumulator.perspectives.getPtrConst(stm.flip()),
		});

		const wgts = std.EnumArray(types.Color, *align(64) const Accumulator.Half).init(.{
			.white = @ptrCast(&self.out_w[types.Color.white.tag()]),
			.black = @ptrCast(&self.out_w[types.Color.black.tag()]),
		});

		var out: Accumulator.Madd = @splat(engine.evaluation.score.draw);
		for (types.Color.values) |c| {
			const v = vecs.get(c).*;
			const w = wgts.get(c).*;

			const half_len = arch.hl0_len / 2;
			const v0: Accumulator.Half
			  = @as([arch.hl0_len]arch.Int, v)[half_len * 0 ..][0 .. half_len].*;
			const v1: Accumulator.Half
			  = @as([arch.hl0_len]arch.Int, v)[half_len * 1 ..][0 .. half_len].*;

			const clamped0 = crelu(v0);
			const clamped1 = crelu(v1);
			out +%= madd(clamped0, clamped1 *% w);
		}

		var ev = @reduce(.Add, out);
		ev = @divTrunc(ev, arch.qa) + self.out_b;
		ev = @divTrunc(ev * arch.scale, arch.qa * arch.qb);
		return ev;
	}
};

pub const default = init: {
	const bin = @embedFile("default.nn");
	var net: Self align(64) = undefined;
	@memcpy(std.mem.asBytes(&net), bin[0 ..]);
	break :init net;
};

fn crelu(v: Accumulator.Half) @TypeOf(v) {
	const min: @TypeOf(v) = @splat(0);
	const max: @TypeOf(v) = @splat(arch.qa);
	return std.math.clamp(v, min, max);
}

fn madd(a: Accumulator.Half, b: Accumulator.Half) Accumulator.Madd {
	const a_deinterlaced = std.simd.deinterlace(2, a);
	const b_deinterlaced = std.simd.deinterlace(2, b);

	const a0: Accumulator.Madd = a_deinterlaced[0];
	const a1: Accumulator.Madd = a_deinterlaced[1];
	const b0: Accumulator.Madd = b_deinterlaced[0];
	const b1: Accumulator.Madd = b_deinterlaced[1];
	return a0 *% b0 +% a1 *% b1;
}
