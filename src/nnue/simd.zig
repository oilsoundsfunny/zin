const builtin = @import("builtin");
const std = @import("std");

const has_avx2 = builtin.cpu.has(.x86, .avx2);
const has_avx512f = builtin.cpu.has(.x86, .avx512f);
const has_avx512vnni = builtin.cpu.has(.x86, .avx512vnni);

comptime {
    std.debug.assert(Vec(i32).len * 2 == Vec(i16).len);
    std.debug.assert(Vec(i16).len * 2 == Vec(i8).len);

    std.debug.assert(Vec(u32).len * 2 == Vec(u16).len);
    std.debug.assert(Vec(u16).len * 2 == Vec(u8).len);
}

pub fn Vec(comptime T: type) switch (T) {
    i8, u8, i16, u16, i32, u32 => type,
    else => @compileError("unsupported type"),
} {
    return struct {
        v: Inner,
        const Self = @This();

        const alignment = @alignOf(Inner);
        const dwords = std.simd.suggestVectorLength(u32) orelse
            @compileError("cpu doesn't support vectors with 32bit elements");

        pub const Inner = @Vector(len, T);
        pub const len = dwords * @sizeOf(u32) / @sizeOf(T);

        pub fn bitCast(vec: anytype) Self {
            if (@bitSizeOf(@TypeOf(vec.v)) != @bitSizeOf(Inner)) {
                const msg = std.fmt.comptimePrint(
                    "expected {}bit vector type, found {s}",
                    .{ @bitSizeOf(Inner), @typeName(@TypeOf(vec.v)) },
                );
                @compileError(msg);
            }

            return .{ .v = @bitCast(vec.v) };
        }

        pub fn splat(i: T) Self {
            return .{ .v = @splat(i) };
        }

        pub fn add(self: Self, other: Self) Self {
            return .{ .v = self.v + other.v };
        }

        pub fn sub(self: Self, other: Self) Self {
            return .{ .v = self.v - other.v };
        }

        pub fn mul(self: Self, other: Self) Self {
            return .{ .v = self.v * other.v };
        }

        pub fn shl(self: Self, amt: anytype) Self {
            return switch (@TypeOf(amt)) {
                comptime_int, T => .{ .v = self.v << @splat(amt) },
                Inner => .{ .v = self.v << amt },
                else => |A| {
                    const msg = std.fmt.comptimePrint(
                        "expected {s} or {s}, found {s}",
                        .{ @typeName(T), @typeName(Inner), @typeName(A) },
                    );
                    @compileError(msg);
                },
            };
        }

        pub fn shr(self: Self, amt: anytype) Self {
            return switch (@TypeOf(amt)) {
                comptime_int, T => .{ .v = self.v >> @splat(amt) },
                Inner => .{ .v = self.v >> amt },
                else => |A| {
                    const msg = std.fmt.comptimePrint(
                        "expected {s} or {s}, found {s}",
                        .{ @typeName(T), @typeName(Inner), @typeName(A) },
                    );
                    @compileError(msg);
                },
            };
        }

        pub fn clamp(self: Self, l: Self, h: Self) Self {
            return .{ .v = std.math.clamp(self.v, l.v, h.v) };
        }

        pub fn reduce(self: Self, comptime op: std.builtin.ReduceOp) T {
            return @reduce(op, self.v);
        }

        pub fn load(ptr: anytype) Self {
            const p: *const Inner = switch (@TypeOf(ptr)) {
                [*]const T, []const T => @alignCast(ptr[0..len]),
                *const Inner => ptr,
                else => |P| {
                    const msg = std.fmt.comptimePrint(
                        "expected slice of {s}s or ref to {s}, found {s}",
                        .{ @typeName(T), @typeName(Inner), @typeName(P) },
                    );
                    @compileError(msg);
                },
            };
            return .{ .v = p.* };
        }

        pub fn store(self: *const Self, ptr: anytype) void {
            const p: *Inner = switch (@TypeOf(ptr)) {
                [*]T, []T => @alignCast(ptr[0..len]),
                *Inner => ptr,
                else => |P| {
                    const msg = std.fmt.comptimePrint(
                        "expected slice of mut {s}s or mut ref to {s}, found {s}",
                        .{ @typeName(T), @typeName(Inner), @typeName(P) },
                    );
                    @compileError(msg);
                },
            };
            p.* = self.v;
        }
    };
}

pub fn dpbusd(s: Vec(i32), u: Vec(u8), i: Vec(i8)) Vec(i32) {
    return if (has_avx512vnni) .{ .v = asm ("vpdpbusd %[i], %[u], %[s]"
        : [s] "+x" (-> Vec(i32).Inner),
        : [u] "x" (u.v),
          [i] "x" (i.v),
    ) } else blk: {
        const partial = maddubs(u, i);
        const dotprod = maddwd(partial, .splat(1));
        break :blk .add(s, dotprod);
    };
}

pub fn dpbusd2(s: Vec(i32), uv0: Vec(u8), iv0: Vec(i8), uv1: Vec(u8), iv1: Vec(i8)) Vec(i32) {
    return dpbusd(dpbusd(s, uv0, iv0), uv1, iv1);
}

pub fn maddubs(u: Vec(u8), i: Vec(i8)) Vec(i16) {
    return if (has_avx512f or has_avx2) .{ .v = asm ("vpmaddubsw %[i], %[u], %[dst]"
        : [dst] "=x" (-> Vec(i16).Inner),
        : [i] "x" (i.v),
          [u] "x" (u.v),
    ) } else blk: {
        const u_ditl = std.simd.deinterlace(2, u.v);
        const i_ditl = std.simd.deinterlace(2, i.v);
        const prod0 = @as(Vec(i16).Inner, u_ditl[0]) * @as(Vec(i16).Inner, i_ditl[0]);
        const prod1 = @as(Vec(i16).Inner, u_ditl[1]) * @as(Vec(i16).Inner, i_ditl[1]);
        break :blk .{ .v = prod0 +| prod1 };
    };
}

pub fn maddwd(a: Vec(i16), b: Vec(i16)) Vec(i32) {
    return if (has_avx512f or has_avx2) .{ .v = asm ("vpmaddwd %[b], %[a], %[dst]"
        : [dst] "=x" (-> Vec(i32).Inner),
        : [a] "x" (a.v),
          [b] "x" (b.v),
    ) } else blk: {
        const a_ditl = std.simd.deinterlace(2, a.v);
        const b_ditl = std.simd.deinterlace(2, b.v);
        const prod0 = @as(Vec(i32).Inner, a_ditl[0]) * @as(Vec(i32).Inner, b_ditl[0]);
        const prod1 = @as(Vec(i32).Inner, a_ditl[1]) * @as(Vec(i32).Inner, b_ditl[1]);
        break :blk .{ .v = prod0 + prod1 };
    };
}

pub fn mulhi(a: Vec(i16), b: Vec(i16)) Vec(i16) {
    return if (has_avx512f or has_avx2) .{ .v = asm ("vpmulhw %[b], %[a], %[dst]"
        : [dst] "=x" (-> Vec(i16).Inner),
        : [a] "x" (a.v),
          [b] "x" (b.v),
    ) } else blk: {
        const Wide = @Vector(Vec(i16).len, i32);
        const mul = @as(Wide, a.v) * @as(Wide, b.v);
        break :blk .{ .v = @intCast(mul >> @splat(16)) };
    };
}

pub fn packus(a: Vec(i16), b: Vec(i16)) Vec(u8) {
    return if (has_avx512f or has_avx2) .{ .v = asm ("vpackuswb %[b], %[a], %[dst]"
        : [dst] "=x" (-> Vec(u8).Inner),
        : [a] "x" (a.v),
          [b] "x" (b.v),
    ) } else blk: {
        const zeroes: Vec(i16) = .splat(0);
        const packed_a: @Vector(Vec(i16).len, u8) = @intCast(@max(a.v, zeroes.v));
        const packed_b: @Vector(Vec(i16).len, u8) = @intCast(@max(b.v, zeroes.v));
        const halves: [2]@Vector(Vec(i16).len, u8) = .{ packed_a, packed_b };
        break :blk .{ .v = @bitCast(halves) };
    };
}
