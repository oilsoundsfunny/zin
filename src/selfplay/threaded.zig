const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const ViriFormat = @import("ViriFormat.zig");

fn terminalResult(thread: *engine.Thread) ViriFormat.Result {
    const board = &thread.board;
    const pos = board.positions.last();

    const mat = pos.material();
    const eval = board.evaluate();
    const norm = engine.evaluation.score.normalize(eval, mat);

    return switch (pos.stm) {
        .white => if (norm > 200) .white else if (norm < -200) .black else .draw,
        .black => if (norm > 200) .black else if (norm < -200) .white else .draw,
    };
}

fn playRandom(thread: *engine.Thread, pool: *const engine.Thread.Pool) !void {
    const rq = &thread.job.datagen;
    const random_moves = rq.random_moves;

    const board = try pool.gpa.create(engine.Board);
    defer {
        thread.board = board.*;
        pool.gpa.destroy(board);
    }

    find_line: while (true) : (board.* = thread.board) {
        var ply: usize = 0;
        while (ply < random_moves) : (ply += 1) {
            const root_moves = engine.movegen.RootMove.List.init(board);
            const rms = root_moves.constSlice();
            const rmn = rms.len;
            if (rmn == 0) {
                continue :find_line;
            }

            const i = rq.rng.random().uintLessThan(usize, rmn);
            const m = rms[i].constSlice()[0];
            board.doMove(m);
        } else {
            const mat = board.positions.last().material();
            const eval = board.evaluate();
            const norm = engine.evaluation.score.normalize(eval, mat);
            if (norm == std.math.clamp(norm, -200, 200)) {
                break :find_line;
            }
        }
    }
}

fn playOut(thread: *engine.Thread, pool: *engine.Thread.Pool, data: *ViriFormat) !void {
    const board = &thread.board;
    const root_moves = &thread.root_moves;
    const rq = &thread.job.datagen;

    data.* = .{ .head = .init(board), .line = .init };
    defer data.line.pushUnchecked(.init);

    while (data.head.result == .none) {
        try thread.search(pool);

        const is_terminal = board.isTerminal();
        data.head.result = if (root_moves.constSlice().len == 0) no_moves: {
            const stm = board.positions.last().stm;
            const is_checked = board.positions.last().isChecked();
            const is_drawn = board.isDrawn();

            break :no_moves if (is_terminal)
                terminalResult(thread)
            else if (is_drawn or !is_checked)
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
            const pos = board.positions.last();
            const mat = pos.material();
            const stm = pos.stm.flip();

            const norm = engine.evaluation.score.normalize(@intCast(pvs), mat);
            data.line.pushUnchecked(.{
                .move = .init(pvm),
                .score = @intCast(norm),
            });

            const is_drawn = rq.adjudicate(.draw, data);
            const is_won = rq.adjudicate(.win, data);
            break :has_moves if (is_drawn) .draw else if (!is_won) .none else switch (stm) {
                inline else => |e| @field(ViriFormat.Result, @tagName(e)),
            };
        };
    }
}

fn readOpening(pool: *engine.Thread.Pool) ![]const u8 {
    try pool.io.lockReader();
    defer pool.io.unlockReader();

    const line = try pool.io.reader().takeDelimiterInclusive('\n');
    const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
    return pool.gpa.dupe(u8, trimmed);
}

fn writeData(pool: *engine.Thread.Pool, data: *const ViriFormat) !void {
    try pool.io.lockWriter();
    defer pool.io.unlockWriter();

    const writer = pool.io.writer();
    try writer.writeAll(std.mem.asBytes(&data.head));
    try writer.writeAll(std.mem.sliceAsBytes(data.line.constSlice()));

    if (writer.buffer.len - writer.buffered().len < 4096) {
        try writer.flush();
    }
}

pub fn run(thread: *engine.Thread, pool: *engine.Thread.Pool) !void {
    const i = thread - &pool.threads.items[0];
    const n = pool.threads.items.len;
    const rq = &thread.job.datagen;
    var data: ViriFormat = undefined;

    const games = rq.games / n + @intFromBool(rq.games % n != 0);
    var played: usize = 0;
    var positions: usize = 0;

    while (played < games) {
        const opening = rq.book.getRandom(rq.rng.random());
        try thread.board.parseFen(opening);
        try playRandom(thread, pool);
        try playOut(thread, pool, &data);
        try writeData(pool, &data);

        played += 1;
        positions += data.line.constSlice().len -| 1;

        if (played % 256 == 0 or played >= games) {
            const ntime = pool.elapsed();
            const pps =
                @as(f64, @floatFromInt(positions)) /
                @as(f64, @floatFromInt(ntime)) *
                std.time.ns_per_s;
            std.log.info(
                "thread {} finished {} games, generated {} positions @ {:.4} pps",
                .{ i, played, positions, pps },
            );
        }
    }
}
