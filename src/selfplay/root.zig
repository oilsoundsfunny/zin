const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

pub const Request = @import("Request.zig");
pub const threaded = @import("threaded.zig");
pub const ViriFormat = @import("ViriFormat.zig");

const Depth = engine.Thread.Depth;
const Score = engine.evaluation.score.Int;

const Options = struct {
    book: ?[]const u8 = null,
    data: ?[]const u8 = null,
    games: ?usize = null,
    random_moves: ?usize = null,

    hash: ?usize = null,
    threads: ?usize = null,

    depth: ?Depth = null,
    soft_nodes: ?usize = null,
    hard_nodes: ?usize = null,

    win_adj_min_ply: ?usize = null,
    win_adj_ply_num: ?usize = null,
    win_adj_score: ?Score = null,

    draw_adj_min_ply: ?usize = null,
    draw_adj_ply_num: ?usize = null,
    draw_adj_score: ?Score = null,
};

pub fn run(pool: *engine.Thread.Pool, args: *std.process.ArgIterator) !void {
    const duped_err = "duplicated arg '{s}'";
    const expected_err = "expected arg after '{s}'";
    var options: Options = .{};

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--book")) {
            if (options.book) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            options.book = args.next() orelse std.process.fatal(expected_err, .{arg});
        } else if (std.mem.eql(u8, arg, "--data")) {
            if (options.data) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            options.data = args.next() orelse std.process.fatal(expected_err, .{arg});
        } else if (std.mem.eql(u8, arg, "--random-moves")) {
            if (options.random_moves) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.random_moves = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--games")) {
            if (options.games) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.games = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--depth")) {
            if (options.depth) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.depth = try std.fmt.parseUnsigned(Depth, token, 10);
        } else if (std.mem.eql(u8, arg, "--soft-nodes")) {
            if (options.soft_nodes) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.soft_nodes = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--hard-nodes")) {
            if (options.hard_nodes) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.hard_nodes = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--hash")) {
            if (options.hash) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.hash = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--threads")) {
            if (options.threads) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.threads = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--win-adj-min-ply")) {
            if (options.win_adj_min_ply) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.win_adj_min_ply = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--win-adj-ply-num")) {
            if (options.win_adj_ply_num) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.win_adj_ply_num = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--win-adj-score")) {
            if (options.win_adj_score) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.win_adj_score = try std.fmt.parseUnsigned(Score, token, 10);
        } else if (std.mem.eql(u8, arg, "--draw-adj-min-ply")) {
            if (options.draw_adj_min_ply) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.draw_adj_min_ply = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--draw-adj-ply-num")) {
            if (options.draw_adj_ply_num) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.draw_adj_ply_num = try std.fmt.parseUnsigned(usize, token, 10);
        } else if (std.mem.eql(u8, arg, "--draw-adj-score")) {
            if (options.draw_adj_score) |_| {
                std.process.fatal(duped_err, .{arg});
            }

            const token = args.next() orelse std.process.fatal(expected_err, .{arg});
            options.draw_adj_score = try std.fmt.parseUnsigned(Score, token, 10);
        } else std.process.fatal("unknown arg '{s}'", .{arg});
    }

    const hash = options.hash orelse 128;
    const threads = options.threads orelse 1;

    try pool.realloc(threads);
    pool.tt.deinit(pool.allocator);
    pool.tt = try .init(pool.allocator, hash);
    pool.clearHash();

    const book = options.book orelse std.process.fatal("missing arg '--book'", .{});
    const data = options.data orelse std.process.fatal("missing arg '--data'", .{});

    pool.io.deinit(pool.allocator);
    pool.io = try .init(pool.allocator, book, 65536, data, 65536 * threads * 4);

    pool.limits.depth = options.depth;
    pool.limits.soft_nodes = options.soft_nodes orelse 5000;
    pool.limits.hard_nodes = options.hard_nodes orelse pool.limits.soft_nodes.? * 50;
    pool.limits.set(pool.opts.overhead, .white);

    pool.datagen(.{
        .games = options.games,
        .random_moves = options.random_moves orelse 8,
        .win_adj = try .init(
            options.win_adj_min_ply orelse 3,
            options.win_adj_ply_num orelse 3,
            options.win_adj_score orelse 400,
        ),
        .draw_adj = try .init(
            options.draw_adj_min_ply orelse 40,
            options.draw_adj_ply_num orelse 8,
            options.draw_adj_score orelse 25,
        ),
    });
    pool.waitSleep();
    try pool.io.writer().flush();
}
