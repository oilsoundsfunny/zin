const base = @import("base");
const builtin = @import("builtin");
const engine = @import("engine");
const std = @import("std");

const Accumulator = @import("Accumulator.zig");
const arch = @import("arch.zig");

pub const Self = extern struct {
	hl0_w:	[arch.inp_len][arch.hl0_len]arch.Int align(64),
	hl0_b:	[arch.hl0_len]arch.Int align(64),

	out_w:	[arch.color_n][arch.hl0_len]arch.Int align(64),
	out_b:	arch.Int align(64),

	pub fn infer(self: *const Self, pos: *const engine.Position) engine.evaluation.score.Int {
		const stm = pos.stm;
		const accumulators = &pos.ss.top().accumulators;

		const vecs = std.EnumArray(base.types.Color, *align(64) const Accumulator.Vec).init(.{
			.white = if (stm == .white) &accumulators.white.values else &accumulators.black.values,
			.black = if (stm == .white) &accumulators.black.values else &accumulators.white.values,
		});

		const wgts = std.EnumArray(base.types.Color, *align(64) const Accumulator.Vec).init(.{
			.white = @ptrCast(&self.out_w[base.types.Color.white.tag()]),
			.black = @ptrCast(&self.out_w[base.types.Color.black.tag()]),
		});

		var out: MaddReturnType(Accumulator.Vec) = @splat(engine.evaluation.score.draw);
		var ev: engine.evaluation.score.Int = engine.evaluation.score.draw;
		inline for (base.types.Color.values) |c| {
			const v = vecs.get(c).*;
			const w = wgts.get(c).*;
			const clamped = crelu(v);

			const vw = clamped *% w;
			out +%= madd(clamped, vw);
		}

		ev = @reduce(.Add, out);
		ev = @divTrunc(ev, arch.qa) + self.out_b;
		ev = @divTrunc(ev * arch.scale, arch.qa * arch.qb);
		return ev;
	}
};

pub const default = init: {
	const bin = if (builtin.is_test) @embedFile("test.nn") else @embedFile("default.nn");
	var net: Self align(64) = undefined;
	@memcpy(std.mem.asBytes(&net), bin[0 ..]);
	break :init net;
};

fn MaddReturnType(comptime T: type) type {
	return switch (@typeInfo(T)) {
		.vector => |v| @Type(.{.vector = .{
			.len = if (v.len % 2 == 0) v.len / 2
			  else @compileError("unexpected vector length " ++ @typeName(v.len)),
			.child = @Type(.{.int = .{
				.signedness = @typeInfo(v.child).int.signedness,
				.bits = @typeInfo(v.child).int.bits * 2,
			}}),
		}}),
		else => @compileError("expected vector type, found " ++ @typeName(T)),
	};
}

fn madd(a: anytype, b: anytype) MaddReturnType(@TypeOf(a, b)) {
	const a_deinterlaced = std.simd.deinterlace(2, a);
	const b_deinterlaced = std.simd.deinterlace(2, b);

	const R = MaddReturnType(@TypeOf(a, b));
	const a0: R = @intCast(a_deinterlaced[0]);
	const a1: R = @intCast(a_deinterlaced[1]);
	const b0: R = @intCast(b_deinterlaced[0]);
	const b1: R = @intCast(b_deinterlaced[1]);
	return a0 *% b0 +% a1 *% b1;
}

fn crelu(v: anytype) switch (@typeInfo(@TypeOf(v))) {
	.vector => @TypeOf(v),
	else => @compileError("expected vector type, found " ++ @typeName(@TypeOf(v))),
} {
	const V = @TypeOf(v);
	const min: V = @splat(0);
	const max: V = @splat(arch.qa);
	return std.math.clamp(v, min, max);
}
