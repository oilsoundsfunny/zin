const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const network = @import("network.zig");
const simd = @import("simd.zig");

const Accumulator = @This();

vec: [network.Default.l1s]i16 align(1024) = network.verbatim.l0b,

pub const Feature = struct {
    piece: types.Piece,
    square: types.Square,

    pub fn init(p: types.Piece, s: types.Square) Feature {
        return .{
            .piece = p,
            .square = s,
        };
    }

    pub fn transform(self: Feature, target: anytype) switch (@TypeOf(target)) {
        types.Square, types.Square.Set, Feature => |T| T,
        else => @compileError("unexpected type"),
    } {
        const pt = self.piece.ptype();
        const pc = self.piece.color();
        const hm = switch (self.square.file()) {
            .file_a, .file_b, .file_c, .file_d => false,
            else => true,
        };

        std.debug.assert(pt == .king);
        return if (@TypeOf(target) == Feature) blk: {
            const target_pt = target.piece.ptype();
            const target_pc = target.piece.color();
            break :blk .{
                .piece = .init(target_pt, if (target_pc == pc) .white else .black),
                .square = self.transform(target.square),
            };
        } else blk: {
            const ret = if (pc == .black) target.flipRank() else target;
            break :blk if (hm) ret.flipFile() else ret;
        };
    }

    pub fn bucket(self: Feature) usize {
        std.debug.assert(self.piece.ptype() == .king);
        return network.Default.buckets[self.transform(self.square).int()];
    }

    pub fn index(self: Feature) usize {
        const ci: usize = if (self.piece.color() == .white) 0 else types.Ptype.num;
        const pi: usize = self.piece.ptype().int();
        const si: usize = self.square.int();
        return (ci + pi) * types.Square.num + si;
    }
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
    wgts: *const [network.Default.inp][network.Default.l1s]i16,
    adds: *const types.BoundedArray(usize, null, 32),
    subs: *const types.BoundedArray(usize, null, 32),
) void {
    const Native = simd.Vec(i16).Inner;
    const native_len = simd.Vec(i16).len;

    const a: *[network.Default.l1s]i16 = &self.vec;
    var i: usize = 0;

    while (i < network.Default.l1s) : (i += native_len) {
        const vec: *Native = @alignCast(@ptrCast(a[i..][0..native_len]));
        var acc: Native = @splat(0);
        defer vec.* +%= acc;

        for (adds.constSlice()) |add_i| {
            const v: *const Native = @alignCast(@ptrCast(wgts[add_i][i..][0..native_len]));
            acc +%= v.*;
        }

        for (subs.constSlice()) |sub_i| {
            const v: *const Native = @alignCast(@ptrCast(wgts[sub_i][i..][0..native_len]));
            acc -%= v.*;
        }
    }
}
