const misc = @import("misc");
const std = @import("std");

const n_atk_tbl = n_atk_init: {
	const bin = @embedFile("n_atk_tbl.bin");
	var tbl = std.EnumArray(misc.types.Square, misc.types.BitBoard).initUndefined();
	@memcpy(std.mem.asBytes(tbl.values[0 ..]), bin[0 ..]);
	break :n_atk_init tbl;
};

const k_atk_tbl = k_atk_init: {
	const bin = @embedFile("k_atk_tbl.bin");
	var tbl = std.EnumArray(misc.types.Square, misc.types.BitBoard).initUndefined();
	@memcpy(std.mem.asBytes(tbl.values[0 ..]), bin[0 ..]);
	break :k_atk_init tbl;
};

const b_atk_tbl = b_atk_init: {
	var tbl = std.EnumArray(misc.types.Square, [*]const misc.types.BitBoard).initUndefined();
	for (misc.types.Square.values) |s| {
		tbl.set(s, @ptrCast(&sliding_atk_tbl[b_off.get(s)]));
	}
	break :b_atk_init tbl;
};

const r_atk_tbl = r_atk_init: {
	var tbl = std.EnumArray(misc.types.Square, [*]const misc.types.BitBoard).initUndefined();
	for (misc.types.Square.values) |s| {
		tbl.set(s, @ptrCast(&sliding_atk_tbl[r_off.get(s)]));
	}
	break :r_atk_init tbl;
};

const b_magic = b_magic_init: {
	const bin = @embedFile("b_magic.bin");
	var tbl = std.EnumArray(misc.types.Square, misc.types.BitBoard.Int).initUndefined();
	@memcpy(std.mem.asBytes(tbl.values[0 ..]), bin[0 ..]);
	break :b_magic_init tbl;
};

const r_magic = r_magic_init: {
	const bin = @embedFile("r_magic.bin");
	var tbl = std.EnumArray(misc.types.Square, misc.types.BitBoard.Int).initUndefined();
	@memcpy(std.mem.asBytes(tbl.values[0 ..]), bin[0 ..]);
	break :r_magic_init tbl;
};

const b_masks = b_masks_init: {
	const bin = @embedFile("b_masks.bin");
	var tbl = std.EnumArray(misc.types.Square, misc.types.BitBoard).initUndefined();
	@memcpy(std.mem.asBytes(tbl.values[0 ..]), bin[0 ..]);
	break :b_masks_init tbl;
};

const r_masks = r_masks_init: {
	const bin = @embedFile("r_masks.bin");
	var tbl = std.EnumArray(misc.types.Square, misc.types.BitBoard).initUndefined();
	@memcpy(std.mem.asBytes(tbl.values[0 ..]), bin[0 ..]);
	break :r_masks_init tbl;
};

const b_off = b_off_init: {
	const bin = @embedFile("b_off.bin");
	var tbl = std.EnumArray(misc.types.Square, usize).initUndefined();
	@memcpy(std.mem.asBytes(tbl.values[0 ..]), bin[0 ..]);
	break :b_off_init tbl;
};

const r_off = r_off_init: {
	const bin = @embedFile("r_off.bin");
	var tbl = std.EnumArray(misc.types.Square, usize).initUndefined();
	@memcpy(std.mem.asBytes(tbl.values[0 ..]), bin[0 ..]);
	break :r_off_init tbl;
};

const sliding_atk_tbl = sliding_atk_init: {
	const bin = @embedFile("sliding_atk_tbl.bin");
	var tbl: [88772]misc.types.BitBoard = undefined;
	@memcpy(std.mem.asBytes(tbl[0 ..]), bin[0 ..]);
	break :sliding_atk_init tbl;
};

fn genAtk(comptime pt: misc.types.Ptype,
  s: misc.types.Square,
  occ: misc.types.BitBoard) misc.types.BitBoard {
	const dirs: []const misc.types.Direction = switch (pt) {
		.knight => &.{
			misc.types.Direction.northwest.add(.north), misc.types.Direction.northwest.add(.west),
			misc.types.Direction.southwest.add(.south), misc.types.Direction.southwest.add(.west),
			misc.types.Direction.southeast.add(.south), misc.types.Direction.southeast.add(.east),
			misc.types.Direction.northeast.add(.north), misc.types.Direction.northeast.add(.east),
		},
		.bishop => &.{
			.northwest, .northeast, .southwest, .southeast,
		},
		.rook => &.{
			.north, .west, .south, .east,
		},
		.king => &.{
			.north, .northwest, .west, .southwest, .south, .southeast, .east, .northeast,
		},
		else => @compileError("unexpected tag " ++ @tagName(pt)),
	};
	const max = switch (pt) {
		.knight, .king => 1,
		.bishop, .rook => misc.types.Square.max,
		else => unreachable,
	};
	var atk = misc.types.BitBoard.nil;

	for (dirs) |dir| {
		for (1 .. max + 1) |i| {
			if (!s.okShift(dir, i)) {
				break;
			}

			const shifted = s.shift(dir, i);
			atk.setSquare(shifted);

			if (occ.getSquare(shifted)) {
				break;
			}
		}
	}
	return atk;
}

fn genIdx(comptime pt: misc.types.Ptype,
  s: misc.types.Square,
  occ: misc.types.BitBoard) usize {
	return switch (pt) {
		.knight, .king => s.int(),
		.bishop, .rook => sliding: {
			const mask  = if (pt == .rook) r_masks.get(s) else b_masks.get(s);
			const magic = if (pt == .rook) r_magic.get(s) else b_magic.get(s);
			const shift = if (pt == .rook) 64 - 12 else 64 - 9;
			break :sliding
			  std.math.shr(misc.types.BitBoard.Int, occ.bitAnd(mask).int() *% magic, shift);
		},
		else => @compileError("unexpected tag" ++ @tagName(pt)),
	};
}

pub fn init() !void {
}

pub fn pAtkEast(pawns: misc.types.BitBoard, stm: misc.types.Color) misc.types.BitBoard {
	return pawns
	  .bitAnd(misc.types.File.file_h.bb().flip())
	  .shl(stm.forward().add(.east).int());
}

pub fn pAtkWest(pawns: misc.types.BitBoard, stm: misc.types.Color) misc.types.BitBoard {
	return pawns
	  .bitAnd(misc.types.File.file_a.bb().flip())
	  .shl(stm.forward().add(.west).int());
}

pub fn pAtk(pawns: misc.types.BitBoard, stm: misc.types.Color) misc.types.BitBoard {
	return misc.types.BitBoard.nil
	  .bitOr(pAtkEast(pawns, stm))
	  .bitOr(pAtkWest(pawns, stm));
}

pub fn pAtk1(pawns: misc.types.BitBoard, stm: misc.types.Color) misc.types.BitBoard {
	return misc.types.BitBoard.nil
	  .bitXor(pAtkEast(pawns, stm))
	  .bitXor(pAtkWest(pawns, stm));
}

pub fn pAtk2(pawns: misc.types.BitBoard, stm: misc.types.Color) misc.types.BitBoard {
	return misc.types.BitBoard.all
	  .bitAnd(pAtkEast(pawns, stm))
	  .bitAnd(pAtkWest(pawns, stm));
}

pub fn pPush1(pawns: misc.types.BitBoard,
  occ: misc.types.BitBoard,
  stm: misc.types.Color) misc.types.BitBoard {
	return pawns
	  .shl(stm.forward().int())
	  .bitAnd(occ.flip());
}

pub fn pPush2(pawns: misc.types.BitBoard,
  occ: misc.types.BitBoard,
  stm: misc.types.Color) misc.types.BitBoard {
	const home_pawns = pawns.bitAnd(stm.pawnRank().bb());
	return pPush1(pPush1(home_pawns, occ, stm), occ, stm);
}

pub fn pForwSpan(pawns: misc.types.BitBoard, stm: misc.types.Color) misc.types.BitBoard {
	var p = pawns;
	for (misc.types.Rank.min .. misc.types.Rank.max) |i| {
		p = p.bitOr(p.shl(stm.forward().mul(i).int()));
	}
	return p;
}

pub fn pBackSpan(pawns: misc.types.BitBoard, stm: misc.types.Color) misc.types.BitBoard {
	return pForwSpan(pawns, stm.flip()).bitXor(pawns);
}

pub fn nAtk(s: misc.types.Square) misc.types.BitBoard {
	return n_atk_tbl.get(s);
}

pub fn bAtk(s: misc.types.Square, occ: misc.types.BitBoard) misc.types.BitBoard {
	return b_atk_tbl.get(s)[genIdx(.bishop, s, occ)];
}

pub fn rAtk(s: misc.types.Square, occ: misc.types.BitBoard) misc.types.BitBoard {
	return r_atk_tbl.get(s)[genIdx(.rook, s, occ)];
}

pub fn qAtk(s: misc.types.Square, occ: misc.types.BitBoard) misc.types.BitBoard {
	return misc.types.BitBoard.nil
	  .bitOr(bAtk(s, occ))
	  .bitOr(rAtk(s, occ));
}

pub fn kAtk(s: misc.types.Square) misc.types.BitBoard {
	return k_atk_tbl.get(s);
}

pub fn ptAtk(comptime pt: misc.types.Ptype, s: misc.types.Square, occ: misc.types.BitBoard) misc.types.BitBoard {
	return switch (pt) {
		.knight => nAtk(s),
		.bishop => bAtk(s, occ),
		.rook   => rAtk(s, occ),
		.queen  => qAtk(s, occ),
		.king   => kAtk(s),
		else => @compileError("unexpected tag " ++ @tagName(pt)),
	};
}

test {
}
