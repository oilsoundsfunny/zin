const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");

const Madd = @Vector(native_len / 2, i32);
const Native = @Vector(native_len, i16);

const embedded align(@alignOf(Default)) = @embedFile("embed.nnue").*;

const native_len = std.simd.suggestVectorLength(i16) orelse @compileError(":wilted_rose:");
const page_size = std.heap.pageSize();

pub const Default = Network(.{
    .input_buckets = .init(.{
        // zig fmt: off
        .a8 = 3, .b8 = 3, .c8 = 3, .d8 = 3, .e8 = 3, .f8 = 3, .g8 = 3, .h8 = 3,
        .a7 = 3, .b7 = 3, .c7 = 3, .d7 = 3, .e7 = 3, .f7 = 3, .g7 = 3, .h7 = 3,
        .a6 = 3, .b6 = 3, .c6 = 3, .d6 = 3, .e6 = 3, .f6 = 3, .g6 = 3, .h6 = 3,
        .a5 = 3, .b5 = 3, .c5 = 3, .d5 = 3, .e5 = 3, .f5 = 3, .g5 = 3, .h5 = 3,
        .a4 = 2, .b4 = 2, .c4 = 2, .d4 = 2, .e4 = 2, .f4 = 2, .g4 = 2, .h4 = 2,
        .a3 = 2, .b3 = 2, .c3 = 2, .d3 = 2, .e3 = 2, .f3 = 2, .g3 = 2, .h3 = 2,
        .a2 = 0, .b2 = 0, .c2 = 1, .d2 = 1, .e2 = 1, .f2 = 1, .g2 = 0, .h2 = 0,
        .a1 = 0, .b1 = 0, .c1 = 1, .d1 = 1, .e1 = 1, .f1 = 1, .g1 = 0, .h1 = 0,
        // zig fmt: on
    }),
    .hl_size = 512,
    .output_buckets = 8,
    .qa = 255,
    .qb = 64,
    .scale = 360,
});

pub const Options = struct {
    input_buckets: std.EnumArray(types.Square, usize),
    hl_size: usize,
    output_buckets: usize,
    qa: i16,
    qb: i16,
    scale: i16,
};

pub const verbatim = if (embedded.len == @sizeOf(Default))
    std.mem.bytesAsValue(Default, embedded[0..])
else {
    const msg = std.fmt.comptimePrint(
        "expected {} bytes, found {}",
        .{ @sizeOf(Default), embedded.len },
    );
    @compileError(msg);
};

fn clamp(a: Native, min: Native, max: Native) Native {
    return std.math.clamp(a, min, max);
}

fn madd(a: Native, b: Native) Madd {
    const ap = std.simd.deinterlace(2, a);
    const bp = std.simd.deinterlace(2, b);

    const ap0: Madd = ap[0];
    const ap1: Madd = ap[1];
    const bp0: Madd = bp[0];
    const bp1: Madd = bp[1];
    return ap0 *% bp0 +% ap1 *% bp1;
}

pub fn Network(comptime opts: Options) type {
    return extern struct {
        l0w: [ibn][inp][l0s]i16,
        l0b: [l0s]i16,

        l1w: [obn][l0s]i16,
        l1b: [obn]i16 align(64),

        const Self = @This();

        pub const buckets = opts.input_buckets;
        pub const inp = types.Piece.num * types.Square.num;
        pub const ibn = std.mem.max(usize, buckets.values[0..]) + 1;
        pub const l0s = if (opts.hl_size % 32 == 0)
            opts.hl_size
        else
            @compileError("unsupported hl_size");
        pub const obn = switch (opts.output_buckets) {
            1, 8 => |n| n,
            else => @compileError("unsupported output_buckets"),
        };

        pub const qa = 255;
        pub const qb = 64;
        pub const scale = 360;

        pub fn infer(
            self: *const Self,
            perspective: *const Accumulator.Perspective,
            position: *const engine.Board.Position,
        ) i32 {
            const stm = position.stm;
            const ntm = stm.flip();
            const vecs: std.EnumArray(types.Color, *const [l0s]i16) = .init(.{
                .white = &perspective.accs.getPtrConst(stm).vec,
                .black = &perspective.accs.getPtrConst(ntm).vec,
            });

            const ob = if (obn == 1) 0 else blk: {
                const n = position.bothOcc().count();
                const m = std.math.mulWide(u8, 63 - n, 32 - n);
                break :blk @min(m / 225, 7);
            };
            const wgts: std.EnumArray(types.Color, *const [l0s / 2]i16) = .init(.{
                .white = self.l1w[ob][l0s / 2 * 0 ..][0 .. l0s / 2],
                .black = self.l1w[ob][l0s / 2 * 1 ..][0 .. l0s / 2],
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

                    const crelu0 = clamp(v0.*, @splat(0), @splat(qa));
                    const crelu1 = clamp(v1.*, @splat(0), @splat(qa));
                    l1 +%= madd(crelu0, crelu1 *% w.*);
                }
            }

            var ev = @reduce(.Add, l1);
            ev = @divTrunc(ev, qa) + self.l1b[ob];
            ev = @divTrunc(ev * scale, qa * qb);
            return ev;
        }
    };
}
