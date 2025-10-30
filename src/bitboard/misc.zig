const base = @import("base");
const std = @import("std");

const sliding = @import("sliding.zig");

pub fn genAtk(comptime pt: base.types.Ptype,
  s: base.types.Square,
  b: base.types.Square.Set) base.types.Square.Set {
	const dirs: []const base.types.Direction = switch (pt) {
		.knight => &.{
			.northnorthwest, .westnorthwest, .southsouthwest, .westsouthwest,
			.northnortheast, .eastnortheast, .southsoutheast, .eastsoutheast,
		},
		.bishop => &.{
			.northwest, .northeast,
			.southwest, .southeast,
		},
		.rook => &.{
			.north, .west, .south, .east,
		},
		.king => &.{
			.north, .northwest, .west, .southwest,
			.south, .southeast, .east, .northeast,
		},
		else => @compileError("unexpected tag" ++ @tagName(pt)),
	};
	const max = switch (pt) {
		.knight, .king => 1,
		.bishop, .rook => base.types.Square.cnt,
		else => @compileError("unexpected tag" ++ @tagName(pt)),
	};
	var atk = base.types.Square.Set.none;

	for (dirs) |d| {
		for (1 .. max + 1) |i| {
			if (!s.okShift(d, i)) {
				break;
			}

			const shifted = s.shift(d, i);
			atk.set(shifted);

			if (b.get(shifted)) {
				break;
			}
		}
	}
	return atk;
}

pub fn genIdx(comptime pt: base.types.Ptype,
  s: base.types.Square,
  b: base.types.Square.Set) base.types.Square.Set.Tag {
	return switch (pt) {
		.knight, .king => s.tag(),
		.bishop, .rook => blk: {
			const shr = if (pt == .rook) 64 - 12 else 64 - 9;
			const tbl = if (pt == .rook) &sliding.r_atk else &sliding.b_atk;

			const magic = tbl.getPtrConst(s).magic;
			const nmask = tbl.getPtrConst(s).nmask;

			const mul = b.bwo(nmask).tag() *% magic;
			const idx = std.math.shr(@TypeOf(mul), mul, shr);
			break :blk idx;
		},
		else => @compileError("unexpected tag" ++ @tagName(pt)),
	};
}
