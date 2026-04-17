const builtin = @import("builtin");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");
const simd = @import("simd.zig");
const sparse = @import("sparse.zig");

const page_size = std.heap.pageSize();
const embedded align(page_size) = @embedFile("embed.nnue").*;

pub const verbatim = if (embedded.len == @sizeOf(Default))
    std.mem.bytesAsValue(Default, embedded[0..])
else {
    const msg = std.fmt.comptimePrint(
        "expected {} bytes, found {}",
        .{ @sizeOf(Default), embedded.len },
    );
    @compileError(msg);
};

pub const Default = extern struct {
    l0w: [ibn][inp][l1s]i16,
    l0b: [l1s]i16,

    l1w: [obn][l1s]i16,
    l1b: [obn]i16 align(64),

    const Self = @This();

    const qa = 255;
    const qb = 64;

    pub const scale = 255;

    pub const inp = types.Piece.num * types.Square.num;
    pub const buckets: [64]u8 = .{
        // zig fmt: off
         0,  1,  2,  3,  3,  2,  1,  0,
         4,  5,  6,  7,  7,  6,  5,  4,
         8,  9, 10, 11, 11, 10,  9,  8,
         8,  9, 10, 11, 11, 10,  9,  8,
        12, 12, 13, 13, 13, 13, 12, 12,
        12, 12, 13, 13, 13, 13, 12, 12,
        14, 14, 15, 15, 15, 15, 14, 14,
        14, 14, 15, 15, 15, 15, 14, 14,
        // zig fmt: on
    };

    pub const ibn = std.mem.max(u8, buckets[0..]) + 1;
    pub const obn = 8;
    pub const l1s = 1024;

    pub fn infer(
        self: *const Self,
        perspective: *const Accumulator.Perspective,
        position: *const engine.Board.Position,
    ) i32 {
        const stm = position.stm;
        const ntm = stm.flip();
        const vecs: std.EnumArray(types.Color, []align(simd.Vec(i16).bytes) const i16) = .init(.{
            .white = &perspective.accs.getPtrConst(stm).vec,
            .black = &perspective.accs.getPtrConst(ntm).vec,
        });

        const ob = switch (obn) {
            1, 8 => blk: {
                const n = position.bothOcc().count();
                const m = std.math.mulWide(u8, 63 - n, 32 - n);
                break :blk @min(m / 225, obn - 1);
            },
            else => {
                const msg = std.fmt.comptimePrint("unsupported no. output buckets {}", .{obn});
                @compileError(msg);
            },
        };
        const wgts: std.EnumArray(types.Color, []align(simd.Vec(i16).bytes) const i16) = .init(.{
            .white = @alignCast(self.l1w[ob][l1s / 2 * 0 ..]),
            .black = @alignCast(self.l1w[ob][l1s / 2 * 1 ..]),
        });

        var out: i32 = 0;
        for (types.Color.values) |c| {
            const vec = vecs.get(c);
            const wgt = wgts.get(c);
            var sum: simd.Vec(i32) = .splat(0);
            defer out += sum.reduce(.Add);

            var i: usize = 0;
            while (i < l1s / 2) : (i += simd.Vec(i16).len) {
                const w: []align(simd.Vec(i16).bytes) const i16 = @alignCast(wgt[i..]);
                const v0: @TypeOf(w) = @alignCast(vec[i + l1s / 2 * 0 ..]);
                const v1: @TypeOf(w) = @alignCast(vec[i + l1s / 2 * 1 ..]);
                const w_load = simd.Vec(i16).load(w);
                const crelu0 = simd.Vec(i16).load(v0).clamp(.splat(0), .splat(qa));
                const crelu1 = simd.Vec(i16).load(v1).clamp(.splat(0), .splat(qa));
                sum.v += simd.maddwd(crelu0, crelu1.mul(w_load)).v;
            }
        }

        out = @divTrunc(out, qa) + self.l1b[ob];
        out = @divTrunc(out * scale, qa * qb);
        return out;
    }
};
