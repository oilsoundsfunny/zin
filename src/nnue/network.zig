const builtin = @import("builtin");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");

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
            return @ceil(@log2(self.v));
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

fn vecLen(comptime T: type) comptime_int {
    return std.simd.suggestVectorLength(T) orelse switch (T) {
        i32, u32 => 1,
        else => vecLen(u32) * @sizeOf(u32) / @sizeOf(T),
    };
}

fn Vec(comptime T: type) type {
    return @Vector(vecLen(T), T);
}

fn maddubs(u: Vec(u8), i: Vec(i8)) Vec(i16) {
    return if (has_avx512f or has_avx2)
        asm (
            "vpmaddubsw %[i], %[u], %[dst]"
            : [dst] "=x" (-> Vec(i16)),
            : [i] "x" (i),
              [u] "x" (u),
        )
    else blk: {
        const u_ditl = std.simd.deinterlace(2, u);
        const i_ditl = std.simd.deinterlace(2, i);
        const prod0 = @as(Vec(i16), u_ditl[0]) * @as(Vec(i16), i_ditl[0]);
        const prod1 = @as(Vec(i16), u_ditl[1]) * @as(Vec(i16), i_ditl[1]);
        break :blk prod0 +| prod1;
    };
}

fn maddwd(a: Vec(i16), b: Vec(i16)) Vec(i32) {
    return if (has_avx512f or has_avx2)
        asm (
            "vpmaddwd %[b], %[a], %[dst]"
            : [dst] "=x" (-> Vec(i32)),
            : [a] "x" (a),
              [b] "x" (b),
        )
    else blk: {
        const a_ditl = std.simd.deinterlace(2, a);
        const b_ditl = std.simd.deinterlace(2, b);
        const prod0 = @as(Vec(i32), a_ditl[0]) * @as(Vec(i32), b_ditl[0]);
        const prod1 = @as(Vec(i32), a_ditl[1]) * @as(Vec(i32), b_ditl[1]);
        break :blk prod0 + prod1;
    };
}

fn mulhi(a: Vec(i16), b: Vec(i16)) Vec(i16) {
    return if (has_avx512f or has_avx2)
        asm (
            "vpmulhw %[b], %[a], %[dst]"
            : [dst] "=x" (-> Vec(i16)),
            : [a] "x" (a),
              [b] "x" (b),
        )
    else blk: {
        const mul = std.math.mulWide(a, b);
        const shr: @TypeOf(mul) = @splat(16);
        break :blk @intCast(mul >> shr);
    };
}

fn packus(a: Vec(i16), b: Vec(i16)) Vec(u8) {
    return if (has_avx512f or has_avx2)
        asm (
            "vpackuswb %[b], %[a], %[dst]"
            : [dst] "=x" (-> Vec(u8)),
            : [a] "x" (a),
              [b] "x" (b),
        )
    else blk: {
        const zeroes: Vec(i16) = @splat(0);
        const packed_a: @Vector(vecLen(i16), u8) = @intCast(@max(a, zeroes));
        const packed_b: @Vector(vecLen(i16), u8) = @intCast(@max(b, zeroes));
        const halves: [2]@Vector(vecLen(i16), u8) = .{ packed_a, packed_b };
        break :blk @bitCast(halves);
    };
}

fn dpbusd(u: Vec(u8), i: Vec(i8), s: Vec(i32)) Vec(i32) {
    return if (has_avx512vnni)
        asm (
            "vpdpbusd %[i], %[u], %[s]"
            : [s] "+x" (s),
            : [u] "x" (u),
              [i] "x" (i),
        )
    else blk: {
        const partial = maddubs(u, i);
        const ones: Vec(i16) = @splat(1);
        const dotprod = maddwd(partial, ones);
        break :blk s + dotprod;
    };
}

pub fn Network(comptime opts: Options) type {
    return extern struct {
        l0w: [ibn][inp][l1s]i16 align(64),
        l0b: [l1s]i16 align(64),

        l1w: [obn][l1s / 4][l2s * 4]i8 align(64),
        l1b: [obn][l2s]i32 align(64),

        l2w: [obn][l2s * 2][l3s]i32 align(64),
        l2b: [obn][l3s]i32 align(64),

        l3w: [obn][l3s]i32 align(64),
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

        pub const l1s = opts.l1s;
        pub const l2s = opts.l2s;
        pub const l3s = opts.l3s;

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
            l1: *align(64) [l1s]u8,
        ) void {
            const lo: Vec(i16) = @splat(0);
            const hi: Vec(i16) = @splat(q0.v);
            var i: usize = 0;

            _ = self;
            while (i < l1s / 2) : (i += vecLen(i8)) {
                var stm_loads: [4]Vec(i16) = .{
                    stm_inputs[i + l1s / 2 * 0..][0..vecLen(i16)].*,
                    stm_inputs[i + l1s / 2 * 1..][0..vecLen(i16)].*,
                    stm_inputs[i + l1s / 2 * 0 + vecLen(i16)..][0..vecLen(i16)].*,
                    stm_inputs[i + l1s / 2 * 1 + vecLen(i16)..][0..vecLen(i16)].*,
                };
                var ntm_loads: [4]Vec(i16) = .{
                    ntm_inputs[i + l1s / 2 * 0..][0..vecLen(i16)].*,
                    ntm_inputs[i + l1s / 2 * 1..][0..vecLen(i16)].*,
                    ntm_inputs[i + l1s / 2 * 0 + vecLen(i16)..][0..vecLen(i16)].*,
                    ntm_inputs[i + l1s / 2 * 1 + vecLen(i16)..][0..vecLen(i16)].*,
                };

                stm_loads[0] = std.math.clamp(stm_loads[0], lo, hi);
                stm_loads[2] = std.math.clamp(stm_loads[2], lo, hi);
                stm_loads[1] = @min(stm_loads[1], hi);
                stm_loads[3] = @min(stm_loads[3], hi);

                ntm_loads[0] = std.math.clamp(ntm_loads[0], lo, hi);
                ntm_loads[2] = std.math.clamp(ntm_loads[2], lo, hi);
                ntm_loads[1] = @min(ntm_loads[1], hi);
                ntm_loads[3] = @min(ntm_loads[3], hi);

                const stm_prods: [2]Vec(i16) = .{
                    mulhi(stm_loads[0] << @splat(7), stm_loads[1]),
                    mulhi(stm_loads[2] << @splat(7), stm_loads[3]),
                };
                const stm_part = packus(stm_prods[0], stm_prods[1]);

                const ntm_prods: [2]Vec(i16) = .{
                    mulhi(ntm_loads[0] << @splat(7), ntm_loads[1]),
                    mulhi(ntm_loads[2] << @splat(7), ntm_loads[3]),
                };
                const ntm_part = packus(ntm_prods[0], ntm_prods[1]);

                @as(*Vec(u8), @alignCast(l1[i + l1s / 2 * 0..][0..vecLen(u8)])).* = stm_part;
                @as(*Vec(u8), @alignCast(l1[i + l1s / 2 * 1..][0..vecLen(u8)])).* = ntm_part;
            }
        }

        fn forwardL1(
            self: *const Self,
            ob: usize,
            l1: *align(page_size) const [l1s]u8,
            l2: *align(page_size) [l2s]i32,
        ) void {
        }

        fn forwardL2(
            self: *const Self,
            ob: usize,
            l2: *align(page_size) const [l2s]i32,
            l3: *align(page_size) [l3s]i32,
        ) void {
        }

        fn forwardL3(
            self: *const Self,
            ob: usize,
            l3: *align(page_size) const [l3s]i32,
            out: *i32,
        ) void {
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
            var l2: [l2s]i32 align(page_size) = @splat(0);
            var l3: [l3s]i32 align(page_size) = @splat(0);
            var out: i32 = 0;

            self.activateL1(stm_inputs, ntm_inputs, &l1);
            self.forwardL1(ob, &l1, &l2);
            self.forwardL1(ob, &l2, &l3);
            self.forwardL1(ob, &l3, &out);
            return out;
        }
    };
}
