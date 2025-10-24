const base = @import("base");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");

const arch = @import("arch.zig");
const net = @import("net.zig");
const root = @import("root.zig");

const Self = @This();

perspectives:	std.EnumArray(base.types.Color, Vec)
  = std.EnumArray(base.types.Color, Vec).initFill(net.default.hl0_b),
mirrored:	std.EnumArray(base.types.Color, bool)
  = std.EnumArray(base.types.Color, bool).initFill(false),

pub const Madd = @Vector(arch.hl0_len / 2, engine.evaluation.score.Int);
pub const Vec = @Vector(arch.hl0_len, arch.Int);

fn index(self: *const Self, c: base.types.Color, s: base.types.Square, p: base.types.Piece) usize {
	const mirrored = self.mirrored.get(c);
	const kingsided = if (mirrored) s.flipFile() else s;
	const pov = switch (c) {
		.white => kingsided,
		.black => kingsided.flipRank(),
	};

	const ci: usize = if (p.color() == c) 0 else arch.ptype_n;
	const pi: usize = switch (p.ptype()) {
		.pawn => 0,
		.knight => 1,
		.bishop => 2,
		.rook => 3,
		.queen => 4,
		.king => 5,
		else => |pt| std.debug.panic("invalid ptype @enumFromInt({d})", .{pt.tag()}),
	};
	const si: usize = pov.tag();
	return (ci + pi) * arch.square_n + si;
}

pub fn pop(self: *Self, s: base.types.Square, p: base.types.Piece) void {
	inline for (base.types.Color.values) |c| {
		const v: *align(32) Vec
		  = self.perspectives.getPtr(c);
		const w: *align(32) const Vec
		  = @ptrCast(&net.default.hl0_w[self.index(c, s, p)]);
		v.* -%= w.*;
	}
}

pub fn set(self: *Self, s: base.types.Square, p: base.types.Piece) void {
	inline for (base.types.Color.values) |c| {
		const v: *align(32) Vec
		  = self.perspectives.getPtr(c);
		const w: *align(32) const Vec
		  = @ptrCast(&net.default.hl0_w[self.index(c, s, p)]);
		v.* +%= w.*;
	}
}

pub fn mirror(self: *Self,
  stm: base.types.Color,
  occ: *const std.EnumArray(base.types.Piece, base.types.Square.Set)) void {
	const ptr = self.perspectives.getPtr(stm);
	ptr.* = net.default.hl0_b;

	for (base.types.Piece.w_pieces ++ base.types.Piece.b_pieces) |p| {
		var pieces = occ.getPtrConst(p).*;
		while (pieces.lowSquare()) |s| : (pieces.popLow()) {
			ptr.* +%= net.default.hl0_w[self.index(stm, s, p)];
		}
	}
}
