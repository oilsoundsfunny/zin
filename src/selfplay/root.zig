const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

pub const Book = @import("Book.zig");
pub const Request = @import("Request.zig");
pub const threaded = @import("threaded.zig");
pub const ViriFormat = @import("ViriFormat.zig");

const Depth = engine.Thread.Depth;
const Score = engine.evaluation.score.Int;

const Options = struct {
    book: ?[]const u8,
    data: ?[]const u8,

    games: ?usize,
    seed: ?u64,
    random_moves: ?usize,

    hash: ?usize,
    threads: ?usize,

    depth: ?Depth,
    soft_nodes: ?usize,
    hard_nodes: ?usize,

    win_adj_min_ply: ?usize,
    win_adj_ply_num: ?usize,
    win_adj_score: ?Score,

    draw_adj_min_ply: ?usize,
    draw_adj_ply_num: ?usize,
    draw_adj_score: ?Score,

    fn parse(args: *std.process.Args.Iterator) !Options {
        const duped_err = "duplicated arg '{s}'";
        const expected_err = "expected arg after '{s}'";
        var options: Options = .{
            .book = null,
            .data = null,

            .games = null,
            .seed = null,
            .random_moves = null,

            .hash = null,
            .threads = null,

            .depth = null,
            .soft_nodes = null,
            .hard_nodes = null,

            .win_adj_min_ply = null,
            .win_adj_ply_num = null,
            .win_adj_score = null,

            .draw_adj_min_ply = null,
            .draw_adj_ply_num = null,
            .draw_adj_score = null,
        };

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--book")) {
                options.book = if (options.book) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    args.next() orelse std.process.fatal(expected_err, .{arg});
            } else if (std.mem.eql(u8, arg, "--data")) {
                options.data = if (options.data) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    args.next() orelse std.process.fatal(expected_err, .{arg});
            } else if (std.mem.eql(u8, arg, "--seed")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.seed = if (options.seed) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(u64, token, 10);
            } else if (std.mem.eql(u8, arg, "--random-moves")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.random_moves = if (options.random_moves) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--games")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.games = if (options.games) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--depth")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.depth = if (options.depth) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(Depth, token, 10);
            } else if (std.mem.eql(u8, arg, "--soft-nodes")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.soft_nodes = if (options.soft_nodes) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--hard-nodes")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.hard_nodes = if (options.hard_nodes) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--hash")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.hash = if (options.hash) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--threads")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.threads = if (options.threads) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--win-adj-min-ply")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.win_adj_min_ply = if (options.win_adj_min_ply) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--win-adj-ply-num")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.win_adj_ply_num = if (options.win_adj_ply_num) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--win-adj-score")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.win_adj_score = if (options.win_adj_score) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(Score, token, 10);
            } else if (std.mem.eql(u8, arg, "--draw-adj-min-ply")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.draw_adj_min_ply = if (options.draw_adj_min_ply) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--draw-adj-ply-num")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.draw_adj_ply_num = if (options.draw_adj_ply_num) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(usize, token, 10);
            } else if (std.mem.eql(u8, arg, "--draw-adj-score")) {
                const token = args.next() orelse std.process.fatal(expected_err, .{arg});
                options.draw_adj_score = if (options.draw_adj_score) |_|
                    std.process.fatal(duped_err, .{arg})
                else
                    try std.fmt.parseUnsigned(Score, token, 10);
            } else std.process.fatal("unknown arg '{s}'", .{arg});
        }

        return options;
    }
};

pub fn help(pool: *engine.Thread.Pool, version_string: []const u8) !void {
    const fmt =
        \\zin-datagen {s}
        \\
        \\USAGE:
        \\    zin datagen <OPTIONS>
        \\
        \\OPTIONS:
        \\    --book <path>
        \\    --data <path>
        \\    --games <num>
        \\    --seed <num>
        \\    --random-moves <num>
        \\    --hash <num>
        \\    --threads <num>
        \\    --depth <num>
        \\    --soft-nodes <num>
        \\    --hard-nodes <num>
        \\    --win-adj-min-ply <num>
        \\    --win-adj-ply-num <num>
        \\    --win-adj-score <num>
        \\    --draw-adj-min-ply <num>
        \\    --draw-adj-ply-num <num>
        \\    --draw-adj-score <num>
        \\
    ;
    try pool.io.writer().print(fmt, .{version_string});
    try pool.io.writer().flush();
}

pub fn run(pool: *engine.Thread.Pool, args: *std.process.Args.Iterator) !void {
    const options: Options = try .parse(args);

    const data = options.data orelse std.process.fatal("missing arg '--data'", .{});
    const games = options.games orelse std.process.fatal("missing arg '--games'", .{});

    var book = try Book.init(pool.gpa, pool.stdio, options.book);
    defer book.deinit(pool.gpa);

    pool.io.deinit(pool.gpa, pool.stdio);
    pool.io = try .init(pool.gpa, pool.stdio, null, std.atomic.cache_line, data, 65536);

    const threads = options.threads orelse 1;
    try pool.realloc(threads);

    const hash = options.hash orelse 128;
    pool.tt.deinit(pool.gpa);
    pool.tt = try .init(pool.gpa, hash);
    pool.clearHash();

    pool.limits.depth = options.depth;
    pool.limits.soft_nodes, pool.limits.hard_nodes = if (options.depth) |_| .{ null, null } else .{
        options.soft_nodes orelse 5000,
        options.hard_nodes orelse pool.limits.soft_nodes.? * 50,
    };
    pool.limits.set(pool.opts.overhead, .white);
    pool.opts.frc = true;

    try pool.datagen(.{
        .rng = .init(options.seed orelse 0x5555555555555555),
        .book = book,
        .games = games,
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
    try pool.io.writer().flush();
}
