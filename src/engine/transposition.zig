const params = @import("params");
const std = @import("std");
const types = @import("types");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const Thread = @import("Thread.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

pub const Entry = packed struct(u80) {
    key: u16 = 0,
    depth: u8 = 0,
    was_pv: bool = false,
    flag: Flag = .none,
    age: u5 = 0,
    eval: i16 = evaluation.score.none,
    score: i16 = evaluation.score.none,
    move: movegen.Move = .{},

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

pub const Cluster = packed struct(u256) {
    et0: Entry = .{},
    et1: Entry = .{},
    et2: Entry = .{},
    pad: u16 = 0,
};

pub const Table = struct {
    slice: []Cluster,
    age: u5,

    fn index(self: *const Table, key: zobrist.Int) usize {
        return zobrist.index(key, self.slice.len);
    }

    pub fn deinit(self: *Table, allocator: std.mem.Allocator) void {
        allocator.free(self.slice);
        self.slice = undefined;
        self.resetAge();
    }

    pub fn init(allocator: std.mem.Allocator, mb: ?usize) !Table {
        const options: Thread.Options = .{};
        const len = (mb orelse options.hash) * (1 << 20) / @sizeOf(Cluster);
        return .{
            .slice = try allocator.alloc(Cluster, len),
            .age = 0,
        };
    }

    pub fn realloc(self: *Table, allocator: std.mem.Allocator, mb: usize) !void {
        const len = (mb << 20) / @sizeOf(Cluster);
        self.slice = try allocator.realloc(self.slice, len);
    }

    pub fn hashfull(self: *const Table) usize {
        var full: usize = 0;
        for (self.slice[0..2000]) |*cluster| {
            inline for (0..3) |i| {
                const name = std.fmt.comptimePrint("et{d}", .{i});
                const entry: *align(2) Entry = @ptrCast(&@field(cluster, name));
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

    pub fn read(self: *const Table, key: zobrist.Int, dst: *Entry) bool {
        const i = self.index(key);
        const cluster = &self.slice[i];
        const entries = [_]*align(2) Entry{
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
        const entries = [_]*align(2) Entry{
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

            if (tte.value(self.age) < min) {
                opt_replace = entry;
                min = tte.value(self.age);
            }
        }

        const replace = opt_replace orelse std.debug.panic("no tt replacement found", .{});
        var tte = replace.*;
        var ttm = tte.move;

        if (save.flag != .exact and
            tte.key == short_key and
            tte.age == self.age and
            tte.depth >= save.depth + 4)
        {
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
