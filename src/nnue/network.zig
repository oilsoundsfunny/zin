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
    .input_buckets = .{
        // zig fmt: off
         0,  1,  2,  3,
         4,  5,  6,  7,
         8,  9, 10, 11,
         8,  9, 10, 11,
        12, 12, 13, 13,
        12, 12, 13, 13,
        14, 14, 15, 15,
        14, 14, 15, 15,
        // zig fmt: on
    },
    .hl_size = 1024,
    .output_buckets = 8,
    .qa = 255,
    .qb = 64,
    .scale = 360,
});

pub const Options = struct {
    input_buckets: [types.Square.num / 2]u8,
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

        pub const buckets = blk: {
            const seq: [types.Square.num / 2]types.Square = .{
                // zig fmt: off
                .a1, .b1, .c1, .d1,
                .a2, .b2, .c2, .d2,
                .a3, .b3, .c3, .d3,
                .a4, .b4, .c4, .d4,
                .a5, .b5, .c5, .d5,
                .a6, .b6, .c6, .d6,
                .a7, .b7, .c7, .d7,
                .a8, .b8, .c8, .d8,
                // zig fmt: on
            };
            var a: std.EnumArray(types.Square, u8) = .initFill(ibn);
            for (seq, opts.input_buckets) |s, b| {
                a.set(s, b);
                a.set(s.flipFile(), b);
            }
            break :blk a;
        };

        pub const inp = types.Piece.num * types.Square.num;
        pub const ibn = std.mem.max(u8, opts.input_buckets[0..]) + 1;
        pub const l0s = switch (opts.hl_size % 32) {
            0 => opts.hl_size,
            else => @compileError("unsupported hl_size"),
        };
        pub const obn = switch (opts.output_buckets) {
            1, 8 => |n| n,
            else => @compileError("unsupported output_buckets"),
        };

        pub const qa = opts.qa;
        pub const qb = opts.qb;
        pub const scale = opts.scale;

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

            var ev: engine.evaluation.score.Int = 0;
            for (types.Color.values) |c| {
                const vec = vecs.get(c);
                const wgt = wgts.get(c);

                var l1: Madd = @splat(0);
                defer ev += @reduce(.Add, l1);

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

            ev = @divTrunc(ev, qa) + self.l1b[ob];
            ev = @divTrunc(ev * scale, qa * qb);
            return ev;
        }
    };
}
