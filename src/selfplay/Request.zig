const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const viri = @import("viri.zig");

games: ?usize,
win_adj: Adj,
draw_adj: Adj,

pub const Adj = struct {
    min_ply: usize,
    ply_num: usize,
    score: engine.evaluation.score.Int,

    pub const InitError = error{
        TooManyPlies,
        InvalidScore,
    };

    pub fn init(min_ply: usize, ply_num: usize, score: engine.evaluation.score.Int) InitError!Adj {
        const default_line: viri.Line = .{};
        if (default_line.buffer.len < ply_num or min_ply < ply_num) {
            return error.TooManyPlies;
        }

        const min_score = engine.evaluation.score.draw;
        const max_score = engine.evaluation.score.win;
        if (score != std.math.clamp(score, min_score, max_score)) {
            return error.InvalidScore;
        }

        return .{ .min_ply = min_ply, .ply_num = ply_num, .score = score };
    }

    pub fn ok(
        self: *const Adj,
        comptime mode: enum { draw, win },
        line: *const viri.Line,
    ) bool {
        const moves = line.constSlice();
        if (moves.len < self.min_ply) {
            return false;
        }

        const last = moves[moves.len - 1 ..];
        const first = last.ptr - self.ply_num + 1;

        var iter = std.mem.reverseIterator(first[0..self.ply_num]);
        return loop: while (iter.next()) |sm| {
            const abs = if (sm.score < 0) -sm.score else sm.score;
            if (mode == .draw and abs > self.score) {
                break :loop false;
            } else if (mode == .win and abs < self.score) {
                break :loop false;
            }
        } else true;
    }
};
