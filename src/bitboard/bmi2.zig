const std = @import("std");
const types = @import("types");

const utils = @import("utils.zig");

const Bmi = struct {
    ptr: [*]const u16,
    pdep_mask: types.Square.Set,
    pext_mask: types.Square.Set,
    pad: usize,
};

var b_atk: [0x00001480]u16 align(std.atomic.cache_line) = undefined;
var r_atk: [0x00019000]u16 align(std.atomic.cache_line) = undefined;

var b_tbl: std.EnumArray(types.Square, Bmi) align(std.atomic.cache_line) = .initUndefined();
var r_tbl: std.EnumArray(types.Square, Bmi) align(std.atomic.cache_line) = .initUndefined();

fn pdep(comptime T: type, src: T, mask: T) T {
    const instr = switch (T) {
        u32 => "pdepd",
        u64 => "pdepq",
        else => @compileError("expected u32 or u64, found " ++ @typeName(T)),
    };
    return asm (instr ++ " %[mask], %[src], %[dst]"
        : [dst] "=r" (-> T),
        : [mask] "r" (mask),
          [src] "r" (src),
    );
}

fn pext(comptime T: type, src: T, mask: T) T {
    const instr = switch (T) {
        u32 => "pextd",
        u64 => "pextq",
        else => @compileError("expected u32 or u64, found " ++ @typeName(T)),
    };
    return asm (instr ++ " %[mask], %[src], %[dst]"
        : [dst] "=r" (-> T),
        : [mask] "r" (mask),
          [src] "r" (src),
    );
}

fn bGenAtk(s: types.Square, b: types.Square.Set) types.Square.Set {
    return utils.genAtk(.bishop, s, b);
}

fn rGenAtk(s: types.Square, b: types.Square.Set) types.Square.Set {
    return utils.genAtk(.rook, s, b);
}

fn bGenIdx(s: types.Square, b: types.Square.Set) types.Square.Set.Int {
    const m = b_tbl.getPtrConst(s).pext_mask;
    return pext(u64, b.int(), m.int());
}

fn rGenIdx(s: types.Square, b: types.Square.Set) types.Square.Set.Int {
    const m = r_tbl.getPtrConst(s).pext_mask;
    return pext(u64, b.int(), m.int());
}

fn bAtkInit() !void {
    var offset: usize = 0;
    for (types.Square.values) |s| {
        const rank_edge = types.Square.Set
            .fromSlice(types.Rank, &.{ .rank_1, .rank_8 })
            .bwa(s.rank().toSet().flip());
        const file_edge = types.Square.Set
            .fromSlice(types.File, &.{ .file_a, .file_h })
            .bwa(s.file().toSet().flip());

        const edge = types.Square.Set.bwo(rank_edge, file_edge);
        const pdep_mask = bGenAtk(s, .none);
        const pext_mask = pdep_mask.bwa(edge.flip());

        const n = std.math.shl(usize, 1, pext_mask.count());
        const p = b_atk[offset..].ptr;
        b_tbl.set(s, .{
            .ptr = p,
            .pdep_mask = pdep_mask,
            .pext_mask = pext_mask,
            .pad = undefined,
        });
        offset += n;

        var b = types.Square.Set.none;
        for (0..n) |_| {
            const a = bGenAtk(s, b);
            const i = bGenIdx(s, b);

            p[i] = @truncate(pext(u64, a.int(), pdep_mask.int()));
            b = .fromInt(b.int() -% pext_mask.int());
            b = .fromInt(b.int() & pext_mask.int());
        }
    }
}

fn rAtkInit() !void {
    var offset: usize = 0;
    for (types.Square.values) |s| {
        const rank_edge = types.Square.Set
            .fromSlice(types.Rank, &.{ .rank_1, .rank_8 })
            .bwa(s.rank().toSet().flip());
        const file_edge = types.Square.Set
            .fromSlice(types.File, &.{ .file_a, .file_h })
            .bwa(s.file().toSet().flip());

        const edge = types.Square.Set.bwo(rank_edge, file_edge);
        const pdep_mask = rGenAtk(s, .none);
        const pext_mask = pdep_mask.bwa(edge.flip());

        const n = std.math.shl(usize, 1, pext_mask.count());
        const p = r_atk[offset..].ptr;
        r_tbl.set(s, .{
            .ptr = p,
            .pdep_mask = pdep_mask,
            .pext_mask = pext_mask,
            .pad = undefined,
        });
        offset += n;

        var b = types.Square.Set.none;
        for (0..n) |_| {
            const a = rGenAtk(s, b);
            const i = rGenIdx(s, b);

            p[i] = @truncate(pext(u64, a.int(), pdep_mask.int()));
            b = .fromInt(b.int() -% pext_mask.int());
            b = .fromInt(b.int() & pext_mask.int());
        }
    }
}

pub fn init() !void {
    try bAtkInit();
    try rAtkInit();
}

pub fn bAtk(s: types.Square, b: types.Square.Set) types.Square.Set {
    const i = bGenIdx(s, b);
    const x = b_tbl.getPtrConst(s).ptr[i];
    const m = b_tbl.getPtrConst(s).pdep_mask;
    return .fromInt(pdep(u64, x, m.int()));
}

pub fn rAtk(s: types.Square, b: types.Square.Set) types.Square.Set {
    const i = rGenIdx(s, b);
    const x = r_tbl.getPtrConst(s).ptr[i];
    const m = r_tbl.getPtrConst(s).pdep_mask;
    return .fromInt(pdep(u64, x, m.int()));
}
