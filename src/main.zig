const builtin = @import("builtin");
const engine = @import("engine");
const selfplay = @import("selfplay");
const std = @import("std");

const bench = @import("bench.zig");
const root = @import("root.zig");

const help =
    \\zin [command] [options]
    \\
    \\commands:
    \\    bench [depth]:
    \\        run benchmark for openbench.
    \\
    \\    datagen [options]:
    \\        generate training data.
    \\        options:
    \\            --book [path]           epd opening book to read from. must be specified.
    \\            --data [path]           data file to write to. must be specified.
    \\            --games [num]           number of games to be played.
    \\            --random-moves [num]    number of random moves to play at the start of each game.
    \\                                    defaults to 8.
    \\            --depth [num]           max depth to search.
    \\            --soft-nodes [num]      number of soft nodes to search. defaults to 5000.
    \\            --hard-nodes [num]      number of hard nodes to search. defaults to 100000.
    \\            --hash [num]            size of transposition table in mib. defaults to 128.
    \\            --threads [num]         number of threads to use. defaults to 1.
    \\    eval-stats [path]:
    \\        print evaluation stats on positions listed in $path. must be an epd file.
    \\
    \\    help:
    \\        print this message and exit.
    \\
;

pub const author = root.author;
pub const name = root.name;
pub const version = root.version;

pub const std_options: std.Options = .{
    .side_channels_mitigations = .basic,
};

pub fn main() !void {
    try root.init();
    defer root.deinit();

    const is_debug = builtin.mode == .Debug;
    var gpa = if (is_debug) std.heap.DebugAllocator(.{}).init else {};
    const allocator = if (is_debug) gpa.allocator() else std.heap.smp_allocator;
    defer if (is_debug) {
        _ = gpa.deinit();
    };

    const pool = try engine.Thread.Pool.create(
        // zig fmt: off
        allocator, null,
        // zig fmt: on
        try .init(allocator, null, 16384, null, 16384),
        try .init(allocator, null),
    );
    defer pool.destroy();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip();
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "bench")) {
            var depth: ?engine.Thread.Depth = null;
            if (args.next()) |aux| {
                depth = try std.fmt.parseUnsigned(u8, aux, 10);
            }

            return bench.run(pool, depth);
        } else if (std.mem.eql(u8, arg, "datagen")) {
            return selfplay.run(pool, &args);
        } else if (std.mem.eql(u8, arg, "eval-stats")) {
            const epd = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
            return engine.evaluation.printStats(pool, epd);
        } else if (std.mem.eql(u8, arg, "help")) {
            try std.fs.File.stdout().writeAll(help);
            std.process.exit(0);
        } else std.process.fatal("unknown arg '{s}'", .{arg});
    } else try engine.uci.loop(pool);
}
