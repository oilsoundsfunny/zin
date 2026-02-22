const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");

const Madd = @Vector(native_len / 2, i32);
const Native = @Vector(native_len, i16);

const native_len = std.simd.suggestVectorLength(i16) orelse @compileError(":wilted_rose:");
const page_size = std.heap.pageSize();

pub const Network = extern struct {
    l0w: [inp][l0s]i16,
    l0b: [l0s]i16,

    l1w: [l0s]i16,
    l1b: i16 align(64),

    const embedded align(@alignOf(Network)) = @embedFile("embed.nnue").*;

    // TODO: use these
    pub const ibn = 1;
    pub const obn = 1;

    pub const inp = types.Ptype.num * types.Color.num * types.Square.num;
    pub const l0s = 384;

    pub const scale = 360;
    pub const qa = 255;
    pub const qb = 64;

    pub const verbatim = if (@sizeOf(Network) != embedded.len) {
        const msg = std.fmt.comptimePrint(
            "expected {} bytes, found {}",
            .{ @sizeOf(Network), embedded.len },
        );
        @compileError(msg);
    } else std.mem.bytesAsValue(Network, embedded[0..]);

    pub fn infer(
        self: *const Network,
        accumulator: *const Accumulator,
        pos: *const engine.Board.Position,
    ) i32 {
        const stm = pos.stm;
        const vecs: std.EnumArray(types.Color, *const [l0s]i16) = .init(.{
            .white = accumulator.perspectives.getPtrConst(stm),
            .black = accumulator.perspectives.getPtrConst(stm.flip()),
        });

        const wgts: std.EnumArray(types.Color, *const [l0s / 2]i16) = .init(.{
            .white = self.l1w[0 * l0s / 2 ..][0..l0s / 2],
            .black = self.l1w[1 * l0s / 2 ..][0..l0s / 2],
        });

        var l1: Madd = @splat(0);
        for (types.Color.values) |c| {
            const vec = vecs.get(c);
            const wgt = wgts.get(c);
            var i: usize = 0;
            while (i < l0s / 2) : (i += native_len) {
                const v0: *const Native = @alignCast(vec[i + l0s / 2 * 0 ..][0..native_len]);
                const v1: *const Native = @alignCast(vec[i + l0s / 2 * 1 ..][0..native_len]);
                const w: *const Native = @alignCast(wgt[i..][0..native_len]);

                const crelu0 = crelu(v0.*);
                const crelu1 = crelu(v1.*);
                l1 +%= madd(crelu0, crelu1 *% w.*);
            }
        }

        var o = @reduce(.Add, l1);
        o = @divTrunc(o, qa) + self.l1b;
        o = @divTrunc(o * scale, qa * qb);
        return o;
    }
};

fn crelu(v: Native) Native {
    const min: Native = @splat(0);
    const max: Native = @splat(Network.qa);
    return std.math.clamp(v, min, max);
}

fn madd(a: Native, b: Native) Madd {
    const a_ditl = std.simd.deinterlace(2, a);
    const b_ditl = std.simd.deinterlace(2, b);

    const a0: Madd = a_ditl[0];
    const a1: Madd = a_ditl[1];
    const b0: Madd = b_ditl[0];
    const b1: Madd = b_ditl[1];
    return a0 *% b0 +% a1 *% b1;
}
