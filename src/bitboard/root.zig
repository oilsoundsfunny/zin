const std = @import("std");
const types = @import("types");

const jumping = @import("jumping.zig");
const sliding = @import("sliding.zig");

pub const rays = @import("rays.zig");

pub const nAtk = jumping.nAtk;
pub const kAtk = jumping.kAtk;

pub const bAtk = sliding.bAtk;
pub const rAtk = sliding.rAtk;

fn slidersRotate(n: comptime_int) @Vector(8, u6) {
    return .{
        @intCast(@mod(-types.Direction.northwest.int() * n, types.Square.num)),
        @intCast(@mod(-types.Direction.southwest.int() * n, types.Square.num)),
        @intCast(@mod(-types.Direction.southeast.int() * n, types.Square.num)),
        @intCast(@mod(-types.Direction.northeast.int() * n, types.Square.num)),
        @intCast(@mod(-types.Direction.north.int() * n, types.Square.num)),
        @intCast(@mod(-types.Direction.west.int() * n, types.Square.num)),
        @intCast(@mod(-types.Direction.south.int() * n, types.Square.num)),
        @intCast(@mod(-types.Direction.east.int() * n, types.Square.num)),
    };
}

fn rotl64x8(x: @Vector(8, u64), s: @Vector(8, u6)) @Vector(8, u64) {
    const shl = x >> @as(@Vector(8, u6), @splat(0)) -% s;
    const shr = x << s;
    return shl | shr;
}

pub fn deinit() void {}

pub fn init() !void {
    try jumping.init();
    try sliding.init();

    try rays.init();
}

pub fn pAtkEast(pawns: types.Square.Set, stm: types.Color) types.Square.Set {
    const dir = stm.forward().add(.east);
    const dst = types.File.file_a.toSet().flip();
    return pawns.shl(dir.int()).bwa(dst);
}

pub fn pAtkWest(pawns: types.Square.Set, stm: types.Color) types.Square.Set {
    const dir = stm.forward().add(.west);
    const dst = types.File.file_h.toSet().flip();
    return pawns.shl(dir.int()).bwa(dst);
}

pub fn pAtk(pawns: types.Square.Set, stm: types.Color) types.Square.Set {
    const ea = pAtkEast(pawns, stm);
    const wa = pAtkWest(pawns, stm);
    return types.Square.Set.bwo(ea, wa);
}

pub fn pPush1(pawns: types.Square.Set, occ: types.Square.Set, stm: types.Color) types.Square.Set {
    const dir = stm.forward();
    const dst = occ.flip();
    return pawns.shl(dir.int()).bwa(dst);
}

pub fn pPush2(pawns: types.Square.Set, occ: types.Square.Set, stm: types.Color) types.Square.Set {
    const home_pawns = pawns.bwa(stm.pawnRank().toSet());
    return pPush1(pPush1(home_pawns, occ, stm), occ, stm);
}

pub fn qAtk(s: types.Square, occ: types.Square.Set) types.Square.Set {
    const ba = bAtk(s, occ);
    const ra = rAtk(s, occ);
    return types.Square.Set.bwo(ba, ra);
}

pub fn ptAtk(pt: types.Ptype, s: types.Square, b: types.Square.Set) types.Square.Set {
    return switch (pt) {
        .knight => nAtk(s),
        .bishop => bAtk(s, b),
        .rook => rAtk(s, b),
        .queen => qAtk(s, b),
        .king => kAtk(s),
        else => std.debug.panic("unexpected enum value", .{}),
    };
}

// shamelessly stolen from pawnocchio
pub fn knightsAtk(b: types.Square.Set) types.Square.Set {
    const shifts: @Vector(8, u6) = .{
        @intCast(@mod(types.Direction.add(.northwest, .north).int(), types.Square.num)),
        @intCast(@mod(types.Direction.add(.northwest, .west).int(), types.Square.num)),
        @intCast(@mod(types.Direction.add(.southwest, .west).int(), types.Square.num)),
        @intCast(@mod(types.Direction.add(.southwest, .south).int(), types.Square.num)),
        @intCast(@mod(types.Direction.add(.southeast, .south).int(), types.Square.num)),
        @intCast(@mod(types.Direction.add(.southeast, .east).int(), types.Square.num)),
        @intCast(@mod(types.Direction.add(.northeast, .east).int(), types.Square.num)),
        @intCast(@mod(types.Direction.add(.northeast, .north).int(), types.Square.num)),
    };

    const masks: @Vector(8, u64) = .{
        types.Square.Set.bwo3(.rank_8, .file_a, .rank_7).flip().int(),
        types.Square.Set.bwo3(.rank_8, .file_a, .file_b).flip().int(),
        types.Square.Set.bwo3(.rank_1, .file_a, .file_b).flip().int(),
        types.Square.Set.bwo3(.rank_1, .file_a, .rank_2).flip().int(),
        types.Square.Set.bwo3(.rank_1, .file_h, .rank_2).flip().int(),
        types.Square.Set.bwo3(.rank_1, .file_h, .file_g).flip().int(),
        types.Square.Set.bwo3(.rank_8, .file_h, .file_g).flip().int(),
        types.Square.Set.bwo3(.rank_8, .file_h, .rank_7).flip().int(),
    };

    const splatted: @Vector(8, u64) = @splat(b.int());
    const rotated = rotl64x8(splatted & masks, shifts);
    return .fromInt(@reduce(.Or, rotated));
}

// do i have to switch to gpl
pub fn slidersAtk(
    diag: types.Square.Set,
    orth: types.Square.Set,
    occ: types.Square.Set,
) [2]types.Square.Set {
    const diag_lanes: @Vector(8, u64) = .{
        std.math.maxInt(u64), std.math.maxInt(u64), std.math.maxInt(u64), std.math.maxInt(u64),
        std.math.minInt(u64), std.math.minInt(u64), std.math.minInt(u64), std.math.minInt(u64),
    };
    const orth_lanes = ~diag_lanes;
    var generated: @Vector(8, u64) = .{
        diag.int(), diag.int(), diag.int(), diag.int(),
        orth.int(), orth.int(), orth.int(), orth.int(),
    };

    const edge_masks: @Vector(8, u64) = .{
        types.Square.Set.bwo(.rank_8, .file_a).int(),
        types.Square.Set.bwo(.rank_1, .file_a).int(),
        types.Square.Set.bwo(.rank_1, .file_h).int(),
        types.Square.Set.bwo(.rank_8, .file_h).int(),
        types.Square.Set.rank_8.int(),
        types.Square.Set.file_a.int(),
        types.Square.Set.rank_1.int(),
        types.Square.Set.file_h.int(),
    };
    var masked: @Vector(8, u64) = @splat(occ.int());
    masked |= edge_masks;

    inline for (0..3) |i| {
        const rot = 1 << i;
        generated |= rotl64x8(generated, slidersRotate(rot)) & ~masked;
        masked |= rotl64x8(masked, slidersRotate(rot));
    }

    generated = rotl64x8(generated, slidersRotate(1)) & ~edge_masks;
    return .{
        .fromInt(@reduce(.Or, generated & diag_lanes)),
        .fromInt(@reduce(.Or, generated & orth_lanes)),
    };
}
