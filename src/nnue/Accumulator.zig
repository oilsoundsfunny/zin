const base = @import("base");
const std = @import("std");

const arch = @import("arch.zig");
const root = @import("root.zig");

const Self = @This();
const Vec = @Vector(arch.hl0_len, arch.Int);

values:	Vec align(64),

const index = struct {
	fn fromPiece(comptime c: base.types.Color, p: base.types.Piece) usize {
		const is_theirs = p.color() != c;
		const ci: usize = p.color().tag();
		const pi: usize = p.ptype().tag() - base.types.Ptype.pawn.tag();
		return if (is_theirs) ci * arch.ptype_n + pi else pi;
	}

	fn fromSquare(comptime c: base.types.Color, s: base.types.Square) usize {
		return switch (c) {
			.white => s.tag(),
			.black => s.flipRank().tag(),
		};
	}

	fn fromPsq(comptime c: base.types.Color, s: base.types.Square, p: base.types.Piece) usize {
		const pi = fromPiece(c, p);
		const si = fromSquare(c, s);
		return pi * si;
	}
};

pub const Pair = struct {
	white:	Self,
	black:	Self,

	pub fn pop(self: *Pair, s: base.types.Square, p: base.types.Piece) void {
		const vecs = std.EnumArray(base.types.Color, *align(64) Vec).init(.{
			.white = &self.white.values,
			.black = &self.black.values,
		});
		const wgts = std.EnumArray(base.types.Color, *align(64) const Vec).init(.{
			.white = @ptrCast(&root.net.hl0_w[index.fromPsq(.white, s, p)]),
			.black = @ptrCast(&root.net.hl0_w[index.fromPsq(.black, s, p)]),
		});

		vecs.get(.white).* -%= wgts.get(.white).*;
		vecs.get(.black).* -%= wgts.get(.black).*;
	}

	pub fn set(self: *Pair, s: base.types.Square, p: base.types.Piece) void {
		const vecs = std.EnumArray(base.types.Color, *align(64) Vec).init(.{
			.white = &self.white.values,
			.black = &self.black.values,
		});
		const wgts = std.EnumArray(base.types.Color, *align(64) const Vec).init(.{
			.white = @ptrCast(&root.net.hl0_w[index.fromPsq(.white, s, p)]),
			.black = @ptrCast(&root.net.hl0_w[index.fromPsq(.black, s, p)]),
		});

		vecs.get(.white).* +%= wgts.get(.white).*;
		vecs.get(.black).* +%= wgts.get(.black).*;
	}
};
