const bitboard = @import("bitboard");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

pub const Result = struct {
    fen: []const u8,
    moves: []const []const u8,
    nodes: []const usize,
};

fn div(comptime root: bool, board: *engine.Board, depth: engine.Thread.Depth) usize {
    if (depth <= 0) {
        return 1;
    }

    const pos = board.positions.last();
    var ml: engine.movegen.Move.List = .{};
    var sum: usize = 0;
    _ = ml.genNoisy(pos);
    _ = ml.genQuiet(pos);

    for (ml.slice()) |m| {
        if (!pos.isMoveLegal(m)) {
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
    const io = std.testing.io;
    const past: std.Io.Timestamp = .now(io, .real);
    const nodes = div(true, board, depth);

    const now: std.Io.Timestamp = .now(io, .real);
    const elapsed: u64 = @intCast(past.durationTo(now).toNanoseconds());
    const mtime = elapsed / std.time.ns_per_ms;
    const nps = nodes * std.time.ns_per_s / elapsed;

    std.debug.print("info depth {d} nodes {d} time {d} nps {d}\n", .{ depth, nodes, mtime, nps });
    return nodes;
}

test {
    _ = @import("standard.zig");
    _ = @import("frc.zig");
}
