const builtin = @import("builtin");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");
const simd = @import("simd.zig");
const sparse = @import("sparse.zig");

const Options = struct {
    input_buckets: [types.Square.num / 2]u8,
    output_buckets: usize,
    l1: usize,
    l2: usize,
    l3: usize,
    q0: Quantization,
    q1: Quantization,
    q: Quantization,
    scale: i16,

    const Quantization = struct {
        v: comptime_int,

        fn bits(self: Quantization) comptime_int {
            const v: comptime_float = self.v;
            return @ceil(@log2(v));
        }

        fn pow(self: Quantization, p: comptime_int) comptime_int {
            comptime var e = 1;
            for (0..p) |_| {
                e *= self.v;
            }
            return e;
        }
    };
};

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
    .output_buckets = 8,
    .l1 = 768,
    .l2 = 16,
    .l3 = 32,
    .q0 = .{ .v = 255 },
    .q1 = .{ .v = 128 },
    .q = .{ .v = 64 },
    .scale = 255,
});

const has_avx512vnni = builtin.cpu.has(.x86, .avx512vnni);
const has_avx512f = builtin.cpu.has(.x86, .avx512f);
const has_avx2 = builtin.cpu.has(.x86, .avx2);
const page_size = std.heap.pageSize();
const embedded align(@alignOf(Default)) = if (has_avx512f)
        @embedFile("avx512.nnue").*
    else if (has_avx2)
        @embedFile("avx2.nnue").*
    else
        @embedFile("scalar.nnue").*;

pub const verbatim = if (embedded.len == @sizeOf(Default))
    std.mem.bytesAsValue(Default, embedded[0..])
else {
    const msg = std.fmt.comptimePrint(
        "expected {} bytes, found {}",
        .{ @sizeOf(Default), embedded.len },
    );
    @compileError(msg);
};

pub fn Network(comptime opts: Options) type {
    return extern struct {
        l0w: [ibn][inp][l1s]i16,
        l0b: [l1s]i16,

        l1w: [obn][l1s / 4][l2s * 4]i8,
        l1b: [obn][l2s]i32,

        l2w: [obn][l2s * 2][l3s]i32,
        l2b: [obn][l3s]i32,

        l3w: [obn][l3s]i32,
        l3b: [obn]i32 align(64),

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
        pub const obn = switch (opts.output_buckets) {
            1, 8 => |n| n,
            else => @compileError("unsupported output_buckets"),
        };

        pub const l1s = opts.l1;
        pub const l2s = opts.l2;
        pub const l3s = opts.l3;

        pub const q0 = opts.q0;
        pub const q1 = opts.q1;
        pub const q = opts.q;

        pub const scale = opts.scale;

        fn outputBucket(pos: *const engine.Board.Position) usize {
            if (obn == 1) {
                return 0;
            }

            const occ = pos.bothOcc();
            const lhs = std.math.mulWide(u8, 63 - occ.count(), 32 - occ.count());
            return @min(lhs / 225, 7);
        }

        fn activateL1(
            self: *const Self,
            stm_inputs: *align(64) const [l1s]i16,
            ntm_inputs: *align(64) const [l1s]i16,
            l1: []align(page_size) u8,
        ) void {
            _ = self;
            const inputs: [types.Color.num][]align(64) const i16 = .{ stm_inputs, ntm_inputs };

            for (inputs, 0..) |input, which| {
                const half = l1s / 2;
                const offset = which * half;
                var i: usize = 0;

                while (i < half) : (i += simd.Vec(i8).len) {
                    const crelu = struct {
                        fn inner(v: simd.Vec(i16)) simd.Vec(i16) {
                            const lo: simd.Vec(i16) = .splat(0);
                            const hi: simd.Vec(i16) = .splat(q0.v);
                            return .clamp(v, lo, hi);
                        }
                    }.inner;
                    const shift = 16 - q0.bits();

                    const loads: [4]simd.Vec(i16) = .{
                        .load(input[half * 0 + i ..]),
                        .load(input[half * 1 + i ..]),
                        .load(input[half * 0 + i + simd.Vec(i16).len ..]),
                        .load(input[half * 1 + i + simd.Vec(i16).len ..]),
                    };
                    const prods: [2]simd.Vec(i16) = .{
                        simd.mulhi(crelu(loads[0]).shl(shift), crelu(loads[2])),
                        simd.mulhi(crelu(loads[1]).shl(shift), crelu(loads[3])),
                    };
                    simd.packus(prods[0], prods[1]).store(l1[offset + i ..]);
                }
            }
        }

        fn forwardL1(
            self: *const Self,
            ob: usize,
            l1: []align(page_size) const u8,
            l2: []align(page_size) i32,
        ) void {
            const unroll = @sizeOf(i32) / @sizeOf(u8);
            const stride = simd.Vec(i32).len * unroll;
            const acc_lanes = l2s / simd.Vec(i32).len;

            const l1_i32: []align(page_size) const i32 = @ptrCast(l1);
            const wgts: [*]align(64) const i8 = @ptrCast(&self.l1w[ob]);

            const nnz = sparse.findNonZeroes(l1);
            var acc: [acc_lanes][unroll]simd.Vec(i32) = @splat(@splat(.splat(0)));
            var i: usize = 0;

            while (i + unroll * 2 <= nnz.slice().len) : (i += unroll * 2) {
                for (acc[0..], 0..) |*rolled_lanes, j| {
                    const offset = j * stride;
                    for (rolled_lanes[0..], 0..) |*lane, k| {
                        const indices: [2]u16 = .{
                            nnz.slice()[i + k * 2],
                            nnz.slice()[i + k * 2 + 1],
                        };
                        const vs: [2]simd.Vec(u8) = .{
                            .bitCast(simd.Vec(i32).splat(l1_i32[indices[0]])),
                            .bitCast(simd.Vec(i32).splat(l1_i32[indices[1]])),
                        };
                        const ws: [2]simd.Vec(i8) = .{
                            .load(wgts[indices[0] * acc_lanes * stride + offset..]),
                            .load(wgts[indices[1] * acc_lanes * stride + offset..]),
                        };
                        lane.* = simd.dpbusd2(lane.*, vs[0], ws[0], vs[1], ws[1]);
                    }
                }
            } else while (i < nnz.slice().len) : (i += 1) {
                for (acc[0..], 0..) |*lane, j| {
                    const offset = j * stride;
                    const idx = nnz.slice()[i];
                    const v: simd.Vec(u8) = .bitCast(simd.Vec(i32).splat(l1_i32[idx]));
                    const w: simd.Vec(i8) = .load(wgts[idx * acc_lanes * stride + offset..]);
                    lane[0] = simd.dpbusd(lane[0], v, w);
                }
            }

            const out_vecs: []simd.Vec(i32) = @ptrCast(l2);
            for (acc[0..], 0..) |*lane, k| {
                var sum: simd.Vec(i32) = .splat(0);
                for (lane) |v| {
                    sum = sum.add(v);
                }

                const bias: simd.Vec(i32) = .load(self.l2b[ob][k * simd.Vec(i32).len ..]);
                const shifted = sum.add(bias).shr(q0.bits() * 2 - 9 + q1.bits() - q.bits());

                const lo: simd.Vec(i32) = .splat(0);
                const hi: simd.Vec(i32) = .splat(q.v);
                const hi_sq: simd.Vec(i32) = .splat(q.pow(2));
                const crelu = shifted.clamp(lo, hi).shl(q.bits());
                const csrelu = shifted.mul(shifted).clamp(lo, hi_sq);

                out_vecs[k] = crelu;
                out_vecs[k + acc_lanes] = csrelu;
            }
        }

        fn forwardL2(
            self: *const Self,
            ob: usize,
            l2: []align(page_size) const i32,
            l3: []align(page_size) i32,
        ) void {
            const acc: []simd.Vec(i32) = @ptrCast(l3);
            const wgts = &self.l2w[ob];
            const bias = &self.l2b[ob];
            for (acc[0..], 0..) |*lane, i| {
                lane.* = .load(bias[i * simd.Vec(i32).len..]);
            }

            for (l2, wgts) |scalar, *row| {
                for (acc[0..], 0..) |*lane, i| {
                    const offset = i * simd.Vec(i32).len;
                    const w: simd.Vec(i32) = .load(row[offset..]);
                    const v: simd.Vec(i32) = .splat(scalar);
                    lane.* = w.mul(v).add(lane.*);
                }
            }

            for (acc[0..]) |*lane| {
                const lo: simd.Vec(i32) = .splat(0);
                const hi: simd.Vec(i32) = .splat(q.pow(3));
                lane.* = lane.clamp(lo, hi);
            }
        }

        fn forwardL3(
            self: *const Self,
            ob: usize,
            l3: []align(page_size) const i32,
            out: *i64,
        ) void {
            const lanes: []align(page_size) const simd.Vec(i32) = @ptrCast(l3);
            var acc: simd.Vec(i32) = .splat(0);
            for (lanes, 0..) |v, i| {
                const offset = i * simd.Vec(i32).len;
                const w: simd.Vec(i32) = .load(self.l3w[ob][offset..]);
                acc = w.mul(v).add(acc);
            }

            out.* = acc.reduce(.Add) + self.l3b[ob];
            out.* = @divTrunc(out.* * scale, q.pow(4));
        }

        pub fn infer(
            self: *const Self,
            perspective: *const Accumulator.Perspective,
            position: *const engine.Board.Position,
        ) i32 {
            const stm = position.stm;
            const ntm = stm.flip();
            const stm_inputs = &perspective.accs.getPtrConst(stm).vec;
            const ntm_inputs = &perspective.accs.getPtrConst(ntm).vec;
            const ob = outputBucket(position);

            var l1: [l1s]u8 align(page_size) = @splat(0);
            var l2: [l2s * 2]i32 align(page_size) = @splat(0);
            var l3: [l3s]i32 align(page_size) = @splat(0);
            var out: i64 = 0;

            self.activateL1(stm_inputs, ntm_inputs, &l1);
            self.forwardL1(ob, &l1, &l2);
            self.forwardL2(ob, &l2, &l3);
            self.forwardL3(ob, &l3, &out);
            return @intCast(out);
        }
    };
}
