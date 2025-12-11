const builtin = @import("builtin");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");
const arch = @import("arch.zig");

const Madd = @Vector(arch.native_len / 2, engine.evaluation.score.Int);

pub const Self = extern struct {
	hl0_w:	[arch.inp_len][arch.hl0_len]arch.Int,
	hl0_b:	[arch.hl0_len]arch.Int,

	out_w:	[arch.color_n][arch.hl0_len / 2]arch.Int,
	out_b:	arch.Int align(64),

	pub fn infer(self: *const Self, pos: *const engine.Board.One) engine.evaluation.score.Int {
		const stm = pos.stm;
		const accumulator = &pos.accumulator;

		const vecs = std.EnumArray(types.Color, *align(64) const [arch.hl0_len]arch.Int).init(.{
			.white = accumulator.perspectives.getPtrConst(stm),
			.black = accumulator.perspectives.getPtrConst(stm.flip()),
		});

		const half_len = arch.hl0_len / 2;
		const wgts = std.EnumArray(types.Color, *const [half_len]arch.Int).init(.{
			.white = self.out_w[types.Color.white.tag()][0 .. half_len],
			.black = self.out_w[types.Color.black.tag()][0 .. half_len],
		});

		var out: Madd = @splat(engine.evaluation.score.draw);
		for (types.Color.values) |c| {
			const v = vecs.get(c);
			const w = wgts.get(c);

			const native_len = arch.native_len;
			var i: usize = 0;

			while (i < half_len) : (i += native_len) {
				const v0: *const arch.Native = @alignCast(v[i + half_len * 0 ..][0 .. native_len]);
				const v1: *const arch.Native = @alignCast(v[i + half_len * 1 ..][0 .. native_len]);

				const clamped0 = crelu(v0.*);
				const clamped1 = crelu(v1.*);

				const wgt: *const arch.Native = @alignCast(w[i ..][0 .. native_len]);
				out +%= madd(clamped0, clamped1 *% wgt.*);
			}
		}

		var ev = @reduce(.Add, out);
		ev = @divTrunc(ev, arch.qa) + self.out_b;
		ev = @divTrunc(ev * arch.scale, arch.qa * arch.qb);
		return ev;
	}
};

pub const default = init: {
	const bin = @embedFile("default.nn");
	var net: Self = undefined;
	@memcpy(std.mem.asBytes(&net), bin[0 ..]);
	break :init net;
};

fn crelu(v: arch.Native) arch.Native {
	const min: arch.Native = @splat(0);
	const max: arch.Native = @splat(arch.qa);
	return std.math.clamp(v, min, max);
}

fn madd(a: arch.Native, b: arch.Native) Madd {
	const a_deinterlaced = std.simd.deinterlace(2, a);
	const b_deinterlaced = std.simd.deinterlace(2, b);

	const a0: Madd = a_deinterlaced[0];
	const a1: Madd = a_deinterlaced[1];
	const b0: Madd = b_deinterlaced[0];
	const b1: Madd = b_deinterlaced[1];
	return a0 *% b0 +% a1 *% b1;
}
