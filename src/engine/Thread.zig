const builtin = @import("builtin");
const params = @import("params");
const selfplay = @import("selfplay");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const transposition = @import("transposition.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

const Thread = @This();

const Node = transposition.Entry.Flag;

const Job = union(Tag) {
    bench: void,
    clear_hash: void,
    datagen: selfplay.Request,
    go: void,
    quit: void,
    reset: *Pool,
    sleep: void,

    const Tag = enum { bench, clear_hash, datagen, go, quit, reset, sleep };
};

const cache_line = std.atomic.cache_line;
const page_size = std.heap.page_size_max;

const has_debuginfo = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

pub const Depth = evaluation.score.Int;

pub const Pool = struct {
    gpa: std.mem.Allocator,
    handles: std.ArrayList(std.Thread),
    threads: std.ArrayList(Thread),

    stdio: std.Io,
    cond: std.Io.Condition,
    mtx: std.Io.Mutex,
    now: std.Io.Timestamp,

    searching: bool align(cache_line),
    sleeping: bool align(cache_line),
    stopped: bool align(cache_line),

    pawn_corrhist: []align(page_size) hist.Corr.Pawn,
    minor_corrhist: []align(page_size) hist.Corr.Minor,
    major_corrhist: []align(page_size) hist.Corr.Major,
    nonpawn_corrhist: []align(page_size) hist.Corr.NonPawn,

    limits: Limits align(cache_line),
    opts: Options align(cache_line),

    io: types.IO,
    tt: transposition.Table,

    fn wait(self: *Pool) void {
        for (self.threads.items) |*thread| {
            thread.wait();
        }
    }

    fn wake(self: *Pool, job: Job) void {
        for (self.threads.items) |*thread| {
            thread.wake(job);
        }
    }

    pub fn create(gpa: std.mem.Allocator, stdio: std.Io) !*Pool {
        const pool = try gpa.create(Pool);
        pool.* = .{
            .gpa = gpa,
            .handles = try .initCapacity(gpa, 1),
            .threads = try .initCapacity(gpa, 1),

            .stdio = stdio,
            .cond = .init,
            .mtx = .init,
            .now = .now(stdio, .real),

            .searching = false,
            .sleeping = false,
            .stopped = true,

            .pawn_corrhist = try hist.Corr.alloc(gpa, hist.Corr.Pawn, 1),
            .minor_corrhist = try hist.Corr.alloc(gpa, hist.Corr.Minor, 1),
            .major_corrhist = try hist.Corr.alloc(gpa, hist.Corr.Major, 1),
            .nonpawn_corrhist = try hist.Corr.alloc(gpa, hist.Corr.NonPawn, 1),

            .limits = .init,
            .opts = .init,

            .io = try .init(gpa, stdio, null, 65536, null, 65536),
            .tt = try .init(gpa, null),
        };

        const board = try gpa.create(Board);
        try board.parseFen(Board.Position.startpos);
        defer gpa.destroy(board);

        _ = try pool.handles.addOneBounded();
        _ = try pool.threads.addOneBounded();

        try pool.spawn();
        pool.setBoard(board, false);
        pool.clearHash();
        return pool;
    }

    pub fn destroy(self: *Pool) void {
        self.join();
        self.threads.deinit(self.gpa);

        self.gpa.free(self.pawn_corrhist);
        self.gpa.free(self.minor_corrhist);
        self.gpa.free(self.major_corrhist);
        self.gpa.free(self.nonpawn_corrhist);

        self.io.deinit(self.gpa, self.stdio);
        self.tt.deinit(self.gpa);

        self.gpa.destroy(self);
    }

    pub fn spawn(self: *Pool) !void {
        const config: std.Thread.SpawnConfig = .{ .allocator = self.gpa };
        for (self.handles.items, self.threads.items) |*handle, *thread| {
            // TODO: let threads reset their own data
            thread.* = .init;
            thread.pool = self;
            handle.* = try std.Thread.spawn(config, Thread.loop, .{thread});
        }
    }

    pub fn stop(self: *Pool) void {
        if (self.searching) {
            self.stopped = true;
            self.wait();
        }
    }

    pub fn join(self: *Pool) void {
        self.stop();
        self.wake(.quit);
        for (self.handles.items) |*handle| {
            handle.join();
        }
    }

    pub fn realloc(self: *Pool, num: usize) !void {
        const prev_num = self.threads.items.len;
        if (prev_num == num) {
            return;
        }

        const cpu_count = std.Thread.getCpuCount() catch 1;
        if (num > cpu_count) {
            return error.ConcurrencyUnavailable;
        }

        self.join();

        const board = try self.gpa.create(Board);
        defer self.gpa.destroy(board);
        board.* = self.threads.items[0].board;

        try self.handles.resize(self.gpa, num);
        try self.threads.resize(self.gpa, num);

        const corrhist_len = hist.Corr.per_thread * num;
        self.pawn_corrhist = try self.gpa.realloc(self.pawn_corrhist, corrhist_len);
        self.minor_corrhist = try self.gpa.realloc(self.minor_corrhist, corrhist_len);
        self.major_corrhist = try self.gpa.realloc(self.major_corrhist, corrhist_len);
        self.nonpawn_corrhist = try self.gpa.realloc(self.nonpawn_corrhist, corrhist_len);

        try self.spawn();
        self.setBoard(board, self.opts.frc);
    }

    pub fn reset(self: *Pool) !void {
        self.limits = .init;
        self.now = .now(self.stdio, .real);
        self.wake(.{ .reset = self });
        for (self.threads.items) |*thread| {
            self.mtx.lockUncancelable(self.stdio);
            while (thread.job != .sleep) {
                self.cond.waitUncancelable(self.stdio, &self.mtx);
            }
            self.mtx.unlock(self.stdio);
        }
    }

    pub fn nodes(self: *const Pool) u64 {
        var n: u64 = 0;
        for (self.threads.items) |*thread| {
            n += thread.nodes;
        }
        return n;
    }

    pub fn setBoard(self: *Pool, board: *const Board, frc: bool) void {
        defer self.setFRC(frc);
        for (self.threads.items) |*thread| {
            thread.board = board.*;
        }
    }

    pub fn setFRC(self: *Pool, frc: bool) void {
        self.opts.frc = frc;
        for (self.threads.items) |*thread| {
            thread.board.frc = frc;
        }
    }

    pub fn bench(self: *Pool) u64 {
        self.stop();
        self.searching = true;
        self.stopped = false;
        self.wake(.bench);
        self.wait();
        return self.nodes();
    }

    pub fn clearHash(self: *Pool) void {
        self.stop();
        self.wake(.clear_hash);
        self.wait();
    }

    pub fn datagen(self: *Pool, rq: selfplay.Request) !void {
        self.stop();
        self.now = .now(self.stdio, .real);
        self.searching = true;
        self.stopped = false;
        self.wake(.{ .datagen = rq });
        self.wait();
    }

    pub fn search(self: *Pool) !void {
        self.stop();
        self.searching = true;
        self.stopped = false;
        self.wake(.go);
    }

    pub fn elapsedNanosecs(self: *const Pool) u64 {
        const now: std.Io.Timestamp = .now(self.stdio, .real);
        return @intCast(self.now.durationTo(now).toNanoseconds());
    }
};

pub const Limits = struct {
    infinite: bool,
    depth: ?Depth,
    movetime: ?u64,

    hard_nodes: ?u64,
    soft_nodes: ?u64,

    incr: std.EnumMap(types.Color, u64),
    time: std.EnumMap(types.Color, u64),

    pub const init: Limits = .{
        .infinite = true,
        .depth = null,
        .movetime = null,
        .hard_nodes = null,
        .soft_nodes = null,
        .incr = .init(.{}),
        .time = .init(.{}),
    };

    pub fn set(self: *Limits, overhead: u64, stm: types.Color) void {
        const has_clock = self.incr.get(stm) != null and self.time.get(stm) != null;

        const from_movetime = if (self.movetime) |mt| mt -| overhead else std.math.maxInt(u64);
        const from_clock = if (!has_clock) std.math.maxInt(u64) else blk: {
            const incr = self.incr.get(stm).?;
            const time = self.time.get(stm).?;

            const im: u64 = @intCast(params.values.tm_incr_mult);
            const tm: u64 = @intCast(params.values.tm_time_mult);

            break :blk @divTrunc(time * tm + incr * im, 1024) -| overhead;
        };
        const min_time = @min(from_movetime, from_clock);

        self.movetime = if (min_time < std.math.maxInt(u64)) min_time else null;
        self.infinite = self.depth == null and
            self.movetime == null and
            self.soft_nodes == null and
            self.hard_nodes == null;
    }
};

pub const Options = struct {
    frc: bool,
    minimal: bool,
    show_wdl: bool,
    soft_nodes: bool,
    hash: usize,
    threads: usize,
    overhead: u64,

    pub const init: Options = .{
        .frc = false,
        .minimal = false,
        .show_wdl = false,
        .soft_nodes = false,
        .hash = 64,
        .threads = 1,
        .overhead = 10,
    };
};

pub const hist = struct {
    const Quiet = [color_n][ptype_n][square_n]Int;
    const Noisy = [color_n][ptype_n][square_n][ptype_n]Int;
    const Cont = [4][color_n][ptype_n][square_n][ptype_n][square_n]Int;

    const Corr = enum {
        pawn,
        minor,
        major,
        nonpawn,

        const Pawn = [color_n]Int;
        const Minor = Pawn;
        const Major = Pawn;
        const NonPawn = [color_n][color_n]Int;

        const per_thread = 65536;

        const values = std.enums.values(Corr);

        fn alloc(gpa: std.mem.Allocator, comptime T: type, threads: usize) ![]align(page_size) T {
            return gpa.alignedAlloc(T, .fromByteUnits(page_size), per_thread * threads);
        }
    };

    const color_n = 1 << types.Color.int_info.bits;
    const ptype_n = 1 << types.Ptype.int_info.bits;
    const square_n = 1 << types.Square.int_info.bits;

    pub const Int = i16;

    pub const min = std.math.minInt(Int) / 2;
    pub const max = -min;

    fn quietBonus(d: Depth) evaluation.score.Int {
        const v =
            params.values.quiethist_bonus_quad * d * d +
            params.values.quiethist_bonus_mult * d +
            params.values.quiethist_bonus_bias;
        return @min(v, params.values.quiethist_max_bonus);
    }

    fn quietMalus(d: Depth) evaluation.score.Int {
        const v =
            params.values.quiethist_malus_quad * d * d +
            params.values.quiethist_malus_mult * d +
            params.values.quiethist_malus_bias;
        return @min(v, params.values.quiethist_max_malus);
    }

    fn noisyBonus(d: Depth) evaluation.score.Int {
        const v =
            params.values.noisyhist_bonus_quad * d * d +
            params.values.noisyhist_bonus_mult * d +
            params.values.noisyhist_bonus_bias;
        return @min(v, params.values.noisyhist_max_bonus);
    }

    fn noisyMalus(d: Depth) evaluation.score.Int {
        const v =
            params.values.noisyhist_malus_quad * d * d +
            params.values.noisyhist_malus_mult * d +
            params.values.noisyhist_malus_bias;
        return @min(v, params.values.noisyhist_max_malus);
    }

    fn gravity(p: *Int, dx: evaluation.score.Int) void {
        const clamped = std.math.clamp(dx, min, max);
        const abs = if (clamped < 0) -clamped else clamped;

        const curr: evaluation.score.Int = p.*;
        const next = curr + clamped - @divTrunc(curr * abs, max);
        p.* = @intCast(next);
    }
};

pool: *Pool,
job: Job,
board: Board,

nodes: u64,
tbhits: u64,
tthits: u64,

depth: Depth,
seldepth: Depth,
root_moves: movegen.RootMove.List,

nmp_verif: bool,
quiethist: hist.Quiet,
noisyhist: hist.Noisy,
conthist: hist.Cont,

pub const init: Thread = .{
    .pool = undefined,
    .job = .sleep,
    .board = .init,

    .nodes = 0,
    .tbhits = 0,
    .tthits = 0,

    .depth = 0,
    .seldepth = 0,
    .root_moves = .{ .array = .init },

    .nmp_verif = false,
    .quiethist = @splat(@splat(@splat(0))),
    .noisyhist = @splat(@splat(@splat(@splat(0)))),
    .conthist = @splat(@splat(@splat(@splat(@splat(@splat(0)))))),
};

fn loop(self: *Thread) !void {
    const cond = &self.pool.cond;
    const mtx = &self.pool.mtx;
    const stdio = self.pool.stdio;

    while (true) {
        mtx.lockUncancelable(stdio);
        while (self.job == .sleep) {
            cond.signal(stdio);
            cond.waitUncancelable(stdio, mtx);
        }
        mtx.unlock(stdio);

        defer self.job = .sleep;
        switch (self.job) {
            .bench, .go => try self.search(),
            .clear_hash => self.clearHash(),
            .datagen => try self.datagen(),
            .quit => return,
            .reset => try self.reset(),
            .sleep => {},
        }
    }
}

fn wait(self: *Thread) void {
    const cond = &self.pool.cond;
    const mtx = &self.pool.mtx;
    const stdio = self.pool.stdio;

    mtx.lockUncancelable(stdio);
    while (self.job != .sleep) {
        cond.waitUncancelable(stdio, mtx);
    }
    mtx.unlock(stdio);

    if (self == &self.pool.threads.items[0]) {
        self.pool.searching = false;
    }
}

fn wake(self: *Thread, job: Job) void {
    const cond = &self.pool.cond;
    const mtx = &self.pool.mtx;
    const stdio = self.pool.stdio;

    mtx.lockUncancelable(stdio);
    self.job = job;
    cond.signal(stdio);
    mtx.unlock(stdio);
}

fn quietHistPtr(
    self: anytype,
    move: movegen.Move,
) types.SameMutPtr(@TypeOf(self), *Thread, *hist.Int) {
    const sp = self.board.positions.last().getSq(move.src);
    return &self.quiethist[sp.color().int()][sp.ptype().int()][move.dst.int()];
}

fn noisyHistPtr(
    self: anytype,
    move: movegen.Move,
) types.SameMutPtr(@TypeOf(self), *Thread, *hist.Int) {
    const pos = self.board.positions.last();
    const sp = pos.getSq(move.src);
    const dp = switch (pos.getSq(move.dst)) {
        .none => types.Ptype.num,
        else => |p| p.ptype().int(),
    };

    return &self.noisyhist[sp.color().int()][sp.ptype().int()][move.dst.int()][dp];
}

fn contHistPtr(
    self: anytype,
    move: movegen.Move,
    ply: usize,
) ?types.SameMutPtr(@TypeOf(self), *Thread, *hist.Int) {
    const pos: *const Board.Position = self.board.positions.last();
    const this_p = pos.getSq(move.src).ptype().int();
    const this_d = move.dst.int();

    const hist_pos = if (self.board.positions.len > ply) pos.before(ply) else return null;
    const hist_p = switch (hist_pos.src_piece) {
        .none => types.Ptype.num,
        else => |p| p.ptype().int(),
    };
    const hist_d = hist_pos.move.dst.int();

    const stm = pos.stm.int();
    return &self.conthist[ply / 2][stm][hist_p][hist_d][this_p][this_d];
}

fn correctEval(self: *const Thread, eval: evaluation.score.Int) evaluation.score.Int {
    const pos = self.board.positions.last();
    const stm = pos.stm;

    var correction: @TypeOf(eval) = evaluation.score.draw;
    inline for (hist.Corr.values) |t| {
        correction += switch (t) {
            .nonpawn => blk: {
                const len = hist.Corr.per_thread * self.pool.threads.items.len;
                const keys = pos.nonpawn_keys;

                const stm_i = zobrist.index(keys.getPtrConst(stm).*, len);
                const stm_c = self.pool.nonpawn_corrhist[stm_i][stm.int()][stm.int()] *
                    params.values.corr_nonpawn_stm_w;

                const ntm = stm.flip();
                const ntm_i = zobrist.index(keys.getPtrConst(ntm).*, len);
                const ntm_c = self.pool.nonpawn_corrhist[ntm_i][stm.int()][ntm.int()] *
                    params.values.corr_nonpawn_ntm_w;

                break :blk stm_c + ntm_c;
            },

            else => blk: {
                const key = switch (t) {
                    .pawn => pos.pawn_key,
                    .minor => pos.minor_key,
                    .major => pos.major_key,
                    else => unreachable,
                };
                const len = hist.Corr.per_thread * self.pool.threads.items.len;
                const idx = zobrist.index(key, len);

                break :blk switch (t) {
                    .pawn => params.values.corr_pawn_w * self.pool.pawn_corrhist[idx][stm.int()],
                    .minor => params.values.corr_minor_w * self.pool.minor_corrhist[idx][stm.int()],
                    .major => params.values.corr_major_w * self.pool.major_corrhist[idx][stm.int()],
                    else => unreachable,
                };
            },
        };
    }

    const corrected = eval + @as(evaluation.score.Int, @intCast(@divTrunc(correction, 1 << 18)));
    const min = evaluation.score.loss + 1;
    const max = evaluation.score.win - 1;
    return std.math.clamp(corrected, min, max);
}

fn updateCorrHists(
    self: *const Thread,
    depth: Depth,
    diff: evaluation.score.Int,
) void {
    const pos = self.board.positions.last();
    const stm = pos.stm;

    const weight = @min(depth + 1, 16);
    const bonus = diff * weight;

    inline for (hist.Corr.values) |t| {
        switch (t) {
            .nonpawn => {
                const len = hist.Corr.per_thread * self.pool.threads.items.len;
                const keys = pos.nonpawn_keys;

                const ntm = stm.flip();
                const stm_i = zobrist.index(keys.getPtrConst(stm).*, len);
                const ntm_i = zobrist.index(keys.getPtrConst(ntm).*, len);

                const stm_scaled = @divTrunc(bonus * params.values.corr_nonpawn_stm_w, 1024);
                const stm_clamped = std.math.clamp(stm_scaled, -16000, 16000);

                const ntm_scaled = @divTrunc(bonus * params.values.corr_nonpawn_ntm_w, 1024);
                const ntm_clamped = std.math.clamp(ntm_scaled, -16000, 16000);

                hist.gravity(&self.pool.nonpawn_corrhist[stm_i][stm.int()][stm.int()], stm_clamped);
                hist.gravity(&self.pool.nonpawn_corrhist[ntm_i][stm.int()][ntm.int()], ntm_clamped);
            },

            else => {
                const w = switch (t) {
                    .pawn => params.values.corr_pawn_update_w,
                    .minor => params.values.corr_minor_update_w,
                    .major => params.values.corr_major_update_w,
                    else => unreachable,
                };
                const scaled = @divTrunc(bonus * w, 1024);
                const clamped = std.math.clamp(scaled, -16000, 16000);

                const key = switch (t) {
                    .pawn => pos.pawn_key,
                    .minor => pos.minor_key,
                    .major => pos.major_key,
                    else => unreachable,
                };
                const len = hist.Corr.per_thread * self.pool.threads.items.len;
                const idx = zobrist.index(key, len);

                const p = switch (t) {
                    .pawn => &self.pool.pawn_corrhist[idx][stm.int()],
                    .minor => &self.pool.minor_corrhist[idx][stm.int()],
                    .major => &self.pool.major_corrhist[idx][stm.int()],
                    else => unreachable,
                };
                hist.gravity(p, clamped);
            },
        }
    }
}

fn updateHist(
    self: *Thread,
    depth: Depth,
    move: movegen.Move,
    bad_noisy_moves: []const movegen.Move,
    bad_quiet_moves: []const movegen.Move,
) void {
    const is_quiet = move.flag.isQuiet();
    if (is_quiet) {
        const bonus = hist.quietBonus(depth);
        const malus = hist.quietMalus(depth);

        hist.gravity(self.quietHistPtr(move), bonus);
        for (bad_quiet_moves) |qm| {
            hist.gravity(self.quietHistPtr(qm), -malus);
        }

        const cont_plies = [_]usize{ 1, 2, 4, 6 };
        for (cont_plies) |ply| {
            if (self.contHistPtr(move, ply)) |p| {
                hist.gravity(p, bonus);
                for (bad_quiet_moves) |qm| {
                    hist.gravity(self.contHistPtr(qm, ply).?, -malus);
                }
            } else break;
        }
    } else {
        const bonus = hist.noisyBonus(depth);
        hist.gravity(self.noisyHistPtr(move), bonus);
    }

    const malus = hist.noisyMalus(depth);
    for (bad_noisy_moves) |nm| {
        hist.gravity(self.noisyHistPtr(nm), -malus);
    }
}

fn printInfo(
    self: *const Thread,
    opt_pv: ?*const movegen.RootMove,
    depth: Depth,
    seldepth: Depth,
) !void {
    const io = &self.pool.io;
    const tt = &self.pool.tt;

    try io.lockWriter();
    defer io.unlockWriter();

    const writer = io.writer();
    const pv = opt_pv orelse {
        try writer.print("info depth 1 seldepth 1 nodes 1 time 1 nps 1000\n", .{});
        try writer.flush();
        return;
    };

    const nodes = self.pool.nodes();
    const ntime = self.pool.elapsedNanosecs();
    const mtime = ntime / std.time.ns_per_ms;

    try writer.print("info", .{});
    try writer.print(" depth {d}", .{depth});
    try writer.print(" seldepth {d}", .{seldepth});

    try writer.print(" hashfull {d}", .{tt.hashfull()});
    try writer.print(" nodes {d}", .{nodes});
    try writer.print(" time {d}", .{mtime});
    try writer.print(" nps {d}", .{nodes * std.time.ns_per_s / ntime});

    const mat = self.board.positions.last().material();
    const pvs: evaluation.score.Int = @intCast(pv.score);

    try writer.print(" score", .{});
    if (evaluation.score.isMated(pvs)) {
        const ply = pvs - evaluation.score.mated;
        const moves = @divTrunc(ply + 1, 2);
        try writer.print(" mate {d}", .{-moves});
    } else if (evaluation.score.isMate(pvs)) {
        const ply = evaluation.score.mate - pvs;
        const moves = @divTrunc(ply + 1, 2);
        try writer.print(" mate {d}", .{moves});
    } else {
        try writer.print(" cp {d}", .{evaluation.score.normalize(pvs, mat)});
    }

    if (self.pool.opts.show_wdl) {
        if (evaluation.score.isMated(pvs)) {
            try writer.print(" wdl 0 0 1000", .{});
        } else if (evaluation.score.isMate(pvs)) {
            try writer.print(" wdl 1000 0 0", .{});
        } else {
            const w, _, const l = evaluation.score.wdl(pvs, mat);
            const iw: evaluation.score.Int = @intFromFloat(1000 * w);
            const il: evaluation.score.Int = @intFromFloat(1000 * l);
            try writer.print(" wdl {d} {d} {d}", .{ iw, 1000 - iw - il, il });
        }
    }

    try writer.print(" pv", .{});
    for (pv.constSlice()) |m| {
        const s = m.toString(&self.board);
        const l = m.toStringLen();
        try writer.print(" {s}", .{s[0..l]});
    }

    try writer.print("\n", .{});
    try writer.flush();
}

fn printBest(self: *const Thread, opt_pv: ?*const movegen.RootMove) !void {
    const io = &self.pool.io;
    try io.lockWriter();
    defer io.unlockWriter();

    const pv = opt_pv orelse {
        try self.pool.io.writer().print("bestmove 0000\n", .{});
        try self.pool.io.writer().flush();
        return;
    };

    const m = pv.constSlice()[0];
    const s = m.toString(&self.board);
    const l = m.toStringLen();
    try self.pool.io.writer().print("bestmove {s}\n", .{s[0..l]});
    try self.pool.io.writer().flush();
}

fn datagenStop(self: *Thread, comptime which: enum { hard, soft }) bool {
    const limits = &self.pool.limits;
    const opt_lim = if (which == .hard) limits.hard_nodes else limits.soft_nodes;
    return if (opt_lim) |lim| self.nodes >= lim else false;
}

fn searchStop(self: *Thread, comptime which: enum { hard, soft }) bool {
    const limits = &self.pool.limits;
    if (limits.infinite) {
        return false;
    }

    const nodes = self.nodes;
    const nodes_lim = if (which == .hard) limits.hard_nodes else limits.soft_nodes;
    if (nodes_lim != null and nodes >= nodes_lim.?) {
        return true;
    }

    return nodes % 2048 == 0 and self.pool.elapsedNanosecs() >= blk: {
        const mlim = limits.movetime orelse return false;
        const nlim = mlim * std.time.ns_per_ms;

        const mult: u64 = @intCast(params.values.nodetm_mult);
        const bias: u64 = @intCast(params.values.nodetm_bias);
        const n = self.root_moves.constSlice()[0].nodes;
        const d = @max(self.nodes, 1);
        const nodetm = mult * (bias - n * 1024 / d);

        break :blk if (which == .hard) nlim else std.math.shr(u64, nlim * nodetm, 20);
    };
}

fn asp(self: *Thread) void {
    const pv = &self.root_moves.constSlice()[0];
    const pvs: evaluation.score.Int = @intCast(pv.score);

    var s: evaluation.score.Int = evaluation.score.none;
    var w: evaluation.score.Int = params.values.asp_window;

    const d = self.depth;
    var a: @TypeOf(pvs) = evaluation.score.mated;
    var b: @TypeOf(pvs) = evaluation.score.mate;
    if (d >= 7) {
        a = std.math.clamp(pvs - w, evaluation.score.mated, evaluation.score.mate);
        b = std.math.clamp(pvs + w, evaluation.score.mated, evaluation.score.mate);
    }

    while (true) : ({
        w = @divTrunc(w * params.values.asp_window_mult, 256);
        w = std.math.clamp(w, evaluation.score.mated, evaluation.score.mate);
    }) {
        s = self.ab(.exact, 0, a, b, d);
        if (self.job == .datagen and self.datagenStop(.hard) or self.pool.stopped) {
            break;
        }

        if (s <= a) {
            b = @divTrunc(a + b, 2);
            a = @max(a - w, evaluation.score.mated);
        } else if (s >= b) {
            a = @divTrunc(a + b, 2);
            b = @min(b + w, evaluation.score.mate);
        } else break;
    }
}

fn ab(
    self: *Thread,
    node: Node,
    ply: usize,
    alpha: evaluation.score.Int,
    beta: evaluation.score.Int,
    depth: Depth,
) evaluation.score.Int {
    if (depth <= 0) {
        return self.qs(ply, alpha, beta);
    }

    const board = &self.board;
    const pos = board.positions.last();

    self.nodes += 1;
    pos.pv.line.resize(0) catch unreachable;

    const is_datagen = self.job == .datagen;
    if (is_datagen and self.datagenStop(.hard) or self.pool.stopped) {
        return alpha;
    }

    const is_main = self == &self.pool.threads.items[0];
    if (!is_datagen and is_main and self.searchStop(.hard)) {
        self.pool.stopped = true;
        return alpha;
    }

    var a = alpha;
    var b = beta;
    var d = depth;

    const mate = evaluation.score.mateIn(ply);
    const mated = evaluation.score.matedIn(ply);

    const draw = mated + mate;
    const loss = mated;

    // mate dist pruning
    a = @max(a, mated);
    b = @min(b, mate + 1);
    if (a >= b) {
        return a;
    }

    const is_pv = node == .exact;
    const is_root = ply == 0;

    if (is_pv) {
        const len: Depth = @intCast(ply + 1);
        self.seldepth = @max(self.seldepth, len);
    }

    const is_drawn = self.board.isDrawn() and ply > 0;
    const is_terminal = self.board.isTerminal();
    if (is_drawn or is_terminal) {
        @branchHint(.unlikely);
        return if (is_drawn) draw else board.evaluate();
    }

    const key = pos.key;
    const is_checked = pos.isChecked();
    const is_singular = !pos.excluded.isNone();

    const tt = self.pool.tt;
    const tte: transposition.Entry, const tth =
        if (!is_singular)
            tt.read(key)
        else
            .{ .none, false };

    const was_pv = tth and tte.was_pv;
    const ttscore = evaluation.score.fromTT(tte.score, ply);

    if (!is_pv and !is_singular and tth and tte.shouldTrust(a, b, d)) {
        return ttscore;
    }

    if (!is_singular) {
        const has_tteval = tth and
            tte.eval > evaluation.score.loss and
            tte.eval < evaluation.score.win;
        const stat_eval = if (has_tteval) tte.eval else if (is_checked)
            evaluation.score.none
        else
            board.evaluate();

        const is_ttscore_correct = tth and
            ttscore > evaluation.score.loss and
            ttscore < evaluation.score.win and
            !(tte.flag == .upperbound and ttscore > stat_eval) and
            !(tte.flag == .lowerbound and ttscore <= stat_eval);
        const corr_eval = if (is_ttscore_correct) ttscore else if (is_checked)
            evaluation.score.none
        else
            self.correctEval(stat_eval);

        pos.stat_eval = stat_eval;
        pos.corr_eval = corr_eval;
    }

    const stat_eval = pos.stat_eval;
    const corr_eval = pos.corr_eval;

    // improving heuristic(s)
    // 10.0+0.1: 21.29 +- 9.45
    const improving = !is_checked and blk: {
        const fu2ev = pos.before(2).corr_eval;
        if (fu2ev != evaluation.score.none) {
            break :blk fu2ev < corr_eval;
        }

        const fu4ev = pos.before(4).corr_eval;
        if (fu4ev != evaluation.score.none) {
            break :blk fu4ev < corr_eval;
        }

        break :blk true;
    };
    const ntm_worsening = !is_checked and
        !is_root and
        pos.before(1).corr_eval != evaluation.score.none and
        pos.before(1).corr_eval > 1 - corr_eval;

    // internal iterative reduction (iir)
    // 10.0+0.1: 84.25 +- 20.51
    const has_ttm = tth and
        pos.isMovePseudoLegal(tte.move) and
        pos.isMoveLegal(tte.move);
    if (node.hasLower() and depth >= 3 and !has_ttm) {
        d -= 1;
    }

    // reverse futility pruning (rfp)
    if (!is_pv and
        !is_singular and
        !is_checked and
        d <= 7 and
        corr_eval >= b + 6)
    rfp: {
        const margin = blk: {
            const by_d =
                params.values.rfp_depth_quad * d * d +
                params.values.rfp_depth_mult * d +
                params.values.rfp_depth_bias;
            const ntm = params.values.rfp_ntm_worsening * @intFromBool(ntm_worsening);
            break :blk @divTrunc(by_d, 1024) - ntm;
        };

        if (corr_eval < b + margin) {
            break :rfp;
        }

        const lhs = corr_eval * params.values.rfp_fail_firm;
        const rhs = b * (1024 - params.values.rfp_fail_firm);
        return evaluation.score.clamp(@divTrunc(lhs + rhs, 1024));
    }

    // null move pruning
    if (!is_pv and
        !is_singular and
        !is_checked and
        d >= 2 and
        b > evaluation.score.loss and
        b <= corr_eval - params.values.nmp_eval_margin and
        !self.nmp_verif)
    nmp: {
        const occ = pos.bothOcc();
        const kings = pos.ptypeOcc(.king);
        const pawns = pos.ptypeOcc(.pawn);
        if (occ.bwx(kings).bwx(pawns) == .none) {
            break :nmp;
        }

        const base_r = params.values.nmp_base_r;
        const depth_r = params.values.nmp_depth_mult * d;
        const improving_r = params.values.nmp_improving_r * @intFromBool(improving);
        const deval_r = blk: {
            const diff = corr_eval - b;
            const mult = params.values.nmp_deval_mult;
            const max_r = params.values.nmp_deval_max_r;
            break :blk @min(@divTrunc(diff * mult, 1024), max_r);
        };
        const r = @divTrunc(base_r + depth_r + deval_r + improving_r, 256);

        var s = null_search: {
            board.doNull();
            defer board.undoNull();

            break :null_search -self.ab(node.flip(), ply + 1, -b, 1 - b, d - r);
        };

        if (s >= b) {
            if (evaluation.score.isMate(s)) {
                s = b;
            }

            const verified = d < 16 or verif_search: {
                self.nmp_verif = true;
                defer self.nmp_verif = false;

                const vs = self.ab(.upperbound, ply + 1, b - 1, b, d - r);
                break :verif_search vs >= b;
            };
            if (verified) {
                return s;
            }
        }
    }

    // razoring
    if (!is_pv and
        !is_singular and
        !is_checked and
        d <= 7 and
        corr_eval + params.values.razoring_mult * d <= a)
    {
        const rs = self.qs(ply + 1, a, b);
        if (rs <= a) {
            return rs;
        }
    }

    var best: movegen.Move.Scored = .init;
    var flag = transposition.Entry.Flag.upperbound;

    var searched: usize = 0;
    var bad_noisy_moves: movegen.Move.List = .init;
    var bad_quiet_moves: movegen.Move.List = .init;
    var mp: movegen.Picker = .init(
        self,
        if (is_singular) pos.excluded else if (has_ttm) tte.move else .none,
    );

    move_loop: while (mp.next()) |sm| {
        const m = sm.move;
        const is_ttm = m == mp.ttm;
        const is_legal = is_ttm or check: {
            const next_pos = pos.tryMove(m) catch break :check false;
            tt.prefetch(next_pos.key);
            break :check true;
        };
        if (!is_legal) {
            continue :move_loop;
        }

        const is_direct_check = pos.isDirectCheck(m);
        const is_noisy = m.flag.isNoisy();
        const is_quiet = m.flag.isQuiet();

        const base_lmr = params.lmr.get(d, searched, is_quiet);
        const lmr_d = @max(d * 1024 - base_lmr, 0);

        if (!is_root and best.score > evaluation.score.loss) {
            // history pruning
            // 10.0+0.1: 16.91 +- 8.41
            // 40.0+0.4: 3.77 +- 8.30
            const hp_lim, const hp_mult, const hp_bias = if (is_quiet) .{
                params.values.quiethist_pruning_lim,
                params.values.quiethist_pruning_mult,
                params.values.quiethist_pruning_bias,
            } else .{
                params.values.noisyhist_pruning_lim,
                params.values.noisyhist_pruning_mult,
                params.values.noisyhist_pruning_bias,
            };
            if (lmr_d <= hp_lim and sm.score < hp_mult * d + hp_bias) {
                mp.skipQuiets();
                continue :move_loop;
            }

            // futility pruning
            // 10.0+0.1: 34.28 +- 12.73
            const fp_d = @divTrunc(lmr_d, 1024);
            const fp_margin =
                params.values.fp_margin_mult * fp_d +
                params.values.fp_margin_bias +
                @divTrunc(sm.score * params.values.fp_hist_mult, 16384);
            if (fp_d <= 8 and
                !is_noisy and
                !is_checked and
                a < evaluation.score.win and
                corr_eval + fp_margin <= a)
            {
                continue :move_loop;
            }

            // bad noisy(/ies?) futility pruning
            const bnfp_d = fp_d;
            const bnfp_margin =
                params.values.bnfp_margin_mult * bnfp_d +
                params.values.bnfp_margin_bias +
                @divTrunc(sm.score * params.values.bnfp_hist_mult, 16384);
            if (bnfp_d <= 8 and
                mp.stage.isBad() and
                !is_quiet and
                !is_checked and
                a < evaluation.score.win and
                corr_eval + bnfp_margin <= a)
            {
                continue :move_loop;
            }

            // late move pruning (lmp)
            // 10.0+0.1: 21.30 +- 9.80
            const lmp_lim = blk: {
                const base = if (improving)
                    params.values.lmp_improving_quad * d * d +
                        params.values.lmp_improving_mult * d +
                        params.values.lmp_improving_bias
                else
                    params.values.lmp_nonimproving_quad * d * d +
                        params.values.lmp_nonimproving_mult * d +
                        params.values.lmp_nonimproving_bias;
                const div: usize = @intCast(@divTrunc(base, 1024));
                break :blk @max(div + @intFromBool(is_direct_check), 1);
            };
            if (searched > lmp_lim) {
                break :move_loop;
            }

            // pvs see
            const see_margin = if (is_quiet)
                params.values.pvs_see_quiet_mult * d
            else noisy: {
                const base = params.values.pvs_see_noisy_mult * d;
                const mult = params.values.pvs_see_capthist_mult;
                const max = params.values.pvs_see_max_capthist * d;
                break :noisy base - std.math.clamp(@divTrunc(sm.score * mult, 1024), -max, max);
            };
            if (!pos.see(m, see_margin)) {
                continue :move_loop;
            }
        }

        var e: Depth = 0;
        var r: Depth = 0;

        if (!is_root and
            is_ttm and
            d >= 6 and
            d <= tte.depth + 3 and
            tte.flag != .upperbound)
        {
            pos.excluded = m;
            defer pos.excluded = .none;

            const bmul =
                params.values.se_beta_mult -
                params.values.se_beta_mult_pv * @intFromBool(is_pv) +
                params.values.se_beta_mult_was_pv * @intFromBool(was_pv);
            const raw_sb = @divTrunc(ttscore * 1024 - d * bmul, 1024);
            const raw_sd =
                params.values.se_depth_mult * d +
                params.values.se_depth_bias;

            const sb = @max(raw_sb, evaluation.score.loss + 1);
            const sd = @divTrunc(raw_sd, 1024);
            const se_score = self.ab(node, ply, sb - 1, sb, sd);

            if (se_score < sb) {
                const margins: [2]evaluation.score.Int = if (is_noisy) .{
                    params.values.dext_noisy + params.values.dext_pv * @intFromBool(is_pv),
                    params.values.text_noisy + params.values.text_pv * @intFromBool(is_pv),
                } else .{
                    params.values.dext_quiet + params.values.dext_pv * @intFromBool(is_pv),
                    params.values.text_quiet + params.values.text_pv * @intFromBool(is_pv),
                };

                e += 1;
                e += @intFromBool(se_score < sb - margins[0]);
                e += @intFromBool(se_score < sb - margins[1]);
            } else if (sb >= b) {
                const min = evaluation.score.loss + 1;
                const max = evaluation.score.win - 1;
                return std.math.clamp(sb, min, max);
            } else if (a + 1 > b - 1 or ttscore != std.math.clamp(ttscore, a + 1, b - 1)) {
                e -= 4;
            }
        } else if (!is_checked and
            node == .lowerbound and
            d <= 7 and
            corr_eval <= a - params.values.ldse_margin)
        {
            e += 1;
        }

        const s = recur: {
            board.doMove(m);
            defer board.undoMove();
            defer searched += 1;

            const nodes = self.nodes;
            defer if (is_root) {
                const rm = self.root_moves.find(m) orelse
                    std.debug.panic("root move not found", .{});
                rm.nodes += self.nodes - nodes;
            };

            var recur_d = d + e - 1;
            var score: @TypeOf(a, b) = evaluation.score.none;

            if (is_pv and searched == 0) {
                score = -self.ab(.exact, ply + 1, -b, -a, recur_d);
                break :recur score;
            }

            const is_late = blk: {
                var rhs: usize = @intFromBool(is_pv);
                rhs += @intFromBool(is_root);
                rhs += @intFromBool(is_noisy);
                rhs += @intFromBool(mp.ttm.isNone());
                break :blk searched > 1 and searched > rhs;
            };

            score = if (is_late and d >= 3) reduced: {
                // late move reduction (lmr)
                // 10.0+0.1: 48.29 +- 15.89
                r += base_lmr;

                r += params.values.lmr_non_improving * @intFromBool(!improving);
                r += params.values.lmr_cutnode * @intFromBool(node == .lowerbound);
                r += params.values.lmr_noisy_ttm * @intFromBool(has_ttm and mp.ttm.flag.isNoisy());
                r += params.values.lmr_found_pv * @intFromBool(flag == .exact);

                r -= params.values.lmr_gave_check *
                    @intFromBool(board.positions.last().isChecked());
                r -= params.values.lmr_is_checked * @intFromBool(is_checked);
                r -= params.values.lmr_is_pv * @intFromBool(is_pv);

                r -= params.values.lmr_was_pv * @intFromBool(was_pv);
                r -= params.values.lmr_was_pv_non_fail_low *
                    @intFromBool(was_pv and ttscore > a);

                r = @divTrunc(r, 1024);
                const rd = std.math.clamp(recur_d - r, 1, recur_d);
                var rs = -self.ab(.lowerbound, ply + 1, -a - 1, -a, rd);

                if (rs > a and rd < recur_d) {
                    const deeper_margins: [2]evaluation.score.Int = .{
                        params.values.deeper_margin0_mult * recur_d +
                            params.values.deeper_margin0_bias,
                        params.values.deeper_margin1_mult * recur_d +
                            params.values.deeper_margin1_bias,
                    };
                    recur_d += @intFromBool(rs > best.score + @divTrunc(deeper_margins[0], 1024));
                    recur_d += @intFromBool(rs > best.score + @divTrunc(deeper_margins[1], 1024));

                    const shallower_margin =
                        params.values.shallower_margin_mult * recur_d +
                        params.values.shallower_margin_bias;
                    recur_d -= @intFromBool(rs < best.score + @divTrunc(shallower_margin, 1024));

                    rs = -self.ab(node.flip(), ply + 1, -a - 1, -a, recur_d);
                }

                break :reduced rs;
            } else -self.ab(node.flip(), ply + 1, -a - 1, -a, recur_d);

            score = if (is_pv and score > a) -self.ab(.exact, ply + 1, -b, -a, recur_d) else score;

            break :recur score;
        };

        if (is_datagen and self.datagenStop(.hard) or self.pool.stopped) {
            return a;
        }

        const next_pv = &pos.after(1).pv;
        if (is_root) {
            const rm = self.root_moves.find(m) orelse std.debug.panic("root move not found", .{});
            if (searched == 1 or s > a) {
                rm.update(s, m, next_pv.constSlice());
            } else {
                rm.score = evaluation.score.none;
            }
        }

        if (s > best.score) {
            best.score = @intCast(s);

            if (!is_root and is_pv and s > a) {
                pos.pv.update(s, m, next_pv.constSlice());
            }

            if (s > a) {
                a = s;
                best.move = m;
                flag = .exact;
            }

            if (s >= b) {
                flag = .lowerbound;
                break :move_loop;
            }
        }

        const bad_moves = if (is_quiet) &bad_quiet_moves else &bad_noisy_moves;
        bad_moves.array.pushUnchecked(m);
    }

    if (!is_singular and searched == 0) {
        return if (is_checked) loss else draw;
    }

    if (!is_root and
        best.score >= b and
        best.score < evaluation.score.win and
        best.score > evaluation.score.loss and
        a < evaluation.score.win and
        a > evaluation.score.loss)
    {
        best.score = @intCast(@divTrunc(best.score * d + b, d + 1));
    }

    if (flag == .lowerbound) {
        self.updateHist(d, best.move, bad_noisy_moves.constSlice(), bad_quiet_moves.constSlice());
    }

    if (!is_singular) {
        tt.write(key, .{
            .was_pv = was_pv or flag == .exact,
            .flag = flag,
            .age = @truncate(tt.age),
            .depth = @intCast(depth),
            .eval = @intCast(stat_eval),
            .score = @intCast(evaluation.score.toTT(best.score, ply)),
            .move = best.move,
        });
    }

    if (!is_checked and
        !is_singular and
        !best.move.flag.isNoisy() and
        !(flag == .upperbound and best.score > corr_eval) and
        !(flag == .lowerbound and best.score < corr_eval))
    {
        self.updateCorrHists(depth, best.score - corr_eval);
    }

    return best.score;
}

fn qs(
    self: *Thread,
    ply: usize,
    alpha: evaluation.score.Int,
    beta: evaluation.score.Int,
) evaluation.score.Int {
    const board = &self.board;
    const pos = board.positions.last();

    self.nodes += 1;
    pos.pv.line.resize(0) catch unreachable;

    const is_datagen = self.job == .datagen;
    if (is_datagen and self.datagenStop(.hard) or self.pool.stopped) {
        return alpha;
    }

    const is_main = self == &self.pool.threads.items[0];
    if (!is_datagen and is_main and self.searchStop(.hard)) {
        self.pool.stopped = true;
        return alpha;
    }

    const draw = evaluation.score.draw;
    const loss = evaluation.score.loss + 1;

    const b = beta;
    var a = alpha;

    const is_drawn = self.board.isDrawn() and ply > 0;
    const is_terminal = self.board.isTerminal();
    if (is_drawn or is_terminal) {
        @branchHint(.unlikely);
        return if (is_drawn) draw else board.evaluate();
    }

    const key = pos.key;
    const is_checked = pos.isChecked();

    const tt = self.pool.tt;
    const tte, const tth = tt.read(key);
    const ttscore = evaluation.score.fromTT(tte.score, ply);

    if (tth and tte.shouldTrust(a, b, 0)) {
        return ttscore;
    }

    const has_tteval = tth and
        tte.eval > evaluation.score.loss and
        tte.eval < evaluation.score.win;
    const stat_eval = if (has_tteval) tte.eval else if (is_checked)
        evaluation.score.none
    else
        board.evaluate();

    const is_ttscore_correct = tth and
        ttscore > evaluation.score.loss and
        ttscore < evaluation.score.win and
        !(tte.flag == .upperbound and ttscore > stat_eval) and
        !(tte.flag == .lowerbound and ttscore <= stat_eval);
    const corr_eval = if (is_ttscore_correct) ttscore else if (is_checked)
        evaluation.score.none
    else
        self.correctEval(stat_eval);

    pos.stat_eval = stat_eval;
    pos.corr_eval = corr_eval;

    a = @max(a, stat_eval);
    if (a >= b) {
        return a;
    }

    var best: movegen.Move.Scored = .{ .move = .none, .score = @intCast(stat_eval) };
    var flag = transposition.Entry.Flag.upperbound;

    const has_ttm = tth and
        pos.isMovePseudoLegal(tte.move) and
        pos.isMoveLegal(tte.move);
    var mp = movegen.Picker.init(self, if (has_ttm) tte.move else .none);
    var searched: usize = 0;
    if (!is_checked) {
        mp.skipQuiets();
    }

    move_loop: while (mp.next()) |sm| {
        const m = sm.move;
        const is_ttm = m == mp.ttm;

        const is_legal = is_ttm or check: {
            const next_pos = pos.tryMove(m) catch break :check false;
            tt.prefetch(next_pos.key);
            break :check true;
        };
        if (!is_legal) {
            continue :move_loop;
        }

        if (searched > 0) {
            if (mp.stage.isBad()) {
                break :move_loop;
            }

            // qs see pruning
            // 10.0+0.1: 206.81 +- 35.91
            if (!pos.see(m, draw)) {
                continue :move_loop;
            }
        }

        if (!is_checked) {
            // qs futility pruning
            // 10.0+0.1: 65.37 +- 17.63
            const margin = params.values.qs_fp_margin;
            if (corr_eval + margin <= a and !pos.see(m, draw + 1)) {
                best.score = @intCast(@max(best.score, corr_eval + margin));
                continue :move_loop;
            }
        }

        const s = recur: {
            board.doMove(m);
            defer board.undoMove();
            defer mp.skipQuiets();
            defer searched += 1;

            break :recur -self.qs(ply + 1, -b, -a);
        };

        if (is_datagen and self.datagenStop(.hard) or self.pool.stopped) {
            return a;
        }

        if (s > best.score) {
            best.score = @intCast(s);

            if (s > a) {
                a = s;
                best.move = m;
            }

            if (s >= b) {
                flag = .lowerbound;
                break :move_loop;
            }
        }
    }

    if (searched == 0 and is_checked) {
        return loss;
    }

    tt.write(key, .{
        .was_pv = tte.was_pv,
        .flag = flag,
        .age = @truncate(tt.age),
        .depth = 0,
        .eval = @intCast(stat_eval),
        .score = @intCast(evaluation.score.toTT(best.score, ply)),
        .move = best.move,
    });

    return best.score;
}

fn clearHash(self: *Thread) void {
    const tt = self.pool.tt.clusters;
    const i = self - &self.pool.threads.items[0];
    const n = self.pool.threads.items.len;
    const d = tt.len / n;
    const m = tt.len % n;
    var p = tt.ptr;

    if (d == 0 and m == 0) {
        return;
    }

    for (0..i) |it| {
        p += if (it < m) d + 1 else d;
    }

    const s = p[0..if (i < m) d + 1 else d];
    for (s) |*c| {
        c.* = .none;
    }

    self.pool.pawn_corrhist[i * hist.Corr.per_thread ..][0..hist.Corr.per_thread].* =
        @splat(@splat(0));
    self.pool.minor_corrhist[i * hist.Corr.per_thread ..][0..hist.Corr.per_thread].* =
        @splat(@splat(0));
    self.pool.major_corrhist[i * hist.Corr.per_thread ..][0..hist.Corr.per_thread].* =
        @splat(@splat(0));
    self.pool.nonpawn_corrhist[i * hist.Corr.per_thread ..][0..hist.Corr.per_thread].* =
        @splat(@splat(@splat(0)));
}

fn datagen(self: *Thread) !void {
    try selfplay.threaded.run(self);
}

fn reset(self: *Thread) !void {
    const pool = self.job.reset;
    self.* = .init;
    self.pool = pool;
    try self.board.parseFen(Board.Position.startpos);
    self.board.frc = self.pool.opts.frc;
}

pub fn search(self: *Thread) !void {
    self.nodes = 0;
    self.tbhits = 0;
    self.tthits = 0;
    self.root_moves = movegen.RootMove.List.init(&self.board);

    const job = self.job;
    const is_main = self == &self.pool.threads.items[0];
    const is_datagen, const is_go = switch (job) {
        .datagen => .{ true, false },
        .go => .{ false, true },
        else => .{ false, false },
    };
    defer if (is_datagen or is_main) {
        self.pool.tt.doAge();
    };

    const should_print = is_go and is_main;
    defer if (should_print) {
        self.pool.stopped = true;
        if (self.pool.threads.items.len > 1) {
            for (self.pool.threads.items[1..]) |*helper| {
                helper.wait();
            }
        }
    };

    const root_moves = self.root_moves.slice();
    if (root_moves.len == 0) {
        if (should_print) {
            try self.printInfo(null, 0, 0);
            try self.printBest(null);
        }
        return;
    }

    const pool = self.pool;
    const max_depth = pool.limits.depth orelse movegen.RootMove.capacity;
    const min_depth = 1;

    var depth: Depth = min_depth;
    var last_depth: Depth = 0;
    var last_seldepth: Depth = 0;
    var last_pv: movegen.RootMove = root_moves[0];

    while (depth <= max_depth) : (depth += 1) {
        self.depth = depth;
        self.seldepth = 0;
        self.asp();

        if (self.pool.stopped) {
            break;
        }

        movegen.RootMove.sortSlice(root_moves);
        last_depth = self.depth;
        last_seldepth = self.seldepth;
        last_pv = root_moves[0];
        if (should_print and !pool.opts.minimal) {
            try self.printInfo(&last_pv, last_depth, last_seldepth);
        }

        if (is_datagen and self.datagenStop(.soft) or is_go and self.searchStop(.soft)) {
            break;
        }
    }

    if (should_print) {
        try self.printInfo(&last_pv, last_depth, last_seldepth);
        try self.printBest(&last_pv);
    }
}

pub fn getQuietHist(self: *const Thread, move: movegen.Move) hist.Int {
    return self.quietHistPtr(move).*;
}

pub fn getNoisyHist(self: *const Thread, move: movegen.Move) hist.Int {
    return self.noisyHistPtr(move).*;
}

pub fn getContHist(self: *const Thread, move: movegen.Move, ply: usize) hist.Int {
    return if (self.contHistPtr(move, ply)) |p| p.* else evaluation.score.draw;
}
