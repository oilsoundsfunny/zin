const base = @import("base");
const std = @import("std");

pub const Set = base.types.Square.Set;

pub fn genAtk(comptime pt: base.types.Ptype,
  s: base.types.Square,
  o: Set) Set {
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

		else => @compileError("unexpected tag " ++ @tagName(pt)),
	};
	const max = switch (pt) {
		.knight, .king => 1,
		.bishop, .rook => base.types.Square.cnt,
		else => @compileError("unexpected tag " ++ @tagName(pt)),
	};
	var atk = Set.nul;

	for (dirs) |d| {
		for (1 .. max + 1) |i| {
			if (!s.okShift(d, i)) {
				break;
			}

			const shifted = s.shift(d, i);
			atk.set(shifted);

			if (o.get(shifted)) {
				break;
			}
		}
	}

	return atk;
}

pub fn permute(mask: Set, id: usize) Set {
	var i = id;
	var m = mask;
	var b = @TypeOf(m).nul;

	while (i != 0) : ({
		i /= 2;
		m.popLow();
	}) {
		b.setOther(if (i % 2 != 0) m.getLow() else .nul);
	}

	return b;
}
