const bitboard = @import("bitboard");
const nnue = @import("nnue");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const movegen = @import("movegen.zig");
const Thread = @import("Thread.zig");

pub const score = struct {
    const max = std.math.maxInt(Small);
    const min = std.math.minInt(Small);

    pub const Int = i32;
    pub const Small = i16;

    pub const Simd = @Vector(simd_len, Int);

    pub const List = struct {
        array: types.BoundedArray(Int, null, capacity),

        pub const capacity = movegen.Move.List.capacity;
        pub const init: List = .{ .array = .init };
    };

    pub const simd_len = std.simd.suggestVectorLength(Int) orelse 1;

    // zig fmt: off
    pub const mate  =  max;
    pub const mated = -max;
    pub const none  =  min;
    // zig fmt: on

    // zig fmt: off
    pub const win  = max - 1 - movegen.RootMove.capacity;
    pub const draw = 0;
    pub const loss = min + 1 + movegen.RootMove.capacity;
    // zig fmt: on

    fn wdlParams(m: Int) struct { f32, f32 } {
        // zig fmt: off
        const p_a: [4]f32 = .{  64.49100593,   8.70130556, -301.51837609, 466.62915918 };
        const p_b: [4]f32 = .{ -20.61031493, 155.98667782, -181.81035461, 154.21305171 };
        // zig fmt: on
        const x: f32 = @floatFromInt(std.math.clamp(m, 17, 78));

        var a: f32 = 0.0;
        var b: f32 = 0.0;
        for (p_a[0..], p_b[0..]) |pa, pb| {
            a = @mulAdd(f32, a, x / 58.0, pa);
            b = @mulAdd(f32, b, x / 58.0, pb);
        }

        return .{ a, b };
    }

    fn winrate(s: Int, mat: Int) f32 {
        const a, const b = wdlParams(mat);
        const x: f32 = @floatFromInt(s);
        const d: f32 = 1.0 + @exp((a - x) / b);
        return 1.0 / d;
    }

    pub fn isMate(s: Int) bool {
        return s == std.math.clamp(s, win, mate);
    }

    pub fn isMated(s: Int) bool {
        return s == std.math.clamp(s, mated, loss);
    }

    pub fn mateIn(ply: usize) Int {
        const i: Int = @intCast(ply);
        return mate - i;
    }

    pub fn matedIn(ply: usize) Int {
        const i: Int = @intCast(ply);
        return mated + i;
    }

    pub fn fromTT(s: Int, ply: usize) Int {
        var r = s;
        if (r < loss) {
            r += @intCast(ply);
        } else if (r > win) {
            r -= @intCast(ply);
        }
        return r;
    }

    pub fn toTT(s: Int, ply: usize) Int {
        var r = s;
        if (r < loss) {
            r -= @intCast(ply);
        } else if (r > win) {
            r += @intCast(ply);
        }
        return r;
    }

    pub fn clamp(s: Int) Int {
        return std.math.clamp(s, loss + 1, win - 1);
    }

    pub fn normalize(s: Int, mat: Int) Int {
        const a, _ = wdlParams(mat);
        const x: f32 = @floatFromInt(s);
        return @intFromFloat(x / a * 100.0);
    }

    pub fn wdl(s: Int, mat: Int) struct { f32, f32, f32 } {
        const w = winrate(s, mat);
        const l = winrate(-s, mat);
        return .{ w, std.math.clamp(1.0 - w - l, 0.0, 1.0), l };
    }

    pub fn withIndex(s: Int, i: u32) u32 {
        const o = 1 << 20;
        const h: u32 = @intCast(s + o);
        return h * 256 + i;
    }

    pub fn withIndices(s: Simd, i: @Vector(simd_len, u32)) @Vector(simd_len, u32) {
        const o: Simd = @splat(1 << 20);
        const h: @Vector(simd_len, u32) = @intCast(s +% o);
        const m: @Vector(simd_len, u32) = @splat(256);
        return h *% m +% i;
    }
};

pub const Stats = struct {
    cnt: u32,
    sum: i64,
    abs_sum: u64,
    sqr_sum: u64,
    max: score.Int,
    min: score.Int,

    fn init(eval: score.Int) Stats {
        return .{
            .cnt = 1,
            .sum = eval,
            .abs_sum = @intCast(eval * eval),
            .sqr_sum = @intCast(if (eval < 0) -eval else eval),
            .max = eval,
            .min = eval,
        };
    }

    fn add(self: Stats, other: Stats) Stats {
        return .{
            .cnt = self.cnt + other.cnt,
            .sum = self.sum + other.sum,
            .abs_sum = self.abs_sum + other.abs_sum,
            .sqr_sum = self.sqr_sum + other.sqr_sum,
            .max = @max(self.max, other.max),
            .min = @min(self.min, other.min),
        };
    }

    fn print(self: Stats, pool: *Thread.Pool) !void {
        const fcnt: f64 = @floatFromInt(self.cnt);
        const fabs: f64 = @floatFromInt(self.abs_sum);
        const time: f64 = @floatFromInt(pool.elapsed());

        const avg = fabs / fcnt;
        const pps = fcnt / time * std.time.ns_per_s;
        const scale = 955.8869178457139 / avg * nnue.network.Default.scale;

        try pool.io.writer().print(
            "processed {} positions @ {:.2} pps, abs mean {:.2}, scale {:.2}\n",
            .{ self.cnt, pps, avg, scale },
        );
        try pool.io.writer().flush();
    }

    pub fn collect(pool: *Thread.Pool, epd: []const u8) !void {
        pool.io.deinit(pool.gpa, pool.stdio);
        pool.io = try .init(pool.gpa, pool.stdio, epd, 65536, null, 65536);
        pool.now = .now(pool.stdio, .real);

        var board: Board = .init;
        var stats: Stats = .{
            .cnt = 0,
            .sum = 0,
            .abs_sum = 0,
            .sqr_sum = 0,
            .max = std.math.minInt(score.Int),
            .min = std.math.maxInt(score.Int),
        };

        while (pool.io.reader().takeDelimiterInclusive('\n')) |line| {
            board.parseFen(line[0 .. line.len - 1]) catch |err| {
                std.log.err("failed to parse fen '{s}': {t}", .{ line[0 .. line.len - 1], err });
                continue;
            };

            const eval = if (board.positions.last().isChecked()) continue else board.evaluate();
            stats = stats.add(.init(eval));
            if (stats.cnt % 1024 == 0) {
                try stats.print(pool);
            }
        } else |err| switch (err) {
            error.EndOfStream => try stats.print(pool),
            else => return err,
        }

        const fcnt: f64 = @floatFromInt(stats.cnt);
        const fsum: f64 = @floatFromInt(stats.sum);
        const fabs_sum: f64 = @floatFromInt(stats.abs_sum);
        const fsqr_sum: f64 = @floatFromInt(stats.sqr_sum);
        const fmax: f64 = @floatFromInt(stats.max);
        const fmin: f64 = @floatFromInt(stats.min);

        const mean = fsum / fcnt;
        const abs_mean = fabs_sum / fcnt;
        const variance = fsqr_sum / fcnt - mean * mean;
        const stddev = @sqrt(variance);

        try pool.io.writer().print("mean:     {}\n", .{mean});
        try pool.io.writer().print("abs mean: {}\n", .{abs_mean});
        try pool.io.writer().print("stddev:   {}\n", .{stddev});
        try pool.io.writer().print("max:      {}\n", .{fmax});
        try pool.io.writer().print("min:      {}\n", .{fmin});

        const scale = 955.8869178457139 / abs_mean * nnue.network.Default.scale;
        try pool.io.writer().print("scale:    {}\n", .{scale});
        try pool.io.writer().flush();
    }

    pub fn help(pool: *Thread.Pool, version_string: []const u8) !void {
        const fmt =
            \\zin-collect-eval {s}
            \\
            \\USAGE:
            \\    zin collect-eval <PATH>
            \\
        ;
        try pool.io.writer().print(fmt, .{version_string});
        try pool.io.writer().flush();
    }
};
