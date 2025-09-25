const base = @import("base");
const std = @import("std");

const misc = @import("misc.zig");
const genAtk = misc.genAtk;

var b_atk_tbl = std.mem.zeroes([0x00001480]u16);
var b_ptr_tbl = std.EnumArray(base.types.Square, [*]u16).initFill(b_atk_tbl[0 ..].ptr);
var b_pdep = std.EnumArray(base.types.Square, misc.Set.Tag).initFill(0);
var b_pext = std.EnumArray(base.types.Square, misc.Set.Tag).initFill(0);

var r_atk_tbl = std.mem.zeroes([0x00019000]u16);
var r_ptr_tbl = std.EnumArray(base.types.Square, [*]u16).initFill(r_atk_tbl[0 ..].ptr);
var r_pdep = std.EnumArray(base.types.Square, misc.Set.Tag).initFill(0);
var r_pext = std.EnumArray(base.types.Square, misc.Set.Tag).initFill(0);

fn genIdx(comptime pt: base.types.Ptype,
  s: base.types.Square,
  o: misc.Set) misc.Set.Tag {
	return switch (pt) {
		.bishop => bIdx(s, o),
		.rook   => rIdx(s, o),
		else => @compileError("unexpected tag " ++ @tagName(pt)),
	};
}

fn pdep(comptime T: type, src: T, mask: T) T {
	const inst = switch (T) {
		u32 => "pdepd",
		u64 => "pdepq",
		else => @compileError("unexpected type " ++ @typeName(T)),
	};
	return asm (
		inst ++ " %[mask], %[src], %[dst]"
		: [dst] "=r" (-> T),
		: [src]  "r" (src),
		  [mask] "r" (mask),
	);
}

fn pext(comptime T: type, src: T, mask: T) T {
	const inst = switch (T) {
		u32 => "pextd",
		u64 => "pextq",
		else => @compileError("unexpected type " ++ @typeName(T)),
	};
	return asm (
		inst ++ " %[mask], %[src], %[dst]"
		: [dst] "=r" (-> T),
		: [src]  "r" (src),
		  [mask] "r" (mask),
	);
}

fn bIdx(s: base.types.Square, occ: misc.Set) misc.Set.Tag {
	const m = b_pext.getPtrConst(s).*;
	return pext(misc.Set.Tag, occ.tag(), m);
}

fn rIdx(s: base.types.Square, occ: misc.Set) misc.Set.Tag {
	const m = r_pext.getPtrConst(s).*;
	return pext(misc.Set.Tag, occ.tag(), m);
}

pub fn prefetch() void {
	@prefetch(&b_atk_tbl, .{});
	@prefetch(&b_ptr_tbl, .{});
	@prefetch(&b_pdep, .{});
	@prefetch(&b_pext, .{});

	@prefetch(&r_atk_tbl, .{});
	@prefetch(&r_ptr_tbl, .{});
	@prefetch(&r_pdep, .{});
	@prefetch(&r_pext, .{});

	@prefetch(&bAtk, .{.cache = .instruction});
	@prefetch(&rAtk, .{.cache = .instruction});
}

pub fn bAtkInit() !void {
	var p = b_atk_tbl[0 ..].ptr;
	for (base.types.Square.values) |s| {
		const rank_edge = misc.Set
		  .fromSlice(base.types.Rank, &.{.rank_1, .rank_8})
		  .bwa(s.rank().toSet().flip());
		const file_edge = misc.Set
		  .fromSlice(base.types.File, &.{.file_a, .file_h})
		  .bwa(s.file().toSet().flip());
		const edge = misc.Set.bwo(rank_edge, file_edge);

		const pdep_mask = genAtk(.bishop, s, .nul);
		const pext_mask = pdep_mask.bwa(edge.flip());

		b_ptr_tbl.set(s, p);
		b_pdep.set(s, pdep_mask.tag());
		b_pext.set(s, pext_mask.tag());

		const n = std.math.shl(usize, 1, pext_mask.count());
		for (0 .. n) |i| {
			const occ = misc.permute(pext_mask, i);
			const atk = genAtk(.bishop, s, occ).tag();
			const idx = genIdx(.bishop, s, occ);
			const ptr = b_ptr_tbl.getPtrConst(s).*;

			ptr[idx] = @intCast(pext(@TypeOf(atk), atk, pdep_mask.tag()));
			p += 1;
		}
	}
}

pub fn rAtkInit() !void {
	var p = r_atk_tbl[0 ..].ptr;
	for (base.types.Square.values) |s| {
		const rank_edge = misc.Set
		  .fromSlice(base.types.Rank, &.{.rank_1, .rank_8})
		  .bwa(s.rank().toSet().flip());
		const file_edge = misc.Set
		  .fromSlice(base.types.File, &.{.file_a, .file_h})
		  .bwa(s.file().toSet().flip());
		const edge = misc.Set.bwo(rank_edge, file_edge);

		const pdep_mask = genAtk(.rook, s, .nul);
		const pext_mask = pdep_mask.bwa(edge.flip());

		r_ptr_tbl.set(s, p);
		r_pdep.set(s, pdep_mask.tag());
		r_pext.set(s, pext_mask.tag());

		const n = std.math.shl(usize, 1, pext_mask.count());
		for (0 .. n) |i| {
			const occ = misc.permute(pext_mask, i);
			const atk = genAtk(.rook, s, occ).tag();
			const idx = genIdx(.rook, s, occ);
			const ptr = r_ptr_tbl.getPtrConst(s).*;

			ptr[idx] = @intCast(pext(@TypeOf(atk), atk, pdep_mask.tag()));
			p += 1;
		}
	}
}

pub fn bAtk(s: base.types.Square, occ: misc.Set) misc.Set {
	const i = bIdx(s, occ);
	const m = b_pdep.getPtrConst(s).*;
	const p = b_ptr_tbl.getPtrConst(s).*;

	const tag = pdep(@TypeOf(m), p[i], m);
	return misc.Set.fromTag(tag);
}

pub fn rAtk(s: base.types.Square, occ: misc.Set) misc.Set {
	const i = rIdx(s, occ);
	const m = r_pdep.getPtrConst(s).*;
	const p = r_ptr_tbl.getPtrConst(s).*;

	const tag = pdep(@TypeOf(m), p[i], m);
	return misc.Set.fromTag(tag);
}
