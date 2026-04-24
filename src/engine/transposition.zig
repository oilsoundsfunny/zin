const params = @import("params");
const std = @import("std");
const types = @import("types");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const Thread = @import("Thread.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

pub const Entry = packed struct(u64) {
    depth: u8 = 0,
    was_pv: bool = false,
    flag: Flag = .none,
    age: u5 = 0,
    eval: i16 = evaluation.score.none,
    score: i16 = evaluation.score.none,
    move: movegen.Move = .{},

    const flags_vec: @Vector(4, u64) = blk: {
        var entry: Entry = .{};
        entry = @bitCast(@as(u64, 0));
        entry.flag = @enumFromInt(std.math.maxInt(Flag.Tag));
        break :blk @splat(@bitCast(entry));
    };

    const none_vec: @Vector(4, u64) = blk: {
        var entry: Entry = .{};
        entry = @bitCast(@as(u64, 0));
        entry.flag = .none;
        break :blk @splat(@bitCast(entry));
    };

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

    fn value(self: Entry, tt_age: i32) i32 {
        const depth = params.values.tt_depth_w * self.depth;
        const age = params.values.tt_age_w * @mod(tt_age - self.age, 32);
        const pv = if (self.was_pv) params.values.tt_pv_w else evaluation.score.draw;
        const flag = switch (self.flag) {
            .none => evaluation.score.draw,
            inline else => |e| @field(params.values, "tt_" ++ @tagName(e) ++ "_w"),
        };
        const move = if (!self.move.isNone()) params.values.tt_move_w else evaluation.score.draw;
        return depth - age + pv + flag + move;
    }

    pub fn shouldTrust(
        self: Entry,
        a: evaluation.score.Int,
        b: evaluation.score.Int,
        d: Thread.Depth,
    ) bool {
        return self.depth >= d and switch (self.flag) {
            .none => false,
            .upperbound => self.score <= a,
            .lowerbound => self.score >= b,
            .exact => true,
        };
    }
};

const Cluster = struct {
    entries: [3]Entry = @splat(.{}),
    hashes: [4]u16 = @splat(0),
};

pub const Table = struct {
    clusters: []Cluster,
    age: u5,

    fn index(self: *const Table, key: zobrist.Int) usize {
        return zobrist.index(key, self.clusters.len);
    }

    fn madviseHugePage(self: *const Table) !void {
        if (@hasField(std.posix.MADV, "HUGEPAGE")) {
            try std.posix.madvise(
                @ptrCast(self.clusters.ptr),
                @sizeOf(Cluster) * self.clusters.len,
                std.posix.MADV.HUGEPAGE,
            );
        }
    }

    fn values(self: *const Table, vec: *align(32) const [4]Entry) @Vector(4, i32) {
        const depths: @Vector(4, i32) = .{
            params.values.tt_depth_w *% vec[0].depth,
            params.values.tt_depth_w *% vec[1].depth,
            params.values.tt_depth_w *% vec[2].depth,
            params.values.tt_depth_w *% vec[3].depth,
        };

        const ages: @Vector(4, i32) = .{
            params.values.tt_age_w *% @mod(@as(i32, self.age) - vec[0].age, 32),
            params.values.tt_age_w *% @mod(@as(i32, self.age) - vec[1].age, 32),
            params.values.tt_age_w *% @mod(@as(i32, self.age) - vec[2].age, 32),
            params.values.tt_age_w *% @mod(@as(i32, self.age) - vec[3].age, 32),
        };

        const pvs: @Vector(4, i32) = .{
            params.values.tt_pv_w *% @intFromBool(vec[0].was_pv),
            params.values.tt_pv_w *% @intFromBool(vec[1].was_pv),
            params.values.tt_pv_w *% @intFromBool(vec[2].was_pv),
            params.values.tt_pv_w *% @intFromBool(vec[3].was_pv),
        };

        const flags: @Vector(4, i32) = blk: {
            const lut: std.EnumArray(Entry.Flag, i32) = .init(.{
                .none = evaluation.score.draw,
                .upperbound = params.values.tt_upperbound_w,
                .lowerbound = params.values.tt_lowerbound_w,
                .exact = params.values.tt_exact_w,
            });
            break :blk .{
                lut.get(vec[0].flag), lut.get(vec[1].flag),
                lut.get(vec[2].flag), lut.get(vec[3].flag),
            };
        };

        const moves: @Vector(4, i32) = .{
            params.values.tt_move_w *% @intFromBool(!vec[0].move.isNone()),
            params.values.tt_move_w *% @intFromBool(!vec[1].move.isNone()),
            params.values.tt_move_w *% @intFromBool(!vec[2].move.isNone()),
            params.values.tt_move_w *% @intFromBool(!vec[3].move.isNone()),
        };

        const sum = depths - ages + pvs + flags + moves;
        return .{ sum[0], sum[1], sum[2], std.math.maxInt(i32) };
    }

    pub fn deinit(self: *Table, gpa: std.mem.Allocator) void {
        gpa.free(self.clusters);
        self.clusters = undefined;
        self.resetAge();
    }

    pub fn init(gpa: std.mem.Allocator, mb: ?usize) !Table {
        const options: Thread.Options = .{};
        const len = (mb orelse options.hash) * (1 << 20) / @sizeOf(Cluster);

        const page_size = std.heap.pageSize();
        const clusters = try gpa.alignedAlloc(Cluster, .fromByteUnits(page_size), len);

        const table: Table = .{ .clusters = clusters, .age = 0 };
        try table.madviseHugePage();
        return table;
    }

    pub fn realloc(self: *Table, gpa: std.mem.Allocator, mb: usize) !void {
        const len = (mb << 20) / @sizeOf(Cluster);
        self.clusters = try gpa.realloc(self.clusters, len);
        try self.madviseHugePage();
    }

    pub fn hashfull(self: *const Table) usize {
        var full: usize = 0;
        for (self.clusters[0..2000]) |*cluster| {
            inline for (cluster.entries[0..]) |*entry| {
                full += @intFromBool(entry.age == self.age);
            }
        }
        return (full + 3) / 6;
    }

    pub fn doAge(self: *Table) void {
        self.age +%= 1;
    }

    pub fn resetAge(self: *Table) void {
        self.age = 0;
    }

    pub fn read(self: *const Table, pos_hash: zobrist.Int) struct { Entry, bool } {
        const cluster = &self.clusters[self.index(pos_hash)];
        const entries: [4]Entry align(32) = .{
            @atomicLoad(Entry, &cluster.entries[0], .monotonic),
            @atomicLoad(Entry, &cluster.entries[1], .monotonic),
            @atomicLoad(Entry, &cluster.entries[2], .monotonic),
            .{},
        };
        const entries_vec: @Vector(4, u64) = @bitCast(entries);

        const short_hash: u16 = @truncate(pos_hash);
        const short_hashes: @Vector(4, u16) = @splat(short_hash);
        const hashes: @Vector(4, u16) = blk: {
            const p64: *const u64 = @alignCast(@ptrCast(cluster.hashes[0..].ptr));
            const load: @Vector(4, u16) = @bitCast(@atomicLoad(u64, p64, .monotonic));
            break :blk .{ load[0], load[1], load[2], ~short_hash };
        };

        const valids = entries_vec & Entry.flags_vec != Entry.none_vec;
        const matches = hashes == short_hashes;
        const hits = valids & matches;
        return if (std.simd.firstTrue(hits)) |i| .{ entries[i], true } else .{ entries[3], false };
    }

    pub fn write(self: *const Table, pos_hash: zobrist.Int, src: Entry) void {
        const cluster = &self.clusters[self.index(pos_hash)];
        const entries: [4]Entry align(32) = .{
            @atomicLoad(Entry, &cluster.entries[0], .monotonic),
            @atomicLoad(Entry, &cluster.entries[1], .monotonic),
            @atomicLoad(Entry, &cluster.entries[2], .monotonic),
            .{ .flag = .exact },
        };
        const entries_vec: @Vector(4, u64) = @bitCast(entries);

        const short_hash: u16 = @truncate(pos_hash);
        const short_hashes: @Vector(4, u16) = @splat(short_hash);
        const hashes: [4]u16 = blk: {
            const p: *const u64 = @alignCast(@ptrCast(cluster.hashes[0..].ptr));
            const load: [4]u16 = @bitCast(@atomicLoad(u64, p, .monotonic));
            break :blk .{ load[0], load[1], load[2], ~short_hash };
        };
        const hashes_vec: @Vector(4, u16) = @bitCast(hashes);

        const nones = entries_vec & Entry.flags_vec == Entry.none_vec;
        const matches = hashes_vec == short_hashes;
        const early = std.simd.firstTrue(nones | matches);

        const val = self.values(&entries);
        const min: @TypeOf(val) = @splat(@reduce(.Min, val));
        const late = std.simd.firstTrue(val == min);

        const i = early orelse late.?;
        var entry = entries[i];
        var move = entry.move;
        if (src.flag == .exact or
            hashes[i] != short_hash or
            entry.age != self.age or
            entry.depth < src.depth + 4)
        {
            move = if (src.move.isNone() and hashes[i] == short_hash) move else src.move;
            entry = src;
            entry.move = move;
            @atomicStore(Entry, &cluster.entries[i], entry, .monotonic);
            @atomicStore(u16, &cluster.hashes[i], short_hash, .monotonic);
        }
    }

    pub fn prefetch(self: *const Table, hash: zobrist.Int) void {
        std.debug.assert(self.clusters.len > 0);
        @prefetch(&self.clusters[self.index(hash)], .{});
    }
};
