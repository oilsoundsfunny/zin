const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");

const Self = @This();

pos:	Position,
depth:	isize,

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

	root_moves:	movegen.RootMove.List,

	pub var global = Pool {
		.workers = null,
		.cond = .{},
		.mtx = .{},
		.root_moves = std.mem.zeroes(movegen.RootMove.List),
	};

	pub fn allocate(self: *Pool, cnt: usize) !void {
		if (self.workers != null) {
			self.free();
		}
		self.workers = try misc.heap.allocator.alignedAlloc(Self, std.heap.page_size_max, cnt);
	}

	pub fn free(self: *Pool) void {
		misc.heap.allocator.free(self.workers.?);
	}

	pub fn getMainWorker(self: Pool) ?*Self {
		return if (self.workers == null) null else &self.workers.?[0];
	}
};

pub fn isMainWorker(self: *Self) bool {
	const main_worker = Pool.global.getMainWorker() orelse return false;
	return self == main_worker;
}
