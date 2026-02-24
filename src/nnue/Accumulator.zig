const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const network = @import("network.zig");

const Accumulator = @This();

vec: Vec = network.verbatim.l0b,

const Native = @Vector(native_len, i16);

const native_len = std.simd.suggestVectorLength(i16) orelse @compileError(":wilted_rose:");

pub const Vec = @Vector(network.Default.l0s, i16);

pub const Feature = struct {
    piece: types.Piece,
    square: types.Square,
};

pub const Perspective = struct {
    accs: std.EnumArray(types.Color, Accumulator) = .initFill(.{}),
    dirty: std.EnumArray(types.Color, bool) = .initFill(false),

    pub fn before(
        self: anytype,
        dist: usize,
    ) types.SameMutPtr(@TypeOf(self), *Perspective, *Perspective) {
        return &(self[0..1].ptr - dist)[0];
    }

    pub fn after(
        self: anytype,
        dist: usize,
    ) types.SameMutPtr(@TypeOf(self), *Perspective, *Perspective) {
        return &(self[0..1].ptr + dist)[0];
    }
};

pub fn update(
    self: *Accumulator,
    wgts: *const [network.Default.inp][network.Default.l0s]i16,
    opt_adds: ?*const types.BoundedArray(usize, null, 32),
    opt_subs: ?*const types.BoundedArray(usize, null, 32),
) void {
    const a: *[network.Default.l0s]i16 = &self.vec;
    var i: usize = 0;
    while (i < network.Default.l0s) : (i += native_len) {
        const vec: *Native = @alignCast(a[i..][0..native_len]);
        var acc: Native = @splat(0);
        defer vec.* +%= acc;

        if (opt_adds) |adds| {
            for (adds.constSlice()) |add_i| {
                const v: *const Native = @alignCast(wgts[add_i][i..][0..native_len]);
                acc +%= v.*;
            }
        }

        if (opt_subs) |subs| {
            for (subs.constSlice()) |sub_i| {
                const v: *const Native = @alignCast(wgts[sub_i][i..][0..native_len]);
                acc -%= v.*;
            }
        }
    }
}
