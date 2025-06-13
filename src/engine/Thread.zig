const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const timeman = @import("timeman.zig");

const Self = @This();

const spawn_args = std.Thread.SpawnConfig {
  .allocator = misc.heap.allocator,
  .stack_size = 16 * 1024 * 1024,
};

handle:	std.Thread,

pos:	Position,
depth:	isize,

root_moves:	[]movegen.RootMove,

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
		.root_moves = std.mem.zeroes(movegen.RootMove.List),
	};

	pub fn allocate(self: *Pool, cnt: usize) !void {
		if (self.workers != null) {
			self.free();
		}
		self.workers = try misc.heap.allocator.alignedAlloc(Self, null, cnt);
	}

	pub fn free(self: *Pool) void {
		if (self.workers != null) {
			misc.heap.allocator.free(self.workers.?);
		}
	}

	pub fn getMainWorker(self: *Pool) !*Self {
		const workers = self.workers orelse return error.Uninitialized;
		return &workers[0];
	}

	pub fn getHelpers(self: *Pool) ![]Self {
		const workers = self.workers orelse return error.Uninitialized;
		return workers[1 ..];
	}

	pub fn genRootMoves(self: *Pool) !void {
		const workers = self.workers orelse return error.Uninitialized;
		const main_worker = try self.getMainWorker();
		const pos = &main_worker.pos;

		var list = std.mem.zeroes(movegen.ScoredMove.List);
		_ = list.gen(pos.*, true);
		_ = list.gen(pos.*, false);

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

		const div = self.root_moves.constSlice().len / workers.len;
		const mod = self.root_moves.constSlice().len % workers.len;
		var start: usize = 0;
		for (workers, 0 ..) |*thread, i| {
			thread.root_moves = self.root_moves
			  .slice()[start .. if (i < mod) start + div + 1 else start + div];
			start += thread.root_moves.len;
		}
	}

	pub fn sortRootMoves(self: *Pool) void {
		const desc = struct {
			pub fn inner(_: void, a: movegen.RootMove, b: movegen.RootMove) bool {
				return a.score > b.score;
			}
		}.inner;
		std.sort.insertion(movegen.RootMove, self.root_moves.slice(), {}, desc);
	}

	pub fn startMainWorker(self: *Pool, comptime func: anytype, comptime args: anytype) !void {
		const main_worker = try self.getMainWorker();
		main_worker.handle = try std.Thread.spawn(spawn_args, func, .{main_worker} ++ args);
		std.Thread.detach(main_worker.handle);
	}

	pub fn prepare(self: *Pool) !void {
		const main_worker = try self.getMainWorker();
		main_worker.depth = timeman.depth;
	}
};

pub fn isMainWorker(self: *Self) bool {
	const main_worker = Pool.global.getMainWorker() catch return false;
	return self == main_worker;
}

pub fn sleep(self: *Self, condition: *bool) void {
	_ = self;

	Pool.global.mtx.lock();
	while (!@atomicLoad(bool, condition, .monotonic)) {
		Pool.global.cond.wait(&Pool.global.mtx);
	}
	Pool.global.mtx.unlock();
}
