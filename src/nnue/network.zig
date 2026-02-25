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
        .a8 = 0, .b8 = 0, .c8 = 0, .d8 = 0, .e8 = 0, .f8 = 0, .g8 = 0, .h8 = 0,
        .a7 = 0, .b7 = 0, .c7 = 0, .d7 = 0, .e7 = 0, .f7 = 0, .g7 = 0, .h7 = 0,
        .a6 = 0, .b6 = 0, .c6 = 0, .d6 = 0, .e6 = 0, .f6 = 0, .g6 = 0, .h6 = 0,
        .a5 = 0, .b5 = 0, .c5 = 0, .d5 = 0, .e5 = 0, .f5 = 0, .g5 = 0, .h5 = 0,
        .a4 = 0, .b4 = 0, .c4 = 0, .d4 = 0, .e4 = 0, .f4 = 0, .g4 = 0, .h4 = 0,
        .a3 = 0, .b3 = 0, .c3 = 0, .d3 = 0, .e3 = 0, .f3 = 0, .g3 = 0, .h3 = 0,
        .a2 = 0, .b2 = 0, .c2 = 0, .d2 = 0, .e2 = 0, .f2 = 0, .g2 = 0, .h2 = 0,
        .a1 = 0, .b1 = 0, .c1 = 0, .d1 = 0, .e1 = 0, .f1 = 0, .g1 = 0, .h1 = 0,
        // zig fmt: on
    }),
    .hl_size = 384,
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
