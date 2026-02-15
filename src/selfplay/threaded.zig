const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const ViriFormat = @import("ViriFormat.zig");

fn playRandom(thread: *engine.Thread) !void {
    const rq = thread.request.datagen;
    const random_moves = rq.random_moves;

    var board = thread.board;
    var ply: usize = 0;
    var rng = std.Random.Xoroshiro128.init(0x5555555555555555);
    defer thread.board = board;

    while (true) : ({
        board = thread.board;
        ply = 0;
    }) {
        while (ply <= random_moves) : (ply += 1) {
            const root_moves = engine.movegen.Move.Root.List.init(&board);
            const rms = root_moves.constSlice();
            const rmn = rms.len;
            if (rmn == 0) {
                break;
            }

            if (ply < random_moves) {
                const i = rng.random().uintLessThan(usize, rmn);
                const m = rms[i].constSlice()[0];
                board.doMove(m);
            } else {
                const eval = board.evaluate();
                const mat = board.positions.top().material();
                const cp = engine.evaluation.score.normalize(eval, mat);
                if (cp != std.math.clamp(cp, -200, 200)) {
                    break;
                }
            }
        } else break;
    }
}

fn playOut(thread: *engine.Thread, data: *ViriFormat) !void {
    const board = &thread.board;
    // const root_moves = &thread.root_moves;
    // const rq = &thread.request.datagen;

    data.* = .{
        .head = .init(board),
        .line = .{},
    };

    while (data.head.result == .none) {
        try thread.search();

        // data.head.result = if (root_moves.constSlice().len == 0) no_moves: {
        // const is_checked = board.top().isChecked();
        // const is_drawn = board.isDrawn();
        // const is_terminal = board.isTerminal();
        // } else has_moves: {
        // };
    }
}

fn readOpening(thread: *engine.Thread) ![]const u8 {
    thread.pool.mtx.lock();
    defer thread.pool.mtx.unlock();

    const line = try thread.pool.io.reader().takeDelimiterInclusive('\n');
    const dupe = try thread.pool.allocator.dupe(u8, line);
    return dupe;
}

fn writeData(
    thread: *engine.Thread,
    data: *const ViriFormat,
    writer: *std.Io.Writer,
) !void {
    try writer.writeAll(std.mem.asBytes(&data.head));
    for (data.line.constSlice()) |*sm| {
        try writer.writeAll(std.mem.asBytes(sm));
    }

    if (writer.buffer.len - writer.buffered().len < 4096) {
        try flushData(thread, writer);
    }
}

fn flushData(
    thread: *engine.Thread,
    writer: *std.Io.Writer,
) !void {
    thread.pool.mtx.lock();
    defer thread.pool.mtx.unlock();
    try writer.flush();
}

pub fn datagen(thread: *engine.Thread) !void {
    const n = thread.cnt;
    const rq = switch (thread.request) {
        .datagen => |rq| rq,
        else => return,
    };

    const lines = thread.pool.io.lineCount() catch std.debug.panic("unabled to count book", .{});
    const games = if (rq.games) |g| g / n + @intFromBool(g % n != 0) else std.math.maxInt(usize);
    const repeat = if (rq.games) |_| games / lines + @intFromBool(games % lines != 0) else 1;
    var played: usize = 0;

    var data: ViriFormat = undefined;
    var buffer: [65536]u8 align(64) = undefined;
    var writer = thread.pool.io.out.file.writer(buffer[0..]);
    defer flushData(thread, &writer.interface) catch std.debug.panic("failed to flush data", .{});

    loop: while (readOpening(thread)) |opening| {
        defer thread.pool.allocator.free(opening);
        thread.board.parseFen(opening) catch continue :loop;

        const board = thread.board;
        const played_fen = played;

        while (played - played_fen < repeat and played < games) : ({
            played += 1;
            thread.board = board;
        }) {
            playRandom(thread) catch continue :loop;
            playOut(thread, &data) catch continue :loop;
            writeData(thread, &data, &writer.interface) catch continue :loop;
        }

        if (played >= games) {
            break :loop;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
}
