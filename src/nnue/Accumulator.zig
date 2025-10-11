const base = @import("base");
const engine = @import("engine");
const std = @import("std");

const arch = @import("arch.zig");
const net = @import("net.zig");
const root = @import("root.zig");

const Self = @This();

values:	Vec align(64)
  = @as(*align(64) const Vec, @ptrCast(&net.default.hl0_b)).*,

const index = struct {
	fn init(comptime c: base.types.Color, s: base.types.Square, p: base.types.Piece) usize {
		const is_us = p.color() == c;
		const is_them = !is_us;

		const si: usize = if (c == .white) s.tag() else s.flipRank().tag();
		const ci: usize = arch.ptype_n * @as(usize, @intFromBool(is_them));
		const pi: usize = switch (p.ptype()) {
			.pawn => 0,
			.knight => 1,
			.bishop => 2,
			.rook => 3,
			.queen => 4,
			.king => 5,
			else => std.debug.panic("invalid ptype", .{}),
		};
		return (ci + pi) * arch.square_n + si;
	}
};

pub const Vec = @Vector(arch.hl0_len, arch.Int);
pub const Madd = @Vector(arch.hl0_len / 2, engine.evaluation.score.Int);

pub const Marker = struct {
	ply:	usize,
};

pub const Pair = struct {
	white:	Self = .{},
	black:	Self = .{},

	pub fn pop(self: *Pair, s: base.types.Square, p: base.types.Piece) void {
		const vecs = std.EnumArray(base.types.Color, *align(64) Vec).init(.{
			.white = &self.white.values,
			.black = &self.black.values,
		});

		const wgts = std.EnumArray(base.types.Color, *align(64) const Vec).init(.{
			.white = @ptrCast(&net.default.hl0_w[index.init(.white, s, p)]),
			.black = @ptrCast(&net.default.hl0_w[index.init(.black, s, p)]),
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
			.white = @ptrCast(&net.default.hl0_w[index.init(.white, s, p)]),
			.black = @ptrCast(&net.default.hl0_w[index.init(.black, s, p)]),
		});

		vecs.get(.white).* +%= wgts.get(.white).*;
		vecs.get(.black).* +%= wgts.get(.black).*;
	}
};
