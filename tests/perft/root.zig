const bitboard = @import("bitboard");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

pub const Result = struct {
    fen: []const u8,
    nodes: [6]usize,
};

fn div(comptime root: bool, board: *engine.Board, depth: engine.Thread.Depth) usize {
    if (depth <= 0) {
        return 1;
    }

    const pos = board.top();
    var ml: engine.movegen.Move.Scored.List = .{};
    var sum: usize = 0;
    _ = ml.genNoisy(pos);
    _ = ml.genQuiet(pos);

    for (ml.slice()) |sm| {
        const m = sm.move;
        if (!board.top().isMoveLegal(m)) {
            continue;
        }

        const this = blk: {
            board.doMove(m);
            defer board.undoMove();
            break :blk div(false, board, depth - 1);
        };
        sum += this;

        if (root) {
            const s = m.toString(board);
            const l = m.toStringLen();
            std.debug.print("{s}:\t{d}\n", .{ s[0..l], this });
        }
    }

    return sum;
}

pub fn perft(board: *engine.Board, depth: engine.Thread.Depth) !usize {
    var timer = try std.time.Timer.start();
    const nodes = div(true, board, depth);
    const time = timer.lap();
    const mtime = time / std.time.ns_per_ms;
    const nps = nodes * std.time.ns_per_s / time;

    std.debug.print("info depth {d} nodes {d} time {d} nps {d}\n", .{ depth, nodes, mtime, nps });
    return nodes;
}

test {
    _ = @import("standard.zig");
    _ = @import("frc.zig");
}
