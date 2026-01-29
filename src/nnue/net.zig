const builtin = @import("builtin");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");
const arch = @import("arch.zig");

const Madd = @Vector(arch.native_len / 2, engine.evaluation.score.Int);

pub const Self = extern struct {
    hl0_w: [arch.inp_len][arch.hl0_len]arch.Int,
    hl0_b: [arch.hl0_len]arch.Int,

    out_w: [arch.out_len][arch.color_n][arch.hl0_len / 2]arch.Int,
    out_b: [arch.out_len]arch.Int align(64),

    pub fn infer(
        self: *const Self,
        accumulator: *const Accumulator,
        position: *const engine.Board.Position,
    ) engine.evaluation.score.Int {
        const stm = position.stm;
        const vecs = std.EnumArray(types.Color, *const [arch.hl0_len]arch.Int).init(.{
            .white = accumulator.perspectives.getPtrConst(stm),
            .black = accumulator.perspectives.getPtrConst(stm.flip()),
        });

        const bucket = blk: {
            // output bucket scheme used in alexandria
            const cnt: u32 = position.bothOcc().count();
            break :blk @min((63 - cnt) * (32 - cnt) / 225, arch.out_len - 1);
        };
        const wgts = std.EnumArray(types.Color, *const [arch.hl0_len / 2]arch.Int).init(.{
            .white = self.out_w[bucket][types.Color.white.int()][0..],
            .black = self.out_w[bucket][types.Color.black.int()][0..],
        });

        var out: Madd = @splat(engine.evaluation.score.draw);
        for (types.Color.values) |c| {
            const v = vecs.get(c);
            const w = wgts.get(c);

            var i: usize = 0;
            while (i < arch.hl0_len / 2) : (i += arch.native_len) {
                const v0: *const arch.Native =
                    @alignCast(v[i + arch.hl0_len / 2 * 0 ..][0..arch.native_len]);
                const v1: *const arch.Native =
                    @alignCast(v[i + arch.hl0_len / 2 * 1 ..][0..arch.native_len]);
                const wgt: *const arch.Native = @alignCast(w[i..][0..arch.native_len]);

                const crelu0 = crelu(v0.*);
                const crelu1 = crelu(v1.*);
                out +%= madd(crelu0, crelu1 *% wgt.*);
            }
        }

        var ev = @reduce(.Add, out);
        ev = @divTrunc(ev, arch.qa) + self.out_b[bucket];
        ev = @divTrunc(ev * arch.scale, arch.qa * arch.qb);
        return ev;
    }
};

pub const embed = init: {
    var net: Self align(std.atomic.cache_line) = undefined;
    const dst = std.mem.asBytes(&net);
    const src = @embedFile("embed.nn");

    if (dst.len != src.len) {
        const msg = std.fmt.comptimePrint(
            "mismatched size, expected {d}, found {d}",
            .{ dst.len, src.len },
        );
        @compileError(msg);
    }

    @memcpy(dst, src);
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
