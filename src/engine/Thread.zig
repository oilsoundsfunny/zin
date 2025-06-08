const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");

const Self = @This();

pos:	Position,
depth:	isize,

root_moves:	movegen.RootMove.List,

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

pub fn genRootMoves(self: *Self) void {
	var cnt: usize = 0;
	var list = std.mem.zeroes(movegen.ScoredMove.List);

	cnt += list.gen(self.pos, true);
	cnt += list.gen(self.pos, false);
	for (0 .. cnt) |i| {
		const move = list.arr[i].move;

		self.pos.doMove(move) catch continue;
		self.pos.undoMove();

		self.root_moves.arr[self.root_moves.cnt] = .{
			.score = evaluation.score.draw,
			.len   = 0,
			.line  = std.mem.zeroes(@TypeOf(self.root_moves.arr[self.root_moves.cnt].line)),
		};
		self.root_moves.arr[self.root_moves.cnt].line[0] = move;
		self.root_moves.cnt += 1;
	}
}
