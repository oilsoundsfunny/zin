const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const ViriFormat = @import("ViriFormat.zig");

fn terminalResult(thread: *engine.Thread) ViriFormat.Result {
    const board = &thread.board;
    const rq = &thread.request.datagen;

    const eval = board.evaluate();
    const mat = board.positions.top().material();
    const w, const d, _ = engine.evaluation.score.wdl(eval, mat);

    const r = rq.rng.random().float(f32);
    const is_w = r <= w;
    const is_l = r > w + d;
    return switch (board.positions.top().stm) {
        .white => if (is_w) .white else if (is_l) .black else .draw,
        .black => if (is_w) .black else if (is_l) .white else .draw,
    };
}

fn playRandom(thread: *engine.Thread) !void {
    const rq = &thread.request.datagen;
    const random_moves = rq.random_moves;

    var board = thread.board;
    var ply: usize = 0;
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
                const i = rq.rng.random().uintLessThan(usize, rmn);
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
    const root_moves = &thread.root_moves;
    const rq = &thread.request.datagen;

    data.* = .{
        .head = .init(board),
        .line = .{},
    };
    defer data.line.pushUnchecked(.{});

    while (data.head.result == .none) {
        try thread.search();

        data.head.result = if (root_moves.constSlice().len == 0) no_moves: {
            const stm = board.positions.top().stm;
            const is_checked = board.positions.top().isChecked();
            const is_drawn = board.isDrawn();
            const is_terminal = board.isTerminal();

            break :no_moves if (is_drawn)
                .draw
            else if (is_terminal)
                terminalResult(thread)
            else if (!is_checked)
                .draw
            else switch (stm) {
                .white => .black,
                .black => .white,
            };
        } else has_moves: {
            const pv = &root_moves.constSlice()[0];
            const pvm = pv.constSlice()[0];
            const pvs = pv.score;

            board.doMove(pvm);
            const mat = board.positions.top().material();
            const stm = board.positions.top().stm.flip();

            const norm: i16 = @intCast(engine.evaluation.score.normalize(pvs, mat));
            data.line.pushUnchecked(.{
                .move = .init(pvm),
                .score = norm,
            });

            const is_drawn = rq.adjudicate(.draw, data);
            const is_won = rq.adjudicate(.win, data);
            break :has_moves if (is_drawn) .draw else if (!is_won) .none else switch (stm) {
                inline else => |e| @field(ViriFormat.Result, @tagName(e)),
            };
        };
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
    try writer.writeAll(std.mem.sliceAsBytes(data.line.constSlice()));

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
    var data: ViriFormat = undefined;

    const lines = thread.pool.io.lineCount() catch std.debug.panic("unabled to count book", .{});
    const games = if (rq.games) |g| g / n + @intFromBool(g % n != 0) else std.math.maxInt(usize);
    const repeat = if (rq.games) |_| games / lines + @intFromBool(games % lines != 0) else 1;
    var played: usize = 0;

    var buffer: [65536]u8 align(std.heap.pageSize()) = undefined;
    var writer = thread.pool.io.out.file.writer(buffer[0..]);

    const w = &writer.interface;
    defer flushData(thread, w) catch std.debug.panic("failed to flush data", .{});

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
            writeData(thread, &data, w) catch continue :loop;
        }

        if (played >= games) {
            break :loop;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
}
