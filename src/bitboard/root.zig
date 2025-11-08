const std = @import("std");
const types = @import("types");

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

pub fn pAtkEast(pawns: types.Square.Set, stm: types.Color) types.Square.Set {
	const dir = stm.forward().add(.east);
	const dst = types.File.file_a.toSet().flip();
	return pawns.shl(dir.tag()).bwa(dst);
}

pub fn pAtkWest(pawns: types.Square.Set, stm: types.Color) types.Square.Set {
	const dir = stm.forward().add(.west);
	const dst = types.File.file_h.toSet().flip();
	return pawns.shl(dir.tag()).bwa(dst);
}

pub fn pAtk(pawns: types.Square.Set, stm: types.Color) types.Square.Set {
	const ea = pAtkEast(pawns, stm);
	const wa = pAtkWest(pawns, stm);
	return types.Square.Set.bwo(ea, wa);
}

pub fn pPush1(pawns: types.Square.Set, occ: types.Square.Set, stm: types.Color) types.Square.Set {
	const dir = stm.forward();
	const dst = occ.flip();
	return pawns.shl(dir.tag()).bwa(dst);
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
		.rook   => rAtk(s, b),
		.queen  => qAtk(s, b),
		.king   => kAtk(s),
		else => std.debug.panic("unexpected enum value", .{}),
	};
}
