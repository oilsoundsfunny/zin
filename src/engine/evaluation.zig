const bitboard = @import("bitboard");
const nnue = @import("nnue");
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
        array: types.BoundedArray(Int, null, capacity) = .{},

        pub const capacity = movegen.Move.List.capacity;
    };

    pub const simd_len = std.simd.suggestVectorLength(Int) orelse 1;

    // zig fmt: off
    pub const mate  =  max;
    pub const mated = -max;
    pub const none  =  min;
    // zig fmt: on

    // zig fmt: off
    pub const win  = max - 1 - movegen.RootMove.max_len;
    pub const draw = 0;
    pub const loss = min + 1 + movegen.RootMove.max_len;
    // zig fmt: on

    fn wdlParams(m: Int) struct { f32, f32 } {
        // zig fmt: off
        const p_a: [4]f32 = .{ -125.94470275,  361.13329132, -436.02351672, 465.82175860 };
        const p_b: [4]f32 = .{   78.70983897, -167.31729756,  143.00239659,  57.40055307 };
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

pub fn printStats(pool: *Thread.Pool, path: []const u8) !void {
    pool.io.deinit(pool.allocator);
    pool.io = try types.IO.init(pool.allocator, path, 65536, null, 65536);
    pool.timer.reset();

    const board = try pool.allocator.create(Board);
    defer pool.allocator.destroy(board);

    var cnt: u32 = 0;
    var sum: i64 = 0;
    var abs_sum: u64 = 0;
    var sq_sum: u64 = 0;
    var max: score.Int = std.math.minInt(score.Int);
    var min: score.Int = std.math.maxInt(score.Int);

    while (pool.io.reader().takeDelimiterInclusive('\n')) |line| {
        board.parseFen(line) catch continue;

        const pos = board.positions.last();
        if (pos.isChecked()) {
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
            const fcnt: f64 = @floatFromInt(cnt);
            const fabs: f64 = @floatFromInt(abs_sum);
            const time: f64 = @floatFromInt(pool.timer.read());

            const avg = fabs / fcnt;
            const pps = fcnt / time * std.time.ns_per_s;
            const scale = 902.8203897476196 / avg * 360.0;

            try pool.io.writer().print(
                "processed {} positions @ {:.2} pps, abs mean {:.2}, scale {:.2}\n",
                .{ cnt, pps, avg, scale },
            );
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

    try pool.io.writer().print("mean:     {}\n", .{mean});
    try pool.io.writer().print("abs mean: {}\n", .{abs_mean});
    try pool.io.writer().print("stddev:   {}\n", .{stddev});
    try pool.io.writer().print("max:      {}\n", .{fmax});
    try pool.io.writer().print("min:      {}\n", .{fmin});

    const scale = 902.8203897476196 / abs_mean * 360.0;
    try pool.io.writer().print("scale:    {}\n", .{scale});
    try pool.io.writer().flush();
}
