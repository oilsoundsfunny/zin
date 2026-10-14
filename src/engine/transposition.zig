const builtin = @import("builtin");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const Thread = @import("Thread.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

const BigAtomicInt = @Int(.unsigned, big_atomic_bits);

const big_atomic_size = switch (builtin.cpu.arch) {
    .x86_64 => if (builtin.cpu.has(.x86, .cx16)) 16 else 8,
    .aarch64 => 8,
    else => @compileError("architecture not supported"),
};
const big_atomic_bits = big_atomic_size * 8;

pub const Entry = packed struct(u64) {
    was_pv: bool,
    flag: Flag,
    age: Age,
    depth: u8,
    eval: i16,
    score: i16,
    move: movegen.Move,

    pub const none: Entry = .{
        .was_pv = false,
        .flag = .none,
        .age = 0,
        .depth = 0,
        .eval = evaluation.score.none,
        .score = evaluation.score.none,
        .move = .none,
    };

    const flags_vec: @Vector(4, u64) = blk: {
        var entry: Entry = .none;
        entry.flag = @enumFromInt(std.math.maxInt(Flag.Tag));
        entry.eval = evaluation.score.draw;
        entry.score = evaluation.score.draw;
        break :blk @splat(@bitCast(entry));
    };

    const none_vec: @Vector(4, u64) = @splat(0);

    pub const Age = u5;

    pub const Flag = enum(u2) {
        none,
        upperbound,
        lowerbound,
        exact,

        const Tag = std.meta.Tag(Flag);

        fn tag(self: Flag) Tag {
            return @intFromEnum(self);
        }

        fn value(self: Flag) i32 {
            return switch (self) {
                .none => evaluation.score.draw,
                inline else => |e| @field(params.values, "tt_" ++ @tagName(e) ++ "_w"),
            };
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

pub const Cluster = struct {
    entries: [3]Entry,
    hashes: u64,

    pub const none: Cluster = .{ .entries = @splat(.none), .hashes = 0 };

    fn load(self: *const Cluster) Cluster {
        const quarters: [4]u64 = switch (big_atomic_bits) {
            128 => blk: {
                const p128: [*]const u128 = @ptrCast(@alignCast(self));
                const halves: [2]u128 = .{
                    @atomicLoad(u128, &p128[0], .monotonic),
                    @atomicLoad(u128, &p128[1], .monotonic),
                };
                break :blk @bitCast(halves);
            },
            64 => blk: {
                const p64: [*]const u64 = @ptrCast(@alignCast(self));
                break :blk .{
                    @atomicLoad(u64, &p64[0], .monotonic),
                    @atomicLoad(u64, &p64[1], .monotonic),
                    @atomicLoad(u64, &p64[2], .monotonic),
                    @atomicLoad(u64, &p64[3], .monotonic),
                };
            },
            else => @compileError("here's a nickel, kid. go buy yourself a real computer."),
        };
        return .{ .entries = @bitCast(quarters[0..3].*), .hashes = @bitCast(quarters[3]) };
    }

    fn paddedEntries(self: *const Cluster, padding: Entry) @Vector(4, u64) {
        return .{
            @bitCast(self.entries[0]),
            @bitCast(self.entries[1]),
            @bitCast(self.entries[2]),
            @bitCast(padding),
        };
    }
};

pub const Table = struct {
    clusters: []Cluster,
    age: Entry.Age,

    fn index(self: *const Table, key: zobrist.Int) usize {
        return zobrist.index(key, self.clusters.len);
    }

    fn madviseHugePage(self: *const Table) !void {
        const madv_info = @typeInfo(@TypeOf(std.posix.MADV));
        if (madv_info == .@"enum" or madv_info == .@"struct" or madv_info == .@"union") {
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

        const flags: @Vector(4, i32) = .{
            vec[0].flag.value(), vec[1].flag.value(), vec[2].flag.value(), vec[3].flag.value(),
        };

        const moves: @Vector(4, i32) = .{
            params.values.tt_move_w *% @intFromBool(!vec[0].move.isNone()),
            params.values.tt_move_w *% @intFromBool(!vec[1].move.isNone()),
            params.values.tt_move_w *% @intFromBool(!vec[2].move.isNone()),
            params.values.tt_move_w *% @intFromBool(!vec[3].move.isNone()),
        };

        const sum = depths + ages + pvs + flags + moves;
        return .{ sum[0], sum[1], sum[2], std.math.maxInt(i32) };
    }

    pub fn deinit(self: *Table, gpa: std.mem.Allocator) void {
        gpa.free(self.clusters);
        self.clusters = undefined;
        self.resetAge();
    }

    pub fn init(gpa: std.mem.Allocator, mb: ?usize) !Table {
        const options: Thread.Options = .init;
        const len = (mb orelse options.hash) * (1 << 20) / @sizeOf(Cluster);

        const page_size = std.heap.page_size_max;
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
            const loaded = cluster.load();
            inline for (loaded.entries[0..]) |entry| {
                full += @intFromBool(entry.flag != .none and entry.age == self.age);
            }
        }
        return (full + 3) / 6;
    }

    pub fn doAge(self: *Table) void {
        const Age = @TypeOf(self.age);
        var old = @atomicLoad(Age, &self.age, .monotonic);
        while (true) {
            old = @cmpxchgWeak(Age, &self.age, old, old +% 1, .monotonic, .monotonic) orelse break;
        }
    }

    pub fn resetAge(self: *Table) void {
        @atomicStore(@TypeOf(self.age), &self.age, 0, .monotonic);
    }

    pub fn read(self: *const Table, pos_hash: zobrist.Int) struct { Entry, bool } {
        const cluster = &self.clusters[self.index(pos_hash)];
        const loaded = cluster.load();

        const entries_vec: @Vector(4, u64) = loaded.paddedEntries(.none);
        const entries: [4]Entry align(32) = @bitCast(entries_vec);
        const valids = entries_vec & Entry.flags_vec != Entry.none_vec;

        const hashes = loaded.hashes;
        const short_hash: u21 = @truncate(pos_hash);
        const matches: @Vector(4, bool) = .{
            hashes & std.math.shl(u64, 0x1fffff, 21 * 0) == std.math.shl(u64, short_hash, 21 * 0),
            hashes & std.math.shl(u64, 0x1fffff, 21 * 1) == std.math.shl(u64, short_hash, 21 * 1),
            hashes & std.math.shl(u64, 0x1fffff, 21 * 2) == std.math.shl(u64, short_hash, 21 * 2),
            false,
        };

        const hits = valids & matches;
        return if (std.simd.firstTrue(hits)) |i| .{ entries[i], true } else .{ entries[3], false };
    }

    pub fn write(self: *const Table, pos_hash: zobrist.Int, src: Entry) void {
        const cluster = &self.clusters[self.index(pos_hash)];
        const loaded = cluster.load();

        const entries_vec: @Vector(4, u64) = loaded.paddedEntries(blk: {
            var entry: Entry = .none;
            entry.flag = .exact;
            break :blk entry;
        });
        const entries: [4]Entry align(32) = @bitCast(entries_vec);
        const nones = entries_vec & Entry.flags_vec == Entry.none_vec;

        const hashes = loaded.hashes;
        const short_hash: u21 = @truncate(pos_hash);
        const matches: @Vector(4, bool) = .{
            hashes & std.math.shl(u64, 0x1fffff, 21 * 0) == std.math.shl(u64, short_hash, 21 * 0),
            hashes & std.math.shl(u64, 0x1fffff, 21 * 1) == std.math.shl(u64, short_hash, 21 * 1),
            hashes & std.math.shl(u64, 0x1fffff, 21 * 2) == std.math.shl(u64, short_hash, 21 * 2),
            false,
        };
        const matches_arr: [4]bool = .{ matches[0], matches[1], matches[2], matches[3] };

        const val = self.values(&entries);
        const min: @TypeOf(val) = @splat(@reduce(.Min, val));

        const early = std.simd.firstTrue(nones | matches);
        const late = std.simd.firstTrue(val == min);
        const i: usize = early orelse late.?;

        var entry = entries[i];
        var move = entry.move;
        if (!matches_arr[i] or
            src.flag == .exact or
            entry.age != self.age or
            entry.depth < src.depth + 4)
        {
            move = if (src.move.isNone() and matches_arr[i]) move else src.move;
            entry = src;
            entry.move = move;
            const new_hashes = blk: {
                // zig fmt: off
                var new = loaded.hashes;
                new &= ~std.math.shl(u64, 0x1fffff,   21 * i);
                new |=  std.math.shl(u64, short_hash, 21 * i);
                break :blk new;
                // zig fmt: on
            };
            @atomicStore(Entry, &cluster.entries[i], entry, .monotonic);
            @atomicStore(u64, &cluster.hashes, new_hashes, .monotonic);
        }
    }

    pub fn prefetch(self: *const Table, hash: zobrist.Int) void {
        std.debug.assert(self.clusters.len > 0);
        @prefetch(&self.clusters[self.index(hash)], .{});
    }
};

comptime {
    if (@sizeOf(Cluster) != @sizeOf(u128) * 2) {
        @compileError(std.fmt.comptimePrint("unexpected @sizeOf(Cluster) = {d}", .{@sizeOf(Cluster)}));
    }
}
