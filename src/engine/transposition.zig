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
	move:	movegen.Move = .{},

	pub const Flag = enum(u2) {
		none,
		upperbound,
		lowerbound,
		exact,

		const Tag = std.meta.Tag(Flag);

		fn tag(self: Flag) Tag {
			return @intFromEnum(self);
		}

		pub fn flip(self: Flag) Flag {
			return switch (self) {
				.upperbound => .lowerbound,
				.lowerbound => .upperbound,
				else => self,
			};
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
	age:	u5,

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
		self.slice = undefined;
		self.resetAge();
	}

	pub fn init(allocator: std.mem.Allocator, mb: ?usize) !Table {
		const options: search.Options = .{};
		const len = (mb orelse options.hash) * (1 << 20) / @sizeOf(Cluster);
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

		if (tn == 1) {
			threadedClear(self.slice);
			return;
		}

		const mod = len % tn;
		const div = len / tn;

		var p = self.slice.ptr;
		const threads = try self.allocator.alloc(std.Thread, tn);
		defer self.allocator.free(threads);

		const first_slice = p[0 .. div];
		p += div;

		for (1 .. tn) |i| {
			const l = if (i < mod) div + 1 else div;
			const s = p[0 .. l];

			p += l;
			threads[i] = try std.Thread.spawn(.{.allocator = self.allocator}, threadedClear, .{s});
		}
		threadedClear(first_slice);

		defer for (1 .. tn) |i| {
			std.Thread.join(threads[i]);
		};
	}

	pub fn hashfull(self: *const Table) usize {
		var full: usize = 0;
		for (self.slice[0 .. 1000]) |cluster| {
			full += @intFromBool(cluster.et0 != @as(Entry, .{}));
			full += @intFromBool(cluster.et1 != @as(Entry, .{}));
			full += @intFromBool(cluster.et2 != @as(Entry, .{}));
		}
		return full / 3;
	}

	pub fn doAge(self: *Table) void {
		self.age +%= 1;
	}

	pub fn resetAge(self: *Table) void {
		self.age = 0;
	}

	pub fn read(self: *const Table, key: zobrist.Int, dst: *Entry) bool {
		const i = self.index(key);
		const cluster = &self.slice[i];
		const entries = [_]*align(2) Entry {
			@ptrCast(&cluster.et0),
			@ptrCast(&cluster.et1),
			@ptrCast(&cluster.et2),
		};

		for (entries) |entry| {
			const tte = entry.*;
			if (tte.flag != .none and tte.key == @as(@TypeOf(tte.key), @truncate(key))) {
				dst.* = tte;
				return true;
			}
		} else return false;
	}

	pub fn write(self: *const Table, key: zobrist.Int, save: Entry) void {
		const i = self.index(key);
		const cluster = &self.slice[i];
		const entries = [_]*align(2) Entry {
			@ptrCast(&cluster.et0),
			@ptrCast(&cluster.et1),
			@ptrCast(&cluster.et2),
		};

		var min: isize = std.math.maxInt(isize);
		var opt_replace: ?*align(2) Entry = null;
		const short_key: @TypeOf(opt_replace.?.key) = @truncate(key);

		for (entries) |entry| {
			const tte = entry.*;
			if (tte.key == short_key or tte.flag == .none) {
				opt_replace = entry;
				break;
			}

			const cycle = 1 << @bitSizeOf(@TypeOf(self.age));
			const age: u8 = self.age;

			const ta: isize = (cycle + age - tte.age) % cycle;
			const td: isize = tte.depth;
			const rel_age = td - ta * 2;

			if (rel_age < min) {
				opt_replace = entry;
				min = rel_age;
			}
		}

		const replace = opt_replace orelse std.debug.panic("no tt replacement found", .{});
		var tte = replace.*;
		var ttm = tte.move;

		if (save.flag != .exact
		  and tte.key == short_key
		  and tte.age == self.age
		  and tte.depth >= save.depth + 4) {
			return;
		}

		ttm = if (save.move.isNone() and tte.key == short_key) ttm else save.move;
		tte = save;
		tte.move = ttm;
		replace.* = tte;
	}

	pub fn prefetch(self: *const Table, key: zobrist.Int) void {
		std.debug.assert(self.slice.len > 0);
		const i = self.index(key) / 2 * 2;
		const c = &self.slice[i];
		@prefetch(c, .{});
	}
};
