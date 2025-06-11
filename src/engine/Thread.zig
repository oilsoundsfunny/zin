const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");

const Self = @This();

handle:	std.Thread,

pos:	Position,
depth:	isize,

root_moves:	movegen.RootMove.Slice,

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

pub const Error = error {
	Uninitialized,
};

pub const Pool = struct {
	workers:	?[]Self,

	cond:	std.Thread.Condition,
	mtx:	std.Thread.Mutex,

	root_moves:	movegen.RootMove.List,

	pub var global = Pool {
		.workers = null,
		.cond = .{},
		.mtx = .{},
		.root_moves = undefined,
	};

	pub fn allocate(self: *Pool, cnt: usize) !void {
		if (self.workers != null) {
			self.free();
		}
		self.workers = try misc.heap.allocator.alignedAlloc(Self, null, cnt);
	}

	pub fn free(self: *Pool) void {
		misc.heap.allocator.free(self.workers.?);
	}

	pub fn getMainWorker(self: Pool) !*Self {
		return if (self.workers == null) error.Uninitialized else &self.workers.?[0];
	}

	pub fn genRootMoves(self: *Pool) !void {
		const main_worker = try self.getMainWorker();
		const pos = &main_worker.pos;

		var list = std.mem.zeroes(movegen.ScoredMove.List);
		_ = list.gen(main_worker.pos, true);
		_ = list.gen(main_worker.pos, false);

		self.root_moves = try movegen.RootMove.List.init(0);
		for (list.arr[0 .. list.cnt]) |sm| {
			const move = sm.move;
			pos.doMove(move) catch continue;
			pos.undoMove();

			var rm = std.mem.zeroes(movegen.RootMove);
			rm.len = 1;
			rm.line[0] = move;
			rm.score = evaluation.score.nil;
			try self.root_moves.append(rm);
		}

		const div = self.root_moves.constSlice().len / self.workers.?.len;
		const mod = self.root_moves.constSlice().len % self.workers.?.len;
		var start: usize = 0;
		for (self.workers.?, 0 ..) |*thread, i| {
			thread.root_moves.slice = self.root_moves
			  .slice()[start .. if (i < mod) start + div + 1 else start + div];
			thread.root_moves.cnt = thread.root_moves.slice.len;
			thread.root_moves.idx = 0;

			start += thread.root_moves.cnt;
		}
	}
};

pub fn isMainWorker(self: *Self) bool {
	const main_worker = Pool.global.getMainWorker() catch return false;
	return self == main_worker;
}
