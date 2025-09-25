const base = @import("base");
const std = @import("std");

const misc = @import("misc.zig");
const nk = @import("nk.zig");
const br = @import("br.zig");

pub const nAtk = nk.nAtk;
pub const kAtk = nk.kAtk;

pub const bAtk = br.bAtk;
pub const rAtk = br.rAtk;

pub fn deinit() void {
}

pub fn init() !void {
	try nk.nAtkInit();
	try nk.kAtkInit();
	defer nk.prefetch();

	try br.bAtkInit();
	try br.rAtkInit();
	defer br.prefetch();
}

pub fn pAtkEast(pawns: misc.Set, stm: base.types.Color) misc.Set {
	const dir = stm.forward().add(.east);
	const dst = base.types.File.file_a.toSet().flip();
	return pawns.shl(dir.tag()).bwa(dst);
}

pub fn pAtkWest(pawns: misc.Set, stm: base.types.Color) misc.Set {
	const dir = stm.forward().add(.west);
	const dst = base.types.File.file_h.toSet().flip();
	return pawns.shl(dir.tag()).bwa(dst);
}

pub fn pAtk(pawns: misc.Set, stm: base.types.Color) misc.Set {
	const ea = pAtkEast(pawns, stm);
	const wa = pAtkWest(pawns, stm);
	return misc.Set.bwo(ea, wa);
}

pub fn pPush1(pawns: misc.Set, occ: misc.Set, stm: base.types.Color) misc.Set {
	const dir = stm.forward();
	const dst = occ.flip();
	return pawns.shl(dir.tag()).bwa(dst);
}

pub fn pPush2(pawns: misc.Set, occ: misc.Set, stm: base.types.Color) misc.Set {
	const home_pawns = pawns.bwa(stm.pawnRank().toSet());
	return pPush1(pPush1(home_pawns, occ, stm), occ, stm);
}

pub fn qAtk(s: base.types.Square, occ: misc.Set) misc.Set {
	const ba = bAtk(s, occ);
	const ra = rAtk(s, occ);
	return misc.Set.bwo(ba, ra);
}

pub fn ptAtk(pt: base.types.Ptype, s: base.types.Square, occ: misc.Set) misc.Set {
	return switch (pt) {
		.knight => nAtk(s),
		.bishop => bAtk(s, occ),
		.rook   => rAtk(s, occ),
		.queen  => qAtk(s, occ),
		.king   => kAtk(s),
		else => std.debug.panic("unexpected enum value", .{}),
	};
}
