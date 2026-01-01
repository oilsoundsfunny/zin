const bitboard = @import("bitboard");
const nnue = @import("nnue");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const movegen = @import("movegen.zig");
const Thread = @import("Thread.zig");

pub const score = struct {
    const max = std.math.maxInt(i16);
    const min = std.math.minInt(i16);

    pub const Int = i32;

    pub const mate = 0 + max;
    pub const mated = 0 - max;
    pub const none = min;

    pub const win = 0 + (max - 1 - movegen.Move.Root.capacity);
    pub const draw = 0;
    pub const lose = 0 - (max - 1 - movegen.Move.Root.capacity);

    fn winrate(s: Int, mat: Int) Int {
        const p_a = [_]f32{ 6.87155862, -39.65226391, 90.68460352, 170.66996364 };
        const p_b = [_]f32{ -7.19890710, 56.13947185, -139.91091183, 182.81007427 };
        const fm: f32 = @floatFromInt(std.math.clamp(mat, 17, 78));
        const fs: f32 = @floatFromInt(s);

        var a: f32 = 0.0;
        var b: f32 = 0.0;
        for (p_a[0..], p_b[0..]) |param_a, param_b| {
            a = @mulAdd(f32, a, fm / 58.0, param_a);
            b = @mulAdd(f32, b, fm / 58.0, param_b);
        }

        const num = 1000.0;
        const den = 1.0 + @exp((a - fs) / b);
        return @intFromFloat(num / den);
    }

    pub fn isMate(s: Int) bool {
        return s == std.math.clamp(s, win, mate);
    }

    pub fn isMated(s: Int) bool {
        return s == std.math.clamp(s, mated, lose);
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
        if (r < lose) {
            r += @intCast(ply);
        } else if (r > win) {
            r -= @intCast(ply);
        }
        return r;
    }

    pub fn toTT(s: Int, ply: usize) Int {
        var r = s;
        if (r < lose) {
            r -= @intCast(ply);
        } else if (r > win) {
            r += @intCast(ply);
        }
        return r;
    }

    pub fn normalize(s: Int, mat: Int) Int {
        const params = [_]f32{
            6.87155862, -39.65226391, 90.68460352, 170.66996364,
        };
        const fm: f32 = @floatFromInt(@max(mat, 10));
        const fs: f32 = @floatFromInt(s);

        var x = params[0];
        for (params[1..]) |k| {
            x = @mulAdd(f32, x, fm / 58.0, k);
        }
        return @intFromFloat(@round(100.0 * fs / x));
    }

    pub fn wdl(s: Int, mat: Int) struct { Int, Int, Int } {
        const w = winrate(s, mat);
        const l = winrate(-s, mat);
        return .{ w, 1000 - w - l, l };
    }
};

pub fn printStats(pool: *Thread.Pool, path: []const u8) !void {
    pool.io.deinit(pool.allocator);
    pool.io = try types.IO.init(pool.allocator, path, 65536, null, 65536);

    var board: Board = .{};
    var cnt: u32 = 0;
    var sum: i64 = 0;
    var abs_sum: u64 = 0;
    var sq_sum: u64 = 0;
    var max: score.Int = std.math.minInt(score.Int);
    var min: score.Int = std.math.maxInt(score.Int);

    while (pool.io.reader().takeDelimiterInclusive('\n')) |line| {
        board.parseFen(line) catch continue;
        if (board.top().isChecked()) {
            continue;
        }

        const eval = board.evaluate();
        cnt += 1;
        sum += eval;
        abs_sum += @intCast(if (eval < 0) -eval else eval);
        sq_sum += @intCast(eval * eval);
        max = @max(max, eval);
        min = @min(min, eval);

        if (cnt % 1024 == 0) {
            try pool.io.writer().print("processed {d} positions\n", .{cnt});
            try pool.io.writer().flush();
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    const fcnt: f64 = @floatFromInt(cnt);
    const fsum: f64 = @floatFromInt(sum);
    const fabs_sum: f64 = @floatFromInt(abs_sum);
    const fsq_sum: f64 = @floatFromInt(sq_sum);
    const fmax: f64 = @floatFromInt(max);
    const fmin: f64 = @floatFromInt(min);

    const mean = fsum / fcnt;
    const abs_mean = fabs_sum / fcnt;
    const variance = fsq_sum / fcnt - mean * mean;
    const stddev = @sqrt(variance);

    try pool.io.writer().print("    mean: {d}\n", .{mean});
    try pool.io.writer().print("abs mean: {d}\n", .{abs_mean});
    try pool.io.writer().print("  stddev: {d}\n", .{stddev});
    try pool.io.writer().print("     max: {d}\n", .{fmax});
    try pool.io.writer().print("     min: {d}\n", .{fmin});

    const scale = 1087.1360293824707 / abs_mean * nnue.arch.scale;
    try pool.io.writer().print("   scale: {d}\n", .{scale});
    try pool.io.writer().flush();
}
