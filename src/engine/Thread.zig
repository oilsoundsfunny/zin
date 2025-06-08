const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const movegen = @import("movegen.zig");

const Self = @This();

pos:	Position,
depth:	isize,

root_move_cnt:	usize,
root_moves:	[256]movegen.RootMove,

bfhist:	[misc.types.Square.num][misc.types.Piece.num]Hist,
capthist:	[misc.types.Square.num]
  [misc.types.Piece.num]
  [misc.types.Square.num]
  [misc.types.Piece.num]Hist,
conthist:	[misc.types.Square.num]
  [misc.types.Piece.num]
  [misc.types.Square.num]
  [misc.types.Piece.num]Hist,

pub const Depth = isize;
pub const Hist = i16;

pub const Pool = struct {
	workers:	?[]Self,

	cond:	std.Thread.Condition,
	mtx:	std.Thread.Mutex,

	pub var global = Pool {
		.workers = null,
		.cond = .{},
		.mtx = .{},
	};
};

// pub fn genRootMoves(self: *Self) void {
// }
