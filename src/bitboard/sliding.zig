const base = @import("base");
const std = @import("std");

const Magic = struct {
	pad:	usize,
	ptr:	[*]const base.types.Square.Set,
	magic:	base.types.Square.Set.Tag,
	nmask:	base.types.Square.Set,
};

const atk = init: {
	if (@sizeOf(Magic) != @sizeOf(u256)) {
		@compileError(std.fmt.comptimePrint("expected size {d}, found {d}",
		  .{@sizeOf(u256), @sizeOf(Magic)}));
	}

	const bin = @embedFile("sliding_atk.bin");
	var tbl: [87988]base.types.Square.Set = undefined;
	@memcpy(std.mem.sliceAsBytes(tbl[0 ..]), bin[0 ..]);
	break :init tbl;
};

const b_atk = b_init: {
	@setEvalBranchQuota(1 << 16);
	const magic_bin = @embedFile("b_magic.bin");
	const nmask_bin = @embedFile("b_nmask.bin");
	const offset_bin = @embedFile("b_offset.bin");

	var magic: std.EnumArray(base.types.Square, base.types.Square.Set.Tag) = undefined;
	var nmask: std.EnumArray(base.types.Square, base.types.Square.Set) = undefined;
	var offset: std.EnumArray(base.types.Square, u32) = undefined;

	var tbl = std.EnumArray(base.types.Square, Magic).initFill(std.mem.zeroInit(Magic, .{
		.ptr = (&atk)[0 ..].ptr,
	}));

	@memcpy(std.mem.sliceAsBytes(magic.values[0 ..]), magic_bin[0 ..]);
	@memcpy(std.mem.sliceAsBytes(nmask.values[0 ..]), nmask_bin[0 ..]);
	@memcpy(std.mem.sliceAsBytes(offset.values[0 ..]), offset_bin[0 ..]);

	for (base.types.Square.values) |s| {
		tbl.set(s, std.mem.zeroInit(Magic, .{
			.ptr = atk[offset.get(s) ..].ptr,
			.magic = magic.get(s),
			.nmask = nmask.get(s),
		}));
	}

	break :b_init tbl;
};

const r_atk = r_init: {
	@setEvalBranchQuota(1 << 16);
	const magic_bin = @embedFile("r_magic.bin");
	const nmask_bin = @embedFile("r_nmask.bin");
	const offset_bin = @embedFile("r_offset.bin");

	var magic: std.EnumArray(base.types.Square, base.types.Square.Set.Tag) = undefined;
	var nmask: std.EnumArray(base.types.Square, base.types.Square.Set) = undefined;
	var offset: std.EnumArray(base.types.Square, u32) = undefined;

	var tbl = std.EnumArray(base.types.Square, Magic).initFill(std.mem.zeroInit(Magic, .{
		.ptr = (&atk)[0 ..].ptr,
	}));

	@memcpy(std.mem.sliceAsBytes(magic.values[0 ..]), magic_bin[0 ..]);
	@memcpy(std.mem.sliceAsBytes(nmask.values[0 ..]), nmask_bin[0 ..]);
	@memcpy(std.mem.sliceAsBytes(offset.values[0 ..]), offset_bin[0 ..]);

	for (base.types.Square.values) |s| {
		tbl.set(s, std.mem.zeroInit(Magic, .{
			.ptr = atk[offset.get(s) ..].ptr,
			.magic = magic.get(s),
			.nmask = nmask.get(s),
		}));
	}

	break :r_init tbl;
};

pub fn prefetch() void {
	@prefetch(&b_atk, .{});
	@prefetch(&r_atk, .{});

	@prefetch(&bAtk, .{.cache = .instruction});
	@prefetch(&rAtk, .{.cache = .instruction});
}

pub fn bAtk(s: base.types.Square, b: base.types.Square.Set) base.types.Square.Set {
	const magic = b_atk.getPtrConst(s).magic;
	const nmask = b_atk.getPtrConst(s).nmask;

	const i = std.math.shr(@TypeOf(magic), b.bwo(nmask).tag() *% magic, 64 - 9);
	const p = b_atk.getPtrConst(s).ptr;

	return p[i];
} 

pub fn rAtk(s: base.types.Square, b: base.types.Square.Set) base.types.Square.Set {
	const magic = r_atk.getPtrConst(s).magic;
	const nmask = r_atk.getPtrConst(s).nmask;

	const i = std.math.shr(@TypeOf(magic), b.bwo(nmask).tag() *% magic, 64 - 12);
	const p = r_atk.getPtrConst(s).ptr;

	return p[i];
} 
