const bitboard = @import("bitboard");
const std = @import("std");
const types = @import("types");

const Keys = struct {
	occ:	std.EnumArray(types.Square, std.EnumArray(types.Piece, Int)),
	castle:	std.EnumArray(types.Castle.Set, Int),
	en_pas:	std.EnumArray(types.File, Int),
	stm:	Int,
};

var keys = std.mem.zeroInit(Keys, .{});

pub const Int = types.Square.Set.Tag;

pub fn init() !void {
	var r = std.Random.Xoroshiro128.init(0xa69f73cca23a9ac5);

	for (types.Square.values) |s| {
		for (types.Piece.w_pieces) |p| {
			keys.occ.getPtr(s).set(p, r.random().int(Int));
		}
		for (types.Piece.b_pieces) |p| {
			keys.occ.getPtr(s).set(p, r.random().int(Int));
		}
	}

	for (&keys.castle.values) |*p| {
		p.* = r.random().int(Int);
	}

	for (&keys.en_pas.values) |*p| {
		p.* = r.random().int(Int);
	}

	keys.stm = r.random().int(Int);
}

pub fn psq(s: types.Square, p: types.Piece) Int {
	return keys.occ.getPtrConst(s).getPtrConst(p).*;
}

pub fn cas(c: types.Castle.Set) Int {
	return keys.castle.getPtrConst(c).*;
}

pub fn enp(e: ?types.Square) Int {
	return if (e) |s| keys.en_pas.getPtrConst(s.file()).* else 0;
}

pub fn stm() Int {
	return keys.stm;
}

pub fn index(key: Int, len: usize) usize {
	const m = std.math.mulWide(usize, key, len);
	const h = std.math.shr(@TypeOf(m), m, @typeInfo(@TypeOf(m)).int.bits / 2);
	return @truncate(h);
}
