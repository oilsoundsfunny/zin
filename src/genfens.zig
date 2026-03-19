const engine = @import("engine");
const std = @import("std");

const Options = struct {
    num: usize,
    seed: u64,
    book: ?[]const u8,
};

fn parseArgs(args: []const u8, allocator: std.mem.Allocator) !Options {
    var opts: Options = undefined;
    var tokens = std.mem.tokenizeAny(u8, args, &.{ '\n', '\r', '\t', ' ' });

    const first = tokens.next() orelse std.process.fatal("missing arg '{s}'", .{"genfens"});
    opts.num = if (std.mem.eql(u8, first, "genfens"))
        try std.fmt.parseUnsigned(usize, tokens.next().?, 10)
    else
        std.process.fatal("expected '{s}', found '{s}'", .{"genfens", first});

    const second = tokens.next() orelse std.process.fatal("missing arg '{s}'", .{"seed"});
    opts.seed = if (std.mem.eql(u8, second, "seed"))
        try std.fmt.parseUnsigned(u64, tokens.next().?, 10)
    else
        std.process.fatal("expected '{s}', found '{s}'", .{"seed", second});

    const third = tokens.next() orelse std.process.fatal("missing arg '{s}'", .{"book"});
    const book = if (!std.mem.eql(u8, third, "book"))
        std.process.fatal("expected '{s}', found '{s}'", .{"book", third})
    else
        tokens.next() orelse std.process.fatal("expected arg after '{s}'", .{"book"});
    opts.book = if (!std.mem.eql(u8, book, "None"))
        try std.fs.cwd().readFileAlloc(allocator, book, 32 * 1024 * 1024)
    else
        null;

    return if (tokens.peek()) |extra| {
        // TODO: find out tf age meant by <?extra>
        std.process.fatal("extranous arg '{s}'", .{extra});
    } else opts;
}

fn playRandom(board: *engine.Board, rng: *std.Random.Xoroshiro128, random_moves: usize) void {
    const backup_acc = board.perspectives.first().*;
    const backup_pos = board.positions.first().*;

    find_line: while (true) : ({
        board.perspectives.len = 1;
        board.perspectives.first().* = backup_acc;
        board.positions.len = 1;
        board.positions.first().* = backup_pos;
    }) {
        var ply: usize = 0;
        while (ply < random_moves) : (ply += 1) {
            const rms = engine.movegen.RootMove.List.init(board);
            const rmn = rms.constSlice().len;
            if (rmn == 0) {
                continue :find_line;
            }

            const i = rng.random().uintLessThan(usize, rmn);
            board.doMove(rms.constSlice()[i].constSlice()[0]);
        } else {
            const rms = engine.movegen.RootMove.List.init(board);
            if (rms.constSlice().len == 0) {
                continue :find_line;
            }

            const mat = board.positions.last().material();
            const eval = board.evaluate();
            const norm = engine.evaluation.score.normalize(eval, mat);
            if (norm != std.math.clamp(norm, -200, 200)) {
                continue :find_line;
            }

            break :find_line;
        }
    }
}

pub fn run(pool: *engine.Thread.Pool, args: []const u8) !void {
    const opts = try parseArgs(args, pool.allocator);
    defer if (opts.book) |book| {
        pool.allocator.free(book);
    };

    const board = try pool.allocator.create(engine.Board);
    defer pool.allocator.destroy(board);

    var opt_fens = if (opts.book) |book| std.mem.tokenizeAny(u8, book, &.{ '\n', '\r' }) else null;
    var rng: std.Random.Xoroshiro128 = .init(opts.seed);

    var buffer: [65536]u8 = undefined;
    var writer = std.fs.File.stdout().writer(buffer[0..]);

    for (0..opts.num) |_| {
        const fen = if (opt_fens) |*fens| blk: {
            if (fens.peek() == null) {
                fens.reset();
            }
            break :blk fens.next().?;
        } else engine.Board.Position.startpos[0..];
        try board.parseFen(fen);
        playRandom(board, &rng, if (opt_fens) |_| 4 else 8);

        var fen_buffer: [128]u8 = undefined;
        const board_fen = try board.printFen(fen_buffer[0..]);
        try writer.interface.print("info string genfens {s}\n", .{ board_fen });
    } else try writer.interface.flush();
}
