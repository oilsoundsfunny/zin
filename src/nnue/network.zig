const builtin = @import("builtin");
const engine = @import("engine");
const options = @import("options");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");
const simd = @import("simd.zig");
const sparse = @import("sparse.zig");

const page_size = std.heap.pageSize();
const embedded align(page_size) =
    if (simd.has_avx2)
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

pub const Default = extern struct {
    l0w: [ibn][inp][l1s]i16,
    l0b: [l1s]i16,

    l1w: [obn][l1s / 4][l2s * 4]i8,
    l1b: [obn][l2s]i32,

    l2w: [obn][l2s * 2][l3s]i32,
    l2b: [obn][l3s]i32,

    l3w: [obn][l3s]i32,
    l3b: [obn]i32 align(64),

    const Self = @This();

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

    const qa: Quantization = .{ .v = 255 };
    const qb: Quantization = .{ .v = 128 };
    const q: Quantization = .{ .v = 64 };

    pub const scale = 400;

    pub const buckets = options.input_buckets;

    pub const inp = types.Piece.num * types.Square.num;
    pub const ibn = options.ibn;
    pub const obn = options.obn;

    pub const l1s = options.l1;
    pub const l2s = options.l2;
    pub const l3s = options.l3;

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
                        const hi: simd.Vec(i16) = .splat(qa.v);
                        return .clamp(v, lo, hi);
                    }
                }.inner;
                const shift = qa.bits() * 2 - 9;

                const loads: [4]simd.Vec(i16) = .{
                    .load(input[i + half * 0 ..]),
                    .load(input[i + half * 1 ..]),
                    .load(input[i + half * 0 + simd.Vec(i16).len ..]),
                    .load(input[i + half * 1 + simd.Vec(i16).len ..]),
                };
                const clamped: [4]simd.Vec(i16) = .{
                    crelu(loads[0]), crelu(loads[1]), crelu(loads[2]), crelu(loads[3]),
                };

                const prods: [2]simd.Vec(i16) = .{
                    simd.mulhi(clamped[0].shl(shift), clamped[1]),
                    simd.mulhi(clamped[2].shl(shift), clamped[3]),
                };
                const packus = simd.packus(prods[0], prods[1]);
                packus.store(l1[offset + i ..]);
            }
        }
    }

    fn forwardL1(
        self: *const Self,
        ob: usize,
        l1: []align(page_size) const u8,
        l2: []align(page_size) i32,
        l2_raw: []align(page_size) i32,
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
                        .load(wgts[indices[0] * acc_lanes * stride + offset ..]),
                        .load(wgts[indices[1] * acc_lanes * stride + offset ..]),
                    };
                    lane.* = simd.dpbusd2(lane.*, vs[0], ws[0], vs[1], ws[1]);
                }
            }
        } else while (i < nnz.slice().len) : (i += 1) {
            for (acc[0..], 0..) |*lane, j| {
                const offset = j * stride;
                const idx = nnz.slice()[i];
                const v: simd.Vec(u8) = .bitCast(simd.Vec(i32).splat(l1_i32[idx]));
                const w: simd.Vec(i8) = .load(wgts[idx * acc_lanes * stride + offset ..]);
                lane[0] = simd.dpbusd(lane[0], v, w);
            }
        }

        const out_vecs: []align(page_size) simd.Vec(i32) = @ptrCast(l2);
        const raw_vecs: []align(page_size) simd.Vec(i32) = @ptrCast(l2_raw);
        for (acc[0..], 0..) |*lane, k| {
            var sum: simd.Vec(i32) = .splat(0);
            for (lane) |v| {
                sum = sum.add(v);
            }

            const bias: simd.Vec(i32) = .load(self.l1b[ob][k * simd.Vec(i32).len ..]);
            const shifted = sum.add(bias).shr(qa.bits() * 2 - 9 + qb.bits() - q.bits());

            const lo: simd.Vec(i32) = .splat(0);
            const hi: simd.Vec(i32) = .splat(q.v);
            const hi_sq: simd.Vec(i32) = .splat(q.pow(2));
            const crelu = shifted.clamp(lo, hi).shl(q.bits());
            const csrelu = shifted.mul(shifted).clamp(lo, hi_sq);

            raw_vecs[k] = shifted.mul(hi_sq);
            out_vecs[k] = crelu;
            out_vecs[k + acc_lanes] = csrelu;
        }
    }

    fn forwardL2(
        self: *const Self,
        ob: usize,
        l2: []align(page_size) const i32,
        l2_raw: []align(page_size) const i32,
        l3: []align(page_size) i32,
    ) void {
        const acc: []align(page_size) simd.Vec(i32) = @ptrCast(l3);
        const wgts = &self.l2w[ob];
        const bias = &self.l2b[ob];
        for (acc[0..], 0..) |*lane, i| {
            lane.* = .load(bias[i * simd.Vec(i32).len ..]);
        }

        for (l2, wgts) |scalar, *row| {
            for (acc[0..], 0..) |*lane, i| {
                const offset = i * simd.Vec(i32).len;
                const w: simd.Vec(i32) = .load(row[offset..]);
                const v: simd.Vec(i32) = .splat(scalar);
                lane.* = w.mul(v).add(lane.*);
            }
        }

        const raw: []align(page_size) const simd.Vec(i32) = @ptrCast(l2_raw);
        var i: usize = 0;
        while (i < l2.len / l2_raw.len) : (i += 1) {
            for (acc[i * raw.len ..][0..raw.len], raw) |*lane, input| {
                const lo: simd.Vec(i32) = .splat(0);
                const hi: simd.Vec(i32) = .splat(q.pow(3));
                lane.* = lane.clamp(lo, hi).add(input);
            }
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
        const ob = switch (obn) {
            1 => 0,
            8 => blk: {
                const n = position.bothOcc().count();
                const m = std.math.mulWide(u8, 63 - n, 32 - n);
                break :blk @min(m / 225, 7);
            },
            else => {
                const msg = std.fmt.comptimePrint("unsupported no. output buckets {}", .{obn});
                @compileError(msg);
            },
        };

        var l1: [l1s]u8 align(page_size) = @splat(0);
        var l2_raw: [l2s]i32 align(page_size) = @splat(0);
        var l2: [2 * l2s]i32 align(page_size) = @splat(0);
        var l3: [l3s]i32 align(page_size) = @splat(0);
        var out: i64 = 0;

        self.activateL1(stm_inputs, ntm_inputs, &l1);
        self.forwardL1(ob, &l1, &l2, &l2_raw);
        self.forwardL2(ob, &l2, &l2_raw, &l3);
        self.forwardL3(ob, &l3, &out);
        return @intCast(out);
    }
};
