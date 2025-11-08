const std = @import("std");
const types = @import("types");

const misc = @import("misc.zig");

const Magic = struct {
	pad:	usize,
	ptr:	[*]const types.Square.Set,
	magic:	types.Square.Set.Tag,
	nmask:	types.Square.Set,
};

const b_magic = std.EnumArray(types.Square, types.Square.Set.Tag).init(.{
	.a1 = 0xa7020080601803d8, .b1 = 0x13802040400801f1,
	.c1 = 0x0a0080181001f60c, .d1 = 0x1840802004238008,
	.e1 = 0xc03fe00100000000, .f1 = 0x24c00bffff400000,
	.g1 = 0x0808101f40007f04, .h1 = 0x100808201ec00080,
	.a2 = 0xffa2feffbfefb7ff, .b2 = 0x083e3ee040080801,
	.c2 = 0xc0800080181001f8, .d2 = 0x0440007fe0031000,
	.e2 = 0x2010007ffc000000, .f2 = 0x1079ffe000ff8000,
	.g2 = 0x3c0708101f400080, .h2 = 0x080614080fa00040,
	.a3 = 0x7ffe7fff817fcff9, .b3 = 0x7ffebfffa01027fd,
	.c3 = 0x53018080c00f4001, .d3 = 0x407e0001000ffb8a,
	.e3 = 0x201fe000fff80010, .f3 = 0xffdfefffde39ffef,
	.g3 = 0xcc8808000fbf8002, .h3 = 0x7ff7fbfff8203fff,
	.a4 = 0x8800013e8300c030, .b4 = 0x0420009701806018,
	.c4 = 0x7ffeff7f7f01f7fd, .d4 = 0x8700303010c0c006,
	.e4 = 0xc800181810606000, .f4 = 0x20002038001c8010,
	.g4 = 0x087ff038000fc001, .h4 = 0x00080c0c00083007,
	.a5 = 0x00000080fc82c040, .b5 = 0x000000407e416020,
	.c5 = 0x00600203f8008020, .d5 = 0xd003fefe04404080,
	.e5 = 0xa00020c018003088, .f5 = 0x7fbffe700bffe800,
	.g5 = 0x107ff00fe4000f90, .h5 = 0x7f8fffcff1d007f8,
	.a6 = 0x0000004100f88080, .b6 = 0x00000020807c4040,
	.c6 = 0x00000041018700c0, .d6 = 0x0010000080fc4080,
	.e6 = 0x1000003c80180030, .f6 = 0xc10000df80280050,
	.g6 = 0xffffffbfeff80fdc, .h6 = 0x000000101003f812,
	.a7 = 0x0800001f40808200, .b7 = 0x084000101f3fd208,
	.c7 = 0x080000000f808081, .d7 = 0x0004000008003f80,
	.e7 = 0x08000001001fe040, .f7 = 0x72dd000040900a00,
	.g7 = 0xfffffeffbfeff81d, .h7 = 0xcd8000200febf209,
	.a8 = 0x100000101ec10082, .b8 = 0x7fbaffffefe0c02f,
	.c8 = 0x7f83fffffff07f7f, .d8 = 0xfff1fffffff7ffc1,
	.e8 = 0x0878040000ffe01f, .f8 = 0x945e388000801012,
	.g8 = 0x0840800080200fda, .h8 = 0x100000c05f582008,
});

const b_offset = std.EnumArray(types.Square, u32).init(.{
	.a1 = 60984, .b1 = 66046, .c1 = 32910, .d1 = 16369,
	.e1 = 42115, .f1 =   835, .g1 = 18910, .h1 = 25911,
	.a2 = 63301, .b2 = 16063, .c2 = 17481, .d2 = 59361,
	.e2 = 18735, .f2 = 61249, .g2 = 68938, .h2 = 61791,
	.a3 = 21893, .b3 = 62068, .c3 = 19829, .d3 = 26091,
	.e3 = 15815, .f3 = 16419, .g3 = 59777, .h3 = 16288,
	.a4 = 33235, .b4 = 15459, .c4 = 15863, .d4 = 75555,
	.e4 = 79445, .f4 = 15917, .g4 =  8512, .h4 = 73069,
	.a5 = 16078, .b5 = 19168, .c5 = 11056, .d5 = 62544,
	.e5 = 80477, .f5 = 75049, .g5 = 32947, .h5 = 59172,
	.a6 = 55845, .b6 = 61806, .c6 = 73601, .d6 = 15546,
	.e6 = 45243, .f6 = 20333, .g6 = 33402, .h6 = 25917,
	.a7 = 32875, .b7 =  4639, .c7 = 17077, .d7 = 62324,
	.e7 = 18159, .f7 = 61436, .g7 = 57073, .h7 = 61025,
	.a8 = 81259, .b8 = 64083, .c8 = 56114, .d8 = 57058,
	.e8 = 58912, .f8 = 22194, .g8 = 70880, .h8 = 11140,
});

const r_magic = std.EnumArray(types.Square, types.Square.Set.Tag).init(.{
	.a1 = 0x80280013ff84ffff, .b1 = 0x5ffbfefdfef67fff,
	.c1 = 0xffeffaffeffdffff, .d1 = 0x003000900300008a,
	.e1 = 0x0050028010500023, .f1 = 0x0020012120a00020,
	.g1 = 0x0030006000c00030, .h1 = 0x0058005806b00002,
	.a2 = 0x7fbff7fbfbeafffc, .b2 = 0x0000140081050002,
	.c2 = 0x0000180043800048, .d2 = 0x7fffe800021fffb8,
	.e2 = 0xffffcffe7fcfffaf, .f2 = 0x00001800c0180060,
	.g2 = 0x4f8018005fd00018, .h2 = 0x0000180030620018,
	.a3 = 0x00300018010c0003, .b3 = 0x0003000c0085ffff,
	.c3 = 0xfffdfff7fbfefff7, .d3 = 0x7fc1ffdffc001fff,
	.e3 = 0xfffeffdffdffdfff, .f3 = 0x7c108007befff81f,
	.g3 = 0x20408007bfe00810, .h3 = 0x0400800558604100,
	.a4 = 0x0040200010080008, .b4 = 0x0010020008040004,
	.c4 = 0xfffdfefff7fbfff7, .d4 = 0xfebf7dfff8fefff9,
	.e4 = 0xc00000ffe001ffe0, .f4 = 0x4af01f00078007c3,
	.g4 = 0xbffbfafffb683f7f, .h4 = 0x0807f67ffa102040,
	.a5 = 0x200008e800300030, .b5 = 0x0000008780180018,
	.c5 = 0x0000010300180018, .d5 = 0x4000008180180018,
	.e5 = 0x008080310005fffa, .f5 = 0x4000188100060006,
	.g5 = 0xffffff7fffbfbfff, .h5 = 0x0000802000200040,
	.a6 = 0x20000202ec002800, .b6 = 0xfffff9ff7cfff3ff,
	.c6 = 0x000000404b801800, .d6 = 0x2000002fe03fd000,
	.e6 = 0xffffff6ffe7fcffd, .f6 = 0xbff7efffbfc00fff,
	.g6 = 0x000000100800a804, .h6 = 0x6054000a58005805,
	.a7 = 0x0829000101150028, .b7 = 0x00000085008a0014,
	.c7 = 0x8000002b00408028, .d7 = 0x4000002040790028,
	.e7 = 0x7800002010288028, .f7 = 0x0000001800e08018,
	.g7 = 0xa3a80003f3a40048, .h7 = 0x2003d80000500028,
	.a8 = 0xfffff37eefefdfbe, .b8 = 0x40000280090013c1,
	.c8 = 0xbf7ffeffbffaf71f, .d8 = 0xfffdffff777b7d6e,
	.e8 = 0x48300007e8080c02, .f8 = 0xafe0000fff780402,
	.g8 = 0xee73fffbffbb77fe, .h8 = 0x0002000308482882,
});

const r_offset = std.EnumArray(types.Square, u32).init(.{
	.a1 = 10890, .b1 = 50579, .c1 = 62020, .d1 = 67322,
	.e1 = 80251, .f1 = 58503, .g1 = 51175, .h1 = 83130,
	.a2 = 50430, .b2 = 21613, .c2 = 72625, .d2 = 80755,
	.e2 = 69753, .f2 = 26973, .g2 = 84972, .h2 = 31958,
	.a3 = 69272, .b3 = 48372, .c3 = 65477, .d3 = 43972,
	.e3 = 57154, .f3 = 53521, .g3 = 30534, .h3 = 16548,
	.a4 = 46407, .b4 = 11841, .c4 = 21112, .d4 = 44214,
	.e4 = 57925, .f4 = 29574, .g4 = 17309, .h4 = 40143,
	.a5 = 64659, .b5 = 70469, .c5 = 62917, .d5 = 60997,
	.e5 = 18554, .f5 = 14385, .g5 =     0, .h5 = 38091,
	.a6 = 25122, .b6 = 60083, .c6 = 72209, .d6 = 67875,
	.e6 = 56290, .f6 = 43807, .g6 = 73365, .h6 = 76398,
	.a7 = 20024, .b7 =  9513, .c7 = 24324, .d7 = 22996,
	.e7 = 23213, .f7 = 56002, .g7 = 22809, .h7 = 44545,
	.a8 = 36072, .b8 =  4750, .c8 =  6014, .d8 = 36054,
	.e8 = 78538, .f8 = 28745, .g8 =  8555, .h8 =  1009,
});

var atk = std.mem.zeroes([87988]types.Square.Set);
pub var b_atk = std.EnumArray(types.Square, Magic).initUndefined();
pub var r_atk = std.EnumArray(types.Square, Magic).initUndefined();

fn bAtkInit() !void {
	for (types.Square.values) |s| {
		const rank_edge = types.Square.Set
		  .fromSlice(types.Rank, &.{.rank_1, .rank_8})
		  .bwa(s.rank().toSet().flip());
		const file_edge = types.Square.Set
		  .fromSlice(types.File, &.{.file_a, .file_h})
		  .bwa(s.file().toSet().flip());

		const edge = types.Square.Set.bwo(rank_edge, file_edge);
		const mask = misc.genAtk(.bishop, s, .none).bwa(edge.flip());

		const offset = b_offset.getPtrConst(s).*;
		const magic = b_magic.getPtrConst(s).*;
		const nmask = mask.flip();

		const n = std.math.shl(usize, 1, mask.count());
		const p = atk[offset ..].ptr;
		b_atk.set(s, .{
			.ptr = p,
			.magic = magic,
			.nmask = nmask,
			.pad = 0xaaaaaaaaaaaaaaaa,
		});

		var b = types.Square.Set.none;
		for (0 .. n) |_| {
			const a = misc.genAtk(.bishop, s, b);
			const i = misc.genIdx(.bishop, s, b);

			p[i] = a;
			b = @TypeOf(b).fromTag(b.tag() -% mask.tag());
			b.popOther(nmask);
		}
	}
}

fn rAtkInit() !void {
	for (types.Square.values) |s| {
		const rank_edge = types.Square.Set
		  .fromSlice(types.Rank, &.{.rank_1, .rank_8})
		  .bwa(s.rank().toSet().flip());
		const file_edge = types.Square.Set
		  .fromSlice(types.File, &.{.file_a, .file_h})
		  .bwa(s.file().toSet().flip());

		const edge = types.Square.Set.bwo(rank_edge, file_edge);
		const mask = misc.genAtk(.rook, s, .none).bwa(edge.flip());

		const offset = r_offset.getPtrConst(s).*;
		const magic = r_magic.getPtrConst(s).*;
		const nmask = mask.flip();

		const n = std.math.shl(usize, 1, mask.count());
		const p = atk[offset ..].ptr;
		r_atk.set(s, .{
			.ptr = p,
			.magic = magic,
			.nmask = nmask,
			.pad = 0xaaaaaaaaaaaaaaaa,
		});

		var b = types.Square.Set.none;
		for (0 .. n) |_| {
			const a = misc.genAtk(.rook, s, b);
			const i = misc.genIdx(.rook, s, b);

			p[i] = a;
			b = @TypeOf(b).fromTag(b.tag() -% mask.tag());
			b.popOther(nmask);
		}
	}
}

fn prefetch() void {
	@prefetch(&b_atk, .{});
	@prefetch(&r_atk, .{});

	@prefetch(&bAtk, .{.cache = .instruction});
	@prefetch(&rAtk, .{.cache = .instruction});
}

pub fn init() !void {
	defer prefetch();
	try bAtkInit();
	try rAtkInit();
}

pub fn bAtk(s: types.Square, b: types.Square.Set) types.Square.Set {
	const i = misc.genIdx(.bishop, s, b);
	const p = b_atk.getPtrConst(s).ptr;
	return p[i];
} 

pub fn rAtk(s: types.Square, b: types.Square.Set) types.Square.Set {
	const i = misc.genIdx(.rook, s, b);
	const p = r_atk.getPtrConst(s).ptr;
	return p[i];
} 
