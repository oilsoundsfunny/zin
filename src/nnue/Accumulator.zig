const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const arch = @import("arch.zig");
const net = @import("net.zig");
const root = @import("root.zig");

const Self = @This();

perspectives:	std.EnumArray(types.Color, Vec)
  = std.EnumArray(types.Color, Vec).initFill(net.default.hl0_b),
mirrored:	std.EnumArray(types.Color, bool)
  = std.EnumArray(types.Color, bool).initFill(false),

pub const Half = @Vector(arch.hl0_len / 2, arch.Int);
pub const Vec = @Vector(arch.hl0_len, arch.Int);

pub const Mail = struct {
	piece:	types.Piece,
	square:	types.Square,
};

fn index(self: *const Self, c: types.Color, s: types.Square, p: types.Piece) usize {
	const mirrored = self.mirrored.get(c);
	const kingsided = if (mirrored) s.flipFile() else s;
	const pov = switch (c) {
		.white => kingsided,
		.black => kingsided.flipRank(),
	};

	const ci: usize = if (p.color() == c) 0 else arch.ptype_n;
	const pi: usize = p.ptype().tag();
	const si: usize = pov.tag();
	return (ci + pi) * arch.square_n + si;
}

pub fn fusedAddSub(self: *Self, c: types.Color, add_m: Mail, sub_m: Mail) void {
	const add_i = self.index(c, add_m.square, add_m.piece);
	const sub_i = self.index(c, sub_m.square, sub_m.piece);

	const v: *align(1024) [arch.hl0_len]arch.Int = self.perspectives.getPtr(c);
	var i: usize = 0;
	while (i < arch.hl0_len) : (i += arch.native_len) {
		const add_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[add_i][i ..][0 .. arch.native_len]);
		const sub_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[sub_i][i ..][0 .. arch.native_len]);

		const vec: *arch.Native = @alignCast(v[i ..][0 .. arch.native_len]);
		vec.* +%= add_w.*;
		vec.* -%= sub_w.*;
	}
}

pub fn fusedAddSubSub(self: *Self, c: types.Color, add0: Mail, sub0: Mail, sub1: Mail) void {
	const add0_i = self.index(c, add0.square, add0.piece);
	const sub0_i = self.index(c, sub0.square, sub0.piece);
	const sub1_i = self.index(c, sub1.square, sub1.piece);

	const v: *align(1024) [arch.hl0_len]arch.Int = self.perspectives.getPtr(c);
	var i: usize = 0;
	while (i < arch.hl0_len) : (i += arch.native_len) {
		const add0_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[add0_i][i ..][0 .. arch.native_len]);
		const sub0_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[sub0_i][i ..][0 .. arch.native_len]);
		const sub1_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[sub1_i][i ..][0 .. arch.native_len]);

		const vec: *arch.Native = @alignCast(v[i ..][0 .. arch.native_len]);
		vec.* +%= add0_w.*;
		vec.* -%= sub0_w.*;
		vec.* -%= sub1_w.*;
	}
}

pub fn fusedAddAddSubSub(self: *Self,
  c: types.Color,
  add0: Mail, add1: Mail,
  sub0: Mail, sub1: Mail) void {
	const add0_i = self.index(c, add0.square, add0.piece);
	const add1_i = self.index(c, add1.square, add1.piece);
	const sub0_i = self.index(c, sub0.square, sub0.piece);
	const sub1_i = self.index(c, sub1.square, sub1.piece);

	const v: *align(1024) [arch.hl0_len]arch.Int = self.perspectives.getPtr(c);
	var i: usize = 0;
	while (i < arch.hl0_len) : (i += arch.native_len) {
		const add0_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[add0_i][i ..][0 .. arch.native_len]);
		const add1_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[add1_i][i ..][0 .. arch.native_len]);
		const sub0_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[sub0_i][i ..][0 .. arch.native_len]);
		const sub1_w: *const arch.Native
		  = @alignCast(net.default.hl0_w[sub1_i][i ..][0 .. arch.native_len]);

		const vec: *arch.Native = @alignCast(v[i ..][0 .. arch.native_len]);
		vec.* +%= add0_w.*;
		vec.* +%= add1_w.*;
		vec.* -%= sub0_w.*;
		vec.* -%= sub1_w.*;
	}
}

pub fn add(self: *Self, c: types.Color, mail: Mail) void {
	const i = self.index(c, mail.square, mail.piece);
	const w: *align(64) const [arch.hl0_len]arch.Int = net.default.hl0_w[i][0 .. arch.hl0_len];
	const v: *align(64) [arch.hl0_len]arch.Int = self.perspectives.getPtr(c);

	var k: usize = 0;
	while (k < arch.hl0_len) : (k += arch.native_len) {
		const vec: *arch.Native = @alignCast(v[k ..][0 .. arch.native_len]);
		const wgt: *const arch.Native = @alignCast(w[k ..][0 .. arch.native_len]);
		vec.* +%= wgt.*;
	}
}

pub fn sub(self: *Self, c: types.Color, mail: Mail) void {
	const i = self.index(c, mail.square, mail.piece);
	const w: *align(64) const [arch.hl0_len]arch.Int = net.default.hl0_w[i][0 .. arch.hl0_len];
	const v: *align(64) [arch.hl0_len]arch.Int = self.perspectives.getPtr(c);

	var k: usize = 0;
	while (k < arch.hl0_len) : (k += arch.native_len) {
		const vec: *arch.Native = @alignCast(v[k ..][0 .. arch.native_len]);
		const wgt: *const arch.Native = @alignCast(w[k ..][0 .. arch.native_len]);
		vec.* -%= wgt.*;
	}
}

pub fn mirror(self: *Self, pos: *const engine.Board.One, c: types.Color) void {
	const mirrored = self.mirrored.getPtr(c);
	mirrored.* = !mirrored.*;

	self.perspectives.set(c, net.default.hl0_b);
	for (types.Piece.w_pieces ++ types.Piece.b_pieces) |p| {
		var pieces = pos.pieceOcc(p);
		while (pieces.lowSquare()) |s| : (pieces.popLow()) {
			self.add(c, .{.piece = p, .square = s});
		}
	}
}
