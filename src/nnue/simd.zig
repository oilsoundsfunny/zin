const builtin = @import("builtin");
const std = @import("std");

const dwords = @min(std.simd.suggestVectorLength(u32) orelse 1, 8);

pub const has_avx2 = builtin.cpu.has(.x86, .avx2);
pub const bytes = dwords * @sizeOf(u32) / @sizeOf(u8);

pub fn Vec(comptime T: type) switch (T) {
    i8, u8, i16, u16, i32, u32 => type,
    else => @compileError("expected 8, 16 or 32-bit integer type, found " ++ @typeName(T)),
} {
    return struct {
        v: Inner,
        const Self = @This();

        pub const Inner = @Vector(len, T);
        pub const ConstSlice = []align(bytes) const T;
        pub const Slice = []align(bytes) T;

        pub const len = bytes * @sizeOf(u8) / @sizeOf(T);

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

        pub fn min(self: Self, other: Self) Self {
            return .{ .v = @min(self.v, other.v) };
        }

        pub fn max(self: Self, other: Self) Self {
            return .{ .v = @max(self.v, other.v) };
        }

        pub fn clamp(self: Self, l: Self, h: Self) Self {
            return self.min(h).max(l);
        }

        pub fn crelu(self: Self, one: T) Self {
            return self.clamp(.splat(0), .splat(one));
        }

        pub fn reduce(self: Self, comptime op: std.builtin.ReduceOp) T {
            return @reduce(op, self.v);
        }

        pub fn load(p: anytype) Self {
            return .{ .v = switch (@TypeOf(p)) {
                []align(bytes) const T => @bitCast(p[0..len].*),
                *const Inner => p.*,
                *const Self => p.v,
                else => |P| {
                    const msg = std.fmt.comptimePrint(
                        "expected {s} or {s} or {s}, found {s}",
                        .{
                            @typeName(ConstSlice),
                            @typeName(*const Inner),
                            @typeName(*const Self),
                            @typeName(P),
                        },
                    );
                    @compileError(msg);
                },
            } };
        }

        pub fn store(self: *const Self, p: anytype) void {
            switch (@TypeOf(p)) {
                []align(bytes) T => p[0..len].* = @bitCast(self.v),
                *Inner => p.* = self.v,
                *Self => p.* = self.*,
                else => |P| {
                    const msg = std.fmt.comptimePrint(
                        "expected {s} or {s} or {s}, found {s}",
                        .{ @typeName(Slice), @typeName(*Inner), @typeName(*Self), @typeName(P) },
                    );
                    @compileError(msg);
                },
            }
        }
    };
}

pub fn dpbusd(sum: Vec(i32), u: Vec(u8), i: Vec(i8)) Vec(i32) {
    const partial = maddubs(u, i);
    const dotprod = maddwd(partial, .splat(1));
    return sum.add(dotprod);
}

pub fn dpbusd2(s: Vec(i32), uv0: Vec(u8), iv0: Vec(i8), uv1: Vec(u8), iv1: Vec(i8)) Vec(i32) {
    const partials: [2]Vec(i16) = .{ maddubs(uv0, iv0), maddubs(uv1, iv1) };
    const ones: Vec(i16) = .splat(1);
    const dotprod = maddwd(.add(partials[0], partials[1]), ones);
    return s.add(dotprod);
}

pub fn maddubs(u: Vec(u8), i: Vec(i8)) Vec(i16) {
    return if (has_avx2) .{ .v = asm ("vpmaddubsw %[i], %[u], %[dst]"
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
    return if (has_avx2) .{ .v = asm ("vpmaddwd %[b], %[a], %[dst]"
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
    return if (has_avx2) .{ .v = asm ("vpmulhw %[b], %[a], %[dst]"
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
    return if (has_avx2) .{ .v = asm ("vpackuswb %[b], %[a], %[dst]"
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
