const base = @import("base");
const std = @import("std");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const search = @import("search.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

pub const Entry = packed struct(u80) {
	was_pv:	bool,
	flag:	Flag,
	age:	u5,
	depth:	u8,
	key:	u16,
	eval:	i16,
	score:	i16,
	move:	movegen.Move = movegen.Move.zero,

	pub const Flag = enum(u2) {
		none,
		upperbound,
		lowerbound,
		exact,

		const Tag = std.meta.Tag(Flag);

		fn tag(self: Flag) Tag {
			return @intFromEnum(self);
		}

		pub fn hasLower(self: Flag) bool {
			return self.tag() & Flag.lowerbound.tag() != 0;
		}

		pub fn hasUpper(self: Flag) bool {
			return self.tag() & Flag.upperbound.tag() != 0;
		}
	};

	pub fn shouldTrust(self: Entry,
	  a: evaluation.score.Int,
	  b: evaluation.score.Int,
	  d: search.Depth) bool {
		return if (self.depth < d) false else switch (self.flag) {
			.none => false,
			.upperbound => self.score <= a,
			.exact => true,
			.lowerbound => self.score >= b,
		};
	}
};

pub const Cluster = packed struct(u256) {
	et0:	Entry,
	et1:	Entry,
	et2:	Entry,
	pad:	u16,
};

pub const Table = struct {
	slice:	[]Cluster = &.{},
	age:	usize = 0,

	fn index(self: Table, key: zobrist.Int) usize {
		return zobrist.index(key, self.slice.len);
	}

	fn threadedClear(slice: []Cluster) void {
		for (slice) |*cluster| {
			cluster.* = @bitCast(@as(u256, 0));
		}
	}

	pub fn alloc(self: *Table, mb: usize) !void {
		const mem = std.math.shl(usize, mb, 20);
		const cnt = mem / @sizeOf(Cluster);
		self.slice = try base.heap.allocator.realloc(self.slice, cnt);
	}

	pub fn clear(self: Table) !void {
		const len = self.slice.len;
		if (len == 0) {
			return;
		}

		const tn = uci.options.threads;
		const mod = len % tn;
		const div = len / tn;

		var pool: std.Thread.Pool = undefined;
		var wg: std.Thread.WaitGroup = .{};

		try pool.init(.{
			.allocator = base.heap.allocator,
			.n_jobs = tn,
		});
		defer pool.deinit();

		var p = self.slice.ptr;
		for (0 .. tn) |i| {
			const l = if (i < mod) div + 1 else div;
			const s = p[0 .. l];
			p += l;
			pool.spawnWg(&wg, threadedClear, .{s});
		}
		pool.waitAndWork(&wg);
	}

	pub fn fetch(self: Table, key: zobrist.Int) struct {*Entry, bool} {
		std.debug.assert(self.slice.len > 0);
		const i = self.index(key);
		const cluster = &self.slice[i];
		const entries = [_]*Entry {
			@ptrCast(&cluster.et0),
			@ptrCast(&cluster.et1),
			@ptrCast(&cluster.et2),
		};

		for (entries) |tte| {
			if (tte.key != @as(@TypeOf(tte.key), @truncate(key)) or tte.flag == .none) {
				continue;
			}
			return .{tte, true};
		}

		var replace = entries[0];
		for (entries[1 ..]) |tte| {
			const ra: isize = replace.age;
			const rd: isize = replace.age;
			const ta: isize = tte.age;
			const td: isize = tte.age;

			if (rd - ra > td - ta) {
				replace = tte;
			}
		}
		return .{replace, false};
	}

	pub fn prefetch(self: Table, key: zobrist.Int) void {
		std.debug.assert(self.slice.len > 0);
		const i = self.index(key);
		const c = &self.slice[i];
		@prefetch(c, .{});
	}
};

pub var table: Table = .{};
