const base = @import("base");
const std = @import("std");

const misc = @import("misc.zig");
const genAtk = misc.genAtk;

const Int = misc.Set.Tag;

const b_magic = std.EnumArray(base.types.Square, Int).init(.{
	.a1 = 0x007fbfbfbfbfbfff, .b1 = 0x0000a060401007fc,
	.c1 = 0x0001004008020000, .d1 = 0x0000806004000000,
	.e1 = 0x0000100400000000, .f1 = 0x000021c100b20000,
	.g1 = 0x0000040041008000, .h1 = 0x00000fb0203fff80,
	.a2 = 0x0000040100401004, .b2 = 0x0000020080200802,
	.c2 = 0x0000004010202000, .d2 = 0x0000008060040000,
	.e2 = 0x0000004402000000, .f2 = 0x0000000801008000,
	.g2 = 0x000007efe0bfff80, .h2 = 0x0000000820820020,
	.a3 = 0x0000400080808080, .b3 = 0x00021f0100400808,
	.c3 = 0x00018000c06f3fff, .d3 = 0x0000258200801000,
	.e3 = 0x0000240080840000, .f3 = 0x000018000c03fff8,
	.g3 = 0x00000a5840208020, .h3 = 0x0000020008208020,
	.a4 = 0x0000804000810100, .b4 = 0x0001011900802008,
	.c4 = 0x0000804000810100, .d4 = 0x000100403c0403ff,
	.e4 = 0x00078402a8802000, .f4 = 0x0000101000804400,
	.g4 = 0x0000080800104100, .h4 = 0x00004004c0082008,
	.a5 = 0x0001010120008020, .b5 = 0x000080809a004010,
	.c5 = 0x0007fefe08810010, .d5 = 0x0003ff0f833fc080,
	.e5 = 0x007fe08019003042, .f5 = 0x003fffefea003000,
	.g5 = 0x0000101010002080, .h5 = 0x0000802005080804,
	.a6 = 0x0000808080a80040, .b6 = 0x0000104100200040,
	.c6 = 0x0003ffdf7f833fc0, .d6 = 0x0000008840450020,
	.e6 = 0x00007ffc80180030, .f6 = 0x007fffdd80140028,
	.g6 = 0x00020080200a0004, .h6 = 0x0000101010100020,
	.a7 = 0x0007ffdfc1805000, .b7 = 0x0003ffefe0c02200,
	.c7 = 0x0000000820806000, .d7 = 0x0000000008403000,
	.e7 = 0x0000000100202000, .f7 = 0x0000004040802000,
	.g7 = 0x0004010040100400, .h7 = 0x00006020601803f4,
	.a8 = 0x0003ffdfdfc28048, .b8 = 0x0000000820820020,
	.c8 = 0x0000000008208060, .d8 = 0x0000000000808020,
	.e8 = 0x0000000001002020, .f8 = 0x0000000401002008,
	.g8 = 0x0000004040404040, .h8 = 0x007fff9fdf7ff813,
});

const b_off = std.EnumArray(base.types.Square, u32).init(.{
	.a1 =  5378, .b1 =  4093, .c1 =  4314, .d1 =  6587,
	.e1 =  6491, .f1 =  6330, .g1 =  5609, .h1 = 22236,
	.a2 =  6106, .b2 =  5625, .c2 = 16785, .d2 = 16817,
	.e2 =  6842, .f2 =  7003, .g2 =  4197, .h2 =  7356,
	.a3 =  4602, .b3 =  4538, .c3 = 29531, .d3 = 45393,
	.e3 = 12420, .f3 = 15763, .g3 =  5050, .h3 =  4346,
	.a4 =  6074, .b4 =  7866, .c4 = 32139, .d4 = 57673,
	.e4 = 55365, .f4 = 15818, .g4 =  5562, .h4 =  6390,
	.a5 =  7930, .b5 = 13329, .c5 =  7170, .d5 = 27267,
	.e5 = 53787, .f5 =  5097, .g5 =  6643, .h5 =  6138,
	.a6 =  7418, .b6 =  7898, .c6 = 42012, .d6 = 57350,
	.e6 = 22813, .f6 = 56693, .g6 =  5818, .h6 =  7098,
	.a7 =  4451, .b7 =  4709, .c7 =  4794, .d7 = 13364,
	.e7 =  4570, .f7 =  4282, .g7 = 14964, .h7 =  4026,
	.a8 =  4826, .b8 =  7354, .c8 =  4848, .d8 = 15946,
	.e8 = 14932, .f8 = 16588, .g8 =  6905, .h8 = 16076,
});

const r_magic = std.EnumArray(base.types.Square, Int).init(.{
	.a1 = 0x00280077ffebfffe, .b1 = 0x2004010201097fff,
	.c1 = 0x0010020010053fff, .d1 = 0x0040040008004002,
	.e1 = 0x7fd00441ffffd003, .f1 = 0x4020008887dffffe,
	.g1 = 0x004000888847ffff, .h1 = 0x006800fbff75fffd,
	.a2 = 0x000028010113ffff, .b2 = 0x0020040201fcffff,
	.c2 = 0x007fe80042ffffe8, .d2 = 0x00001800217fffe8,
	.e2 = 0x00001800073fffe8, .f2 = 0x00001800e05fffe8,
	.g2 = 0x00001800602fffe8, .h2 = 0x000030002fffffa0,
	.a3 = 0x00300018010bffff, .b3 = 0x0003000c0085fffb,
	.c3 = 0x0004000802010008, .d3 = 0x0004002020020004,
	.e3 = 0x0001002002002001, .f3 = 0x0001001000801040,
	.g3 = 0x0000004040008001, .h3 = 0x0000006800cdfff4,
	.a4 = 0x0040200010080010, .b4 = 0x0000080010040010,
	.c4 = 0x0004010008020008, .d4 = 0x0000040020200200,
	.e4 = 0x0002008010100100, .f4 = 0x0000008020010020,
	.g4 = 0x0000008020200040, .h4 = 0x0000820020004020,
	.a5 = 0x00fffd1800300030, .b5 = 0x007fff7fbfd40020,
	.c5 = 0x003fffbd00180018, .d5 = 0x001fffde80180018,
	.e5 = 0x000fffe0bfe80018, .f5 = 0x0001000080202001,
	.g5 = 0x0003fffbff980180, .h5 = 0x0001fffdff9000e0,
	.a6 = 0x00fffefeebffd800, .b6 = 0x007ffff7ffc01400,
	.c6 = 0x003fffbfe4ffe800, .d6 = 0x001ffff01fc03000,
	.e6 = 0x000fffe7f8bfe800, .f6 = 0x0007ffdfdf3ff808,
	.g6 = 0x0003fff85fffa804, .h6 = 0x0001fffd75ffa802,
	.a7 = 0x00ffffd7ffebffd8, .b7 = 0x007fff75ff7fbfd8,
	.c7 = 0x003fff863fbf7fd8, .d7 = 0x001fffbfdfd7ffd8,
	.e7 = 0x000ffff810280028, .f7 = 0x0007ffd7f7feffd8,
	.g7 = 0x0003fffc0c480048, .h7 = 0x0001ffffafd7ffd8,
	.a8 = 0x00ffffe4ffdfa3ba, .b8 = 0x007fffef7ff3d3da,
	.c8 = 0x003fffbfdfeff7fa, .d8 = 0x001fffeff7fbfc22,
	.e8 = 0x0000020408001001, .f8 = 0x0007fffeffff77fd,
	.g8 = 0x0003ffffbf7dfeec, .h8 = 0x0001ffff9dffa333,
});

const r_off = std.EnumArray(base.types.Square, u32).init(.{
	.a1 = 26304, .b1 = 35520, .c1 = 38592, .d1 =  8026,
	.e1 = 22196, .f1 = 80870, .g1 = 76747, .h1 = 30400,
	.a2 = 11115, .b2 = 18205, .c2 = 53577, .d2 = 62724,
	.e2 = 34282, .f2 = 29196, .g2 = 23806, .h2 = 49481,
	.a3 =  2410, .b3 = 36498, .c3 = 24478, .d3 = 10074,
	.e3 = 79315, .f3 = 51779, .g3 = 13586, .h3 = 19323,
	.a4 = 70612, .b4 = 83652, .c4 = 63110, .d4 = 34496,
	.e4 = 84966, .f4 = 54341, .g4 = 60421, .h4 = 86402,
	.a5 = 50245, .b5 = 76622, .c5 = 84676, .d5 = 78757,
	.e5 = 37346, .f5 =   370, .g5 = 42182, .h5 = 45385,
	.a6 = 61659, .b6 = 12790, .c6 = 16762, .d6 =     0,
	.e6 = 38380, .f6 = 11098, .g6 = 21803, .h6 = 39189,
	.a7 = 58628, .b7 = 44116, .c7 = 78357, .d7 = 44481,
	.e7 = 64134, .f7 = 41759, .g7 =  1394, .h7 = 40910,
	.a8 = 66516, .b8 =  3897, .c8 =  3930, .d8 = 72934,
	.e8 = 72662, .f8 = 56325, .g8 = 66501, .h8 = 14826,
});

var b_masks = std.EnumArray(base.types.Square, misc.Set).initFill(.nul);
var b_ptr_tbl = std.EnumArray(base.types.Square, [*]misc.Set)
  .initFill(atk_tbl[0 ..].ptr);

var r_masks = std.EnumArray(base.types.Square, misc.Set).initFill(.nul);
var r_ptr_tbl = std.EnumArray(base.types.Square, [*]misc.Set)
  .initFill(atk_tbl[0 ..].ptr);

var atk_tbl = std.mem.zeroes([88772]misc.Set);

fn bIdx(s: base.types.Square, occ: misc.Set) Int {
	const magic = b_magic.getPtrConst(s).*;
	const amask = b_masks.getPtrConst(s).*;
	return std.math.shr(Int, occ.bwa(amask).tag() *% magic, 64 - 9);
}

fn rIdx(s: base.types.Square, occ: misc.Set) Int {
	const magic = r_magic.getPtrConst(s).*;
	const amask = r_masks.getPtrConst(s).*;
	return std.math.shr(Int, occ.bwa(amask).tag() *% magic, 64 - 12);
}

fn genIdx(comptime pt: base.types.Ptype, s: base.types.Square, occ: misc.Set) Int {
	return switch (pt) {
		.bishop => bIdx(s, occ),
		.rook   => rIdx(s, occ),
		else => @compileError("unexpected tag " ++ @tagName(pt)),
	};
}

pub fn prefetch() void {
	@prefetch(&b_magic, .{});
	@prefetch(&b_masks, .{});
	@prefetch(&b_ptr_tbl, .{});

	@prefetch(&r_magic, .{});
	@prefetch(&r_masks, .{});
	@prefetch(&r_ptr_tbl, .{});
}

pub fn bAtkInit() !void {
	for (base.types.Square.values) |s| {
		const rank_edge = misc.Set
		  .fromSlice(base.types.Rank, &.{.rank_1, .rank_8})
		  .bwa(s.rank().toSet().flip());
		const file_edge = misc.Set
		  .fromSlice(base.types.File, &.{.file_a, .file_h})
		  .bwa(s.file().toSet().flip());

		const edge = misc.Set.bwo(rank_edge, file_edge);
		const mask = genAtk(.bishop, s, .nul).bwa(edge.flip());

		const n = std.math.shl(usize, 1, mask.count());
		const p = atk_tbl[0 ..].ptr + b_off.getPtrConst(s).*;

		b_ptr_tbl.set(s, p);
		b_masks.set(s, mask);

		for (0 .. n) |i| {
			const occ = misc.permute(mask, i);
			const atk = genAtk(.bishop, s, occ);
			const idx = genIdx(.bishop, s, occ);

			p[idx] = atk;
		}
	}
}

pub fn rAtkInit() !void {
	for (base.types.Square.values) |s| {
		const rank_edge = misc.Set
		  .fromSlice(base.types.Rank, &.{.rank_1, .rank_8})
		  .bwa(s.rank().toSet().flip());
		const file_edge = misc.Set
		  .fromSlice(base.types.File, &.{.file_a, .file_h})
		  .bwa(s.file().toSet().flip());

		const edge = misc.Set.bwo(rank_edge, file_edge);
		const mask = genAtk(.rook, s, .nul).bwa(edge.flip());

		const n = std.math.shl(usize, 1, mask.count());
		const p = atk_tbl[0 ..].ptr + r_off.getPtrConst(s).*;

		r_ptr_tbl.set(s, p);
		r_masks.set(s, mask);

		for (0 .. n) |i| {
			const occ = misc.permute(mask, i);
			const atk = genAtk(.rook, s, occ);
			const idx = genIdx(.rook, s, occ);

			p[idx] = atk;
		}
	}
}

pub fn bAtk(s: base.types.Square, occ: misc.Set) misc.Set {
	const i = bIdx(s, occ);
	const p = b_ptr_tbl.getPtrConst(s).*;
	return p[i];
}

pub fn rAtk(s: base.types.Square, occ: misc.Set) misc.Set {
	const i = rIdx(s, occ);
	const p = r_ptr_tbl.getPtrConst(s).*;
	return p[i];
}
