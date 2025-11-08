const std = @import("std");
const types = @import("types");

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
	allocator:	std.mem.Allocator,

	slice:	[]Cluster,
	age:	usize,

	fn threadedClear(slice: []Cluster) void {
		for (slice) |*cluster| {
			cluster.* = .{};
		}
	}

	fn index(self: *const Table, key: zobrist.Int) usize {
		return zobrist.index(key, self.slice.len);
	}

	pub fn deinit(self: *Table) void {
		self.allocator.free(self.slice);
		self.slice = &.{};
		self.resetAge();
	}

	pub fn init(allocator: std.mem.Allocator, mb: ?usize) !Table {
		const len = (mb orelse search.Options.zero.hash) * (1 << 20) / @sizeOf(Cluster);
		return .{
			.allocator = allocator,
			.slice = try allocator.alloc(Cluster, len),
			.age = 0,
		};
	}

	pub fn realloc(self: *Table, mb: usize) !void {
		const len = (mb << 20) / @sizeOf(Cluster);
		self.slice = try self.allocator.realloc(self.slice, len);
	}

	pub fn clear(self: *Table, tn: usize) !void {
		const len = self.slice.len;
		if (len == 0) {
			return;
		}

		const mod = len % tn;
		const div = len / tn;

		var p = self.slice.ptr;
		const threads = try self.allocator.alloc(std.Thread, tn);
		defer self.allocator.free(threads);

		for (0 .. tn) |i| {
			const l = if (i < mod) div + 1 else div;
			const s = p[0 .. l];

			p += l;
			threads[i] = try std.Thread.spawn(.{.allocator = self.allocator}, threadedClear, .{s});
		}

		defer for (0 .. tn) |i| {
			std.Thread.join(threads[i]);
		};
	}

	pub fn doAge(self: *Table) void {
		self.age += 1;
	}

	pub fn resetAge(self: *Table) void {
		self.age = 0;
	}

	pub fn fetch(self: *const Table, key: zobrist.Int) struct {*Entry, bool} {
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

	pub fn prefetch(self: *const Table, key: zobrist.Int) void {
		std.debug.assert(self.slice.len > 0);
		const i = self.index(key) / 2 * 2;
		const c = &self.slice[i];
		@prefetch(c, .{});
	}
};
