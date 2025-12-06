const builtin = @import("builtin");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");
const arch = @import("arch.zig");

pub const Self = extern struct {
	hl0_w:	[arch.inp_len][arch.hl0_len]arch.Int align(64),
	hl0_b:	[arch.hl0_len]arch.Int align(64),

	out_w:	[arch.color_n][arch.hl0_len]arch.Int align(64),
	out_b:	arch.Int align(64),

	pub fn infer(self: *const Self, pos: *const engine.Board.One) engine.evaluation.score.Int {
		const stm = pos.stm;
		const accumulator = &pos.accumulator;

		const Vec = *align(32) const Accumulator.Vec;
		const vecs = std.EnumArray(types.Color, Vec).init(.{
			.white = accumulator.perspectives.getPtrConst(stm),
			.black = accumulator.perspectives.getPtrConst(stm.flip()),
		});
		const wgts = std.EnumArray(types.Color, Vec).init(.{
			.white = @ptrCast(&self.out_w[types.Color.white.tag()]),
			.black = @ptrCast(&self.out_w[types.Color.black.tag()]),
		});

		var out: Accumulator.Madd = @splat(engine.evaluation.score.draw);
		inline for (types.Color.values) |c| {
			const v = vecs.get(c).*;
			const w = wgts.get(c).*;
			const clamped = crelu(v);

			const vw = clamped *% w;
			out +%= madd(clamped, vw);
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

fn madd(a: Accumulator.Vec, b: Accumulator.Vec) Accumulator.Madd {
	const a_deinterlaced = std.simd.deinterlace(2, a);
	const b_deinterlaced = std.simd.deinterlace(2, b);

	const a0: Accumulator.Madd = a_deinterlaced[0];
	const a1: Accumulator.Madd = a_deinterlaced[1];
	const b0: Accumulator.Madd = b_deinterlaced[0];
	const b1: Accumulator.Madd = b_deinterlaced[1];
	return a0 *% b0 +% a1 *% b1;
}

fn crelu(v: Accumulator.Vec) Accumulator.Vec {
	const min: Accumulator.Vec = @splat(0);
	const max: Accumulator.Vec = @splat(arch.qa);
	return std.math.clamp(v, min, max);
}
