const std = @import("std");
const types = @import("types");

const simd = @import("simd.zig");

const nnz: [256]@Vector(8, u16) = blk: {
    @setEvalBranchQuota(5000);
    var a: [256][8]u16 = @splat(@splat(0));
    for (0..256) |i| {
        var j = i;
        var k = 0;
        while (j != 0) {
            a[i][k] = @ctz(j);
            j &= j - 1;
            k += 1;
        }
    }
    break :blk @bitCast(a);
};

fn nzMask(v: simd.Vec(u8)) std.meta.Int(.unsigned, simd.Vec(i32).len) {
    const v_i32: simd.Vec(i32) = .bitCast(v);
    const zeroes: simd.Vec(i32) = .splat(0);
    return @bitCast(v_i32.v != zeroes.v);
}

pub fn findNonZeroes(l1: []const u8) types.BoundedArray(u16, null, 512) {
    const unroll = @max(8 / simd.Vec(i32).len, 1);
    const chunks = unroll * simd.Vec(i32).len / 8;

    var indices: types.BoundedArray(u16, null, 512) = .{};
    var offset: @Vector(8, u16) = @splat(0);
    var i: usize = 0;

    while (i < l1.len) {
        var mask: u64 = 0;
        for (0..unroll) |k| {
            const nz_mask = nzMask(.load(l1[i..]));
            mask |= std.math.shr(u64, nz_mask, k * simd.Vec(i32).len);
            i += simd.Vec(u8).len;
        }

        for (0..chunks) |chunk| {
            const byte = std.math.shr(u64, mask, chunk * 8) % 256;
            const loaded = nnz[byte];
            indices.buffer[indices.len..][0..8].* = loaded + offset;
            _ = indices.addManyUnchecked(@popCount(byte));
            offset += @splat(8);
        }
    }

    return indices;
}
