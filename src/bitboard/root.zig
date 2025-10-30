const base = @import("base");
const std = @import("std");

const jumping = @import("jumping.zig");
const sliding = @import("sliding.zig");

pub const nAtk = jumping.nAtk;
pub const kAtk = jumping.kAtk;

pub const bAtk = sliding.bAtk;
pub const rAtk = sliding.rAtk;

pub fn deinit() void {
}

pub fn init() !void {
	try jumping.init();
	try sliding.init();
}

pub fn pAtkEast(pawns: base.types.Square.Set, stm: base.types.Color) base.types.Square.Set {
	const dir = stm.forward().add(.east);
	const dst = base.types.File.file_a.toSet().flip();
	return pawns.shl(dir.tag()).bwa(dst);
}

pub fn pAtkWest(pawns: base.types.Square.Set, stm: base.types.Color) base.types.Square.Set {
	const dir = stm.forward().add(.west);
	const dst = base.types.File.file_h.toSet().flip();
	return pawns.shl(dir.tag()).bwa(dst);
}

pub fn pAtk(pawns: base.types.Square.Set, stm: base.types.Color) base.types.Square.Set {
	const ea = pAtkEast(pawns, stm);
	const wa = pAtkWest(pawns, stm);
	return base.types.Square.Set.bwo(ea, wa);
}

pub fn pPush1(pawns: base.types.Square.Set,
  occ: base.types.Square.Set,
  stm: base.types.Color) base.types.Square.Set {
	const dir = stm.forward();
	const dst = occ.flip();
	return pawns.shl(dir.tag()).bwa(dst);
}

pub fn pPush2(pawns: base.types.Square.Set,
  occ: base.types.Square.Set,
  stm: base.types.Color) base.types.Square.Set {
	const home_pawns = pawns.bwa(stm.pawnRank().toSet());
	return pPush1(pPush1(home_pawns, occ, stm), occ, stm);
}

pub fn qAtk(s: base.types.Square, occ: base.types.Square.Set) base.types.Square.Set {
	const ba = bAtk(s, occ);
	const ra = rAtk(s, occ);
	return base.types.Square.Set.bwo(ba, ra);
}

pub fn ptAtk(pt: base.types.Ptype,
  s: base.types.Square,
  b: base.types.Square.Set) base.types.Square.Set {
	return switch (pt) {
		.knight => nAtk(s),
		.bishop => bAtk(s, b),
		.rook   => rAtk(s, b),
		.queen  => qAtk(s, b),
		.king   => kAtk(s),
		else => std.debug.panic("unexpected enum value", .{}),
	};
}
