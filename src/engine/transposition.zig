const misc = @import("misc");
const std = @import("std");

const Zobrist = @import("Zobrist.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const search = @import("search.zig");

pub const Entry = packed struct(u80) {
	key:	u16,
	flag:	Flag,
	was_pv:	bool,
	age:	u5,
	depth:	search.Depth,
	eval:	evaluation.score.Int,
	score:	evaluation.score.Int,
	move:	movegen.Move,

	pub const Flag = enum(u2) {
		nil,
		lowerbound,
		exact,
		upperbound,
	};

	pub fn shouldTrust(self: Entry,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int,
	  depth: search.Depth) bool {
		if (self.depth < depth) {
			return false;
		}
		return self.flag == .exact
		  or (self.flag == .lowerbound and self.score < alpha)
		  or (self.flag == .upperbound and self.score > beta);
	}
};

pub const Cluster = packed struct(u256) {
	et0:	Entry,
	et1:	Entry,
	et2:	Entry,
	pad:	std.meta.Int(.unsigned, 256 - @bitSizeOf(Entry) * 3),
};

pub const Table = struct {
	slice:	?[]Cluster,
	age:	usize,

	pub const Error = error {
		Uninitialized,
	};

	fn index(self: Table, key: Zobrist.Int) !usize {
		const s = self.slice orelse return error.Uninitialized;
		const c = s.len;
		const m = std.math.mulWide(u64, c, key);
		return @truncate(m >> 64);
	}

	pub fn alloc(self: *Table, mb: usize) !void {
		const cnt = mb * 1024 * 1024 / @sizeOf(Cluster);

		if (self.slice) |s| {
			self.slice = try misc.heap.allocator.realloc(s, cnt);
		} else {
			self.slice = try misc.heap.allocator.alignedAlloc(Cluster, std.heap.page_size_max, cnt);
		}
	}

	pub fn clear(self: Table) void {
		if (self.slice) |s| {
			for (s) |*p| {
				p.* = @bitCast(@as(u256, std.math.minInt(u256)));
			}
		}
	}

	pub fn free(self: *Table) void {
		if (self.slice) |s| {
			misc.heap.allocator.free(s);
		}
	}

	pub fn fetch(self: Table, key: Zobrist.Int) !struct {*Entry, bool} {
		const i = try self.index(key);
		const s = self.slice orelse return error.Uninitialized;
		const cluster = &s[i];
		const entries = [_]*Entry {
			@ptrCast(&cluster.et0),
			@ptrCast(&cluster.et1),
			@ptrCast(&cluster.et2),
		};

		for (entries) |tte| {
			if (tte.key == @as(@TypeOf(tte.key), @truncate(key))) {
				return .{tte, true};
			}
		}

		var replace = entries[0];
		for (entries[1 ..]) |tte| {
			if (tte.age < replace.age) {
				replace = tte;
			}
		}
		return .{replace, false};
	}
};

// shadow decl blah blah blah
pub const PawnEntry = struct {
	pft:	evaluation.PawnFeatures,
	key:	Zobrist.Int,
	pad:	Zobrist.Int = 0xaa55aa55aa55aa55,
};

pub const PawnTable = struct {
	array:	[len]PawnEntry,

	const len = 8192 / @sizeOf(PawnEntry);

	fn index(self: PawnTable, key: Zobrist.Int) usize {
		_ = self;
		const m = std.math.mulWide(Zobrist.Int, len, key);
		return @truncate(m >> 64);
	}

	pub fn fetch(self: *PawnTable, key: Zobrist.Int) struct {*PawnEntry, bool} {
		const entry = &self.array[self.index(key)];
		return .{entry, entry.key == key};
	}
};

pub var table: Table = .{
	.slice = null,
	.age = 0,
};

pub var pawn_table = std.mem.zeroInit(PawnTable, .{});
