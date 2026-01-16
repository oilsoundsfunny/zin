const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const viri = @import("viri.zig");

// TODO: change to 8 if dont gen with DFRC/UHO book
const random_moves = 8;

fn playRandom(thread: *engine.Thread) !void {
    var board = thread.board;
    var ply: usize = 0;
    var rng = std.Random.Xoroshiro128.init(0xa69f73cca23a9ac5);
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
                const mat = board.top().material();
                const cp = engine.evaluation.score.normalize(eval, mat);
                if (cp != std.math.clamp(cp, -200, 200)) {
                    break;
                }
            }
        } else break;
    }
}

fn playOut(thread: *engine.Thread, data: *viri.Data, line: *viri.Line) !void {
    const board = &thread.board;
    const root_moves = &thread.root_moves;

    data.* = viri.Data.fromBoard(board);
    try line.resize(0);

    var result: viri.Result = .none;
    while (result == .none) {
        try thread.search();

        const rms = root_moves.constSlice();
        const rmn = rms.len;
        result = if (rmn == 0) no_moves: {
            const stm = board.top().stm;
            const is_drawn = board.top().isChecked() or
                board.isDrawn() or
                board.isTerminal();

            break :no_moves if (is_drawn) .draw else switch (stm) {
                .white => .black,
                .black => .white,
            };
        } else has_moves: {
            const pv = &rms[0];
            const pvm = pv.constSlice()[0];

            const mat = board.top().material();
            const pvs = engine.evaluation.score.normalize(@intCast(pv.score), mat);

            const stm = board.top().stm;
            board.doMove(pvm);
            try line.append(.{
                .move = viri.Move.fromMove(pvm),
                .score = @intCast(pvs),
            });

            const is_drawn = thread.request.datagen.draw_adj.ok(.draw, line);
            const is_won = thread.request.datagen.win_adj.ok(.win, line);
            break :has_moves if (!is_drawn and !is_won)
                .none
            else if (is_drawn)
                .draw
            else switch (stm) {
                inline else => |e| @field(viri.Result, @tagName(e)),
            };
        };
    } else {
        data.result = result;
        try line.append(.{});
    }
}

fn readOpening(thread: *engine.Thread) ![]const u8 {
    thread.pool.mtx.lock();
    defer thread.pool.mtx.unlock();

    const line = try thread.pool.io.reader().takeDelimiterInclusive('\n');
    const dupe = try thread.pool.allocator.dupe(u8, line);
    return dupe;
}

fn flushData(thread: *engine.Thread, writer: *std.Io.Writer) !void {
    thread.pool.mtx.lock();
    defer thread.pool.mtx.unlock();

    const pool_w = thread.pool.io.writer();
    try pool_w.writeAll(writer.buffered());
    _ = writer.consumeAll();

    if (pool_w.buffer.len - pool_w.buffered().len < 4096) {
        try pool_w.flush();
    }
}

fn writeData(
    thread: *engine.Thread,
    writer: *std.Io.Writer,
    data: *viri.Data,
    line: *viri.Line,
) !void {
    try writer.writeAll(std.mem.asBytes(data));
    for (line.constSlice()) |*sm| {
        try writer.writeAll(std.mem.asBytes(sm));
    }

    if (writer.buffer.len - writer.buffered().len < 4096) {
        try flushData(thread, writer);
    }
}

pub fn datagen(thread: *engine.Thread) !void {
    const i = thread.idx;
    const n = thread.cnt;
    const rq = switch (thread.request) {
        .datagen => |rq| rq,
        else => return,
    };

    const lines = thread.pool.io.lineCount() catch std.debug.panic("unabled to count book", .{});
    const games = if (rq.games) |g| g / n + @intFromBool(g % n != 0) else std.math.maxInt(usize);
    const repeat = if (rq.games) |_| games / lines + @intFromBool(games % lines != 0) else 1;
    var played: usize = 0;

    var buffer: [65536]u8 align(64) = undefined;
    var writer = thread.pool.io.out.file.writer(buffer[0..]);

    loop: while (readOpening(thread)) |opening| {
        defer thread.pool.allocator.free(opening);
        thread.board.parseFen(opening) catch {
            std.log.err("worker {d} failed to parse fen: '{s}'", .{ i, opening });
            continue :loop;
        };

        const board = thread.board;
        const played_fen = played;

        while (played - played_fen < repeat and played < games) : ({
            played += 1;
            thread.board = board;
            if (played % 1000 == 0) {
                std.log.info("worker {d} played {d} games", .{ i, played });
            }
        }) {
            playRandom(thread) catch |err| {
                std.log.err("worker {d} failed to selfplay: '{t}'", .{ i, err });
                continue :loop;
            };

            var data: viri.Data = undefined;
            var line: viri.Line = undefined;
            playOut(thread, &data, &line) catch |err| {
                std.log.err("worker {d} failed to selfplay: '{t}'", .{ i, err });
                continue :loop;
            };

            writeData(thread, &writer.interface, &data, &line) catch |err| {
                std.log.err("worker {d} failed to write data: '{t}'", .{ i, err });
                continue :loop;
            };
        }

        if (played >= games) {
            break :loop;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => {
            try flushData(thread, &writer.interface);
            return err;
        },
    }

    try flushData(thread, &writer.interface);
}
