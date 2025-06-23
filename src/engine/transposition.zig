const builtin = @import("builtin");
const misc = @import("misc");
const std = @import("std");

const Zobrist = @import("Zobrist.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const search = @import("search.zig");

pub const Entry = packed struct(u80) {
	key:	u16,
	flag:	Flag,
	age:	u6,
	depth:	u8,
	move:	movegen.Move,
	eval:	evaluation.score.Int,
	score:	evaluation.score.Int,

	pub const Flag = enum(u2) {
		nil,
		alpha,
		pv,
		beta,
	};

	pub fn shouldTrust(self: Entry, alpha: isize, beta: isize) bool {
		if (self.flag == .pv
		  or (self.flag == .alpha and self.score <= alpha)
		  or (self.flag == .beta  and self.score >  beta)) {
			return true;
		}
		return false;
	}
};

pub const Cluster = packed struct(u256) {
	entry0:	Entry,
	entry1:	Entry,
	entry2:	Entry,
	pad:	u16,
};
test {
	try std.testing.expectEqual(@sizeOf(u16) * 16, @sizeOf(Cluster));
}

pub const Table = struct {
	tbl:	?[]Cluster,
	age:	usize,

	pub var global = Table {
		.tbl = null,
		.age = 0,
	};

	fn threadedClear(slice: []Cluster) void {
		for (slice) |*p| {
			p.* = std.mem.zeroes(@TypeOf(p.*));
		}
	}

	fn index(self: Table, key: Zobrist.Int) !usize {
		const c = if (self.tbl != null) self.tbl.?.len else return error.OutOfMemory;
		const m = std.math.mulWide(Zobrist.Int, c, key);
		return @truncate(m >> @typeInfo(Zobrist.Int).int.bits);
	}

	pub fn allocate(self: *Table, mb: usize) !void {
		const len = (mb << 20) / @sizeOf(Cluster);
		if (self.tbl == null) {
			self.tbl = try misc.heap.allocator.alignedAlloc(Cluster, .@"64", len);
		} else {
			self.tbl = try misc.heap.allocator.realloc(self.tbl.?, len);
		}
	}

	pub fn clear(self: *Table) !void {
		if (self.tbl) |tbl| {
			const infos = try search.Info.ofThreads();
			const div = tbl.len / infos.len;
			const mod = tbl.len % infos.len;
			var start: usize = 0;

			var pool: std.Thread.Pool = undefined;
			var wg = std.Thread.WaitGroup {};

			try pool.init(.{
				.allocator = misc.heap.allocator,
				.n_jobs = infos.len,
			});
			defer pool.deinit();
			for (infos, 0 ..) |_, i| {
				const slice = tbl[start ..][0 .. if (i < mod) div + 1 else div];
				start += slice.len;

				pool.spawnWg(&wg, threadedClear, .{slice});
			}
			pool.waitAndWork(&wg);
		}
	}

	pub fn free(self: *Table) void {
		if (self.tbl != null) {
			misc.heap.allocator.free(self.tbl.?);
			self.tbl = null;
		}
	}

	pub fn doAging(self: *Table) void {
		self.age += 1;
	}

	pub fn fetch(self: Table, key: Zobrist.Int) struct {?*Entry, bool} {
		const i = self.index(key) catch return .{null, false};
		const cluster = if (self.tbl != null) &self.tbl.?.ptr[i] else return .{null, false};
		const entries = [_]*Entry {
			@ptrCast(&cluster.entry0),
			@ptrCast(&cluster.entry1),
			@ptrCast(&cluster.entry2),
		};

		for (entries) |tte| {
			if (tte.key == @as(@TypeOf(tte.key), @truncate(key))) {
				return .{tte, true};
			}
		}

		var replace = entries[0];
		for (entries[1 ..]) |tte| {
			if (tte.age < self.age) {
				replace = tte;
			}
		}
		return .{replace, false};
	}
};
