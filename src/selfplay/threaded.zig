const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const ViriFormat = @import("ViriFormat.zig");

fn terminalResult(thread: *engine.Thread) ViriFormat.Result {
    const board = &thread.board;
    const rq = &thread.request.datagen;

    const eval = board.evaluate();
    const mat = board.positions.last().material();
    const w, _, const l = engine.evaluation.score.wdl(eval, mat);

    const r = rq.rng.random().float(f32);
    const is_w = r < w;
    const is_l = r > 1.0 - l;
    return switch (board.positions.last().stm) {
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

    find_line: while (true) : ({ board = thread.board; ply = 0; }) {
        while (ply <= random_moves) : (ply += 1) {
            const root_moves = engine.movegen.Move.Root.List.init(&board);
            const rms = root_moves.constSlice();
            const rmn = rms.len;
            if (rmn == 0) {
                continue :find_line;
            }

            if (ply < random_moves) {
                const i = rq.rng.random().uintLessThan(usize, rmn);
                const m = rms[i].constSlice()[0];
                board.doMove(m);
                continue;
            }

            const eval = board.evaluate();
            const mat = board.positions.last().material();
            const cp = engine.evaluation.score.normalize(eval, mat);
            if (cp != std.math.clamp(cp, -200, 200)) {
                continue :find_line;
            }
        } else break :find_line;
    }
}

fn playOut(thread: *engine.Thread, data: *ViriFormat) !void {
    const board = &thread.board;
    const root_moves = &thread.root_moves;
    const rq = &thread.request.datagen;

    data.* = .{ .head = .init(board), .line = .{} };
    defer data.line.pushUnchecked(.{});

    while (data.head.result == .none) {
        try thread.search();

        const is_terminal = board.isTerminal();
        data.head.result = if (is_terminal)
            terminalResult(thread)
        else if (root_moves.constSlice().len == 0) no_moves: {
            const stm = board.positions.last().stm;
            const is_checked = board.positions.last().isChecked();
            const is_drawn = board.isDrawn();

            break :no_moves if (is_drawn)
                .draw
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
            const mat = board.positions.last().material();
            const stm = board.positions.last().stm.flip();

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

fn writeData(writer: *std.Io.Writer, data: *const ViriFormat) !void {
    try writer.writeAll(std.mem.asBytes(&data.head));
    try writer.writeAll(std.mem.sliceAsBytes(data.line.constSlice()));
}

fn flushData(writer: *std.Io.Writer, thread: *engine.Thread) !void {
    thread.pool.mtx.lock();
    defer thread.pool.mtx.unlock();

    const sink = thread.pool.io.writer();
    try sink.writeAll(writer.buffered());
    _ = writer.consumeAll();
}

pub fn datagen(thread: *engine.Thread) !void {
    const i = thread.idx;
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
    var positions: usize = 0;

    const page_size = std.heap.pageSize();
    var buffer: [4096 * 16]u8 align(page_size) = undefined;
    var writer = std.Io.Writer.fixed(buffer[0..]);
    defer flushData(&writer, thread) catch std.debug.panic("failed to flush data", .{});

    loop: while (readOpening(thread)) |opening| {
        defer thread.pool.allocator.free(opening);
        thread.board.parseFen(opening) catch continue :loop;

        const board = thread.board;
        const played_fen = played;

        while (played - played_fen < repeat and played < games) : (thread.board = board) {
            playRandom(thread) catch continue :loop;
            playOut(thread, &data) catch continue :loop;
            writeData(&writer, &data) catch continue :loop;

            played += 1;
            if (played % 16 == 0) {
                const bytes = writer.buffered().len;
                positions += (bytes - 16 * @sizeOf(ViriFormat.Head)) / 4;

                const ntime = thread.pool.timer.read();
                const pps =
                    @as(f32, @floatFromInt(positions)) /
                    @as(f32, @floatFromInt(ntime)) *
                    std.time.ns_per_s;

                flushData(&writer, thread) catch std.debug.panic("failed to flush data", .{});
                std.log.info(
                    "thread {} played {} games cont. {} positions @ {} pps",
                    .{ i, played, positions, pps },
                );
            }
        }

        if (played >= games) {
            break :loop;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
}
