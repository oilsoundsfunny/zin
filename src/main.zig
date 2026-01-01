const bitboard = @import("bitboard");
const builtin = @import("builtin");
const engine = @import("engine");
const params = @import("params");
const selfplay = @import("selfplay");
const std = @import("std");
const types = @import("types");

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
    \\            --book [path]         opening book to read from. must be specified.
    \\            --data [path]         data file to write to. must be specified.
    \\            --games [num]         number of games to be played.
    \\            --depth [num]         max depth to search.
    \\            --soft-nodes [num]    number of soft nodes to search. defaults to 5000.
    \\            --hard-nodes [num]    number of hard nodes to search. defaults to 100000.
    \\            --hash [num]          size of transposition table in mib. defaults to 128.
    \\            --threads [num]       number of threads to use. defaults to 1.
    \\    eval-stats [epd]:
    \\        print evaluation stats on positions listed in $epd.
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
    defer if (is_debug) {
        _ = gpa.deinit();
    };

    const allocator = if (is_debug) gpa.allocator() else std.heap.smp_allocator;

    const pool = try engine.Thread.Pool.create(
        allocator,
        null,
        try types.IO.init(allocator, null, 16384, null, 16384),
        try engine.transposition.Table.init(allocator, null),
    );
    defer pool.destroy();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip();
    while (args.next()) |arg| {
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
