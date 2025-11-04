const base = @import("base");
const std = @import("std");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const search = @import("search.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

pub const Entry = packed struct(u80) {
	key:	u16 = 0,
	depth:	u8 = 0,
	was_pv:	bool = false,
	flag:	Flag = .none,
	age:	u5 = 0,
	eval:	i16 = evaluation.score.none,
	score:	i16 = evaluation.score.none,
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
		return self.depth >= d and switch (self.flag) {
			.none => false,
			.upperbound => self.score <= a,
			.lowerbound => self.score >= b,
			.exact => true,
		};
	}
};

pub const Cluster = packed struct(u256) {
	et0:	Entry = .{},
	et1:	Entry = .{},
	et2:	Entry = .{},
	pad:	u16 = 0,
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

	pub fn clear(self: *Table) !void {
		const len = self.slice.len;
		if (len == 0) {
			return;
		}
		defer self.age = 0;

		const tn = uci.options.threads;
		const mod = len % tn;
		const div = len / tn;

		const threads = try base.heap.allocator.alloc(std.Thread, tn);
		defer base.heap.allocator.free(threads);

		var p = self.slice.ptr;
		for (0 .. tn) |i| {
			const l = if (i < mod) div + 1 else div;
			const s = p[0 .. l];
			p += l;
			threads[i] = try std.Thread.spawn(.{.allocator = base.heap.allocator},
			  threadedClear, .{s});
		}
		defer for (0 .. tn) |i| {
			std.Thread.join(threads[i]);
		};
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

		for (entries) |entry| {
			const tte = entry.*;
			if (tte.key != @as(@TypeOf(tte.key), @truncate(key)) or tte.flag == .none) {
				continue;
			}
			return .{entry, true};
		}

		var replace = entries[0];
		for (entries[1 ..]) |entry| {
			const rte = replace.*;
			const tte = entry.*;

			const ra: isize = rte.age;
			const rd: isize = rte.age;
			const ta: isize = tte.age;
			const td: isize = tte.age;

			if (rd - ra > td - ta) {
				replace = entry;
			}
		}
		return .{replace, false};
	}

	pub fn prefetch(self: Table, key: zobrist.Int) void {
		std.debug.assert(self.slice.len > 0);
		const i = self.index(key) / 2 * 2;
		const c = &self.slice[i];
		@prefetch(c, .{});
	}
};

pub var table: Table = .{};
