const bitboard = @import("bitboard");
const builtin = @import("builtin");
const engine = @import("engine");
const nnue = @import("nnue");
const params = @import("params");
const selfplay = @import("selfplay");
const std = @import("std");
const types = @import("types");

const bench = @import("bench.zig");
const genfens = @import("genfens.zig");

const help_fmt =
    \\zin {s}
    \\
    \\USAGE:
    \\    zin <SUBCOMMAND>
    \\
    \\SUBCOMMANDS:
    \\    bench
    \\    collect-eval
    \\    datagen
    \\    genfens         Note: not meant for CLI use
    \\    help            Prints this message or help message of given subcommand
    \\
;

pub const version = @import("version").resolved;
pub const version_string = @import("version").string;

pub const author = "oilsoundsfunny";
pub const name = "zin";

pub fn main(init: std.process.Init.Minimal) !void {
    try bitboard.init();
    try params.init();
    try engine.init();

    defer bitboard.deinit();
    defer params.deinit();
    defer engine.deinit();

    const gpa = std.heap.smp_allocator;
    var threaded_io: std.Io.Threaded = .init(gpa, .{});
    const io = threaded_io.io();

    const pool: *engine.Thread.Pool = try .create(gpa, io);
    defer pool.destroy();

    var args = try init.args.iterateAllocator(gpa);
    defer args.deinit();

    _ = args.skip();
    if (args.next()) |first| {
        if (std.mem.startsWith(u8, first, "genfens")) {
            const second = args.next() orelse
                std.process.fatal("expected 'quit' after '{s}'", .{first});

            return if (!std.mem.eql(u8, second, "quit"))
                std.process.fatal("expected 'quit', found '{s}'", .{second})
            else if (args.next()) |third|
                std.process.fatal("extranous arg '{s}'", .{third})
            else
                genfens.run(pool, first);
        } else if (std.mem.eql(u8, first, "bench")) {
            const depth: engine.Thread.Depth =
                if (args.next()) |second| try std.fmt.parseUnsigned(u8, second, 10) else 12;

            return if (args.next()) |third|
                std.process.fatal("extranous arg '{s}'", .{third})
            else
                bench.run(pool, depth);
        } else if (std.mem.eql(u8, first, "collect-eval")) {
            const second = args.next() orelse
                std.process.fatal("expected arg after '{s}'", .{first});

            return if (args.next()) |third|
                std.process.fatal("extranous arg '{s}'", .{third})
            else
                engine.evaluation.Stats.collect(pool, second);
        } else if (std.mem.eql(u8, first, "datagen")) {
            return selfplay.run(pool, &args);
        } else if (std.mem.eql(u8, first, "help")) {
            const second = args.next() orelse {
                try pool.io.writer().print(help_fmt, .{version_string});
                try pool.io.writer().flush();
                return;
            };

            if (args.next()) |third| {
                std.process.fatal("extranous arg '{s}'", .{third});
            } else if (std.mem.eql(u8, second, "bench")) {
                try bench.help(pool, version_string);
            } else if (std.mem.eql(u8, second, "collect-eval")) {
                try engine.evaluation.Stats.help(pool, version_string);
            } else if (std.mem.eql(u8, second, "datagen")) {
                try selfplay.help(pool, version_string);
            } else std.process.fatal("unknown subcommand '{s}'", .{second});
        } else std.process.fatal("unknown arg '{s}'", .{first});
    } else try engine.uci.loop(pool);
}
