const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const ViriFormat = @import("ViriFormat.zig");

const Request = @This();

rng: std.Random.Xoroshiro128 = .init(0x5555555555555555),
games: ?usize,
random_moves: usize,
win_adj: Adj,
draw_adj: Adj,

pub const Adj = struct {
    min_ply: usize,
    ply_num: usize,
    score: engine.evaluation.score.Int,

    pub const Error = error{
        InvalidPlyNum,
        InvalidScore,
    };

    pub fn init(min_ply: usize, ply_num: usize, score: engine.evaluation.score.Int) Error!Adj {
        if (ply_num > @min(min_ply, ViriFormat.Move.Scored.Line.capacity)) {
            return error.InvalidPlyNum;
        }

        const min = engine.evaluation.score.draw;
        const max = engine.evaluation.score.win;
        if (score != std.math.clamp(score, min, max)) {
            return error.InvalidScore;
        }

        return .{ .min_ply = min_ply, .ply_num = ply_num, .score = score };
    }
};

pub fn adjudicate(
    self: *const Request,
    comptime mode: enum { draw, win },
    data: *const ViriFormat,
) bool {
    const cond, const op: std.math.CompareOperator = switch (mode) {
        .draw => .{ &self.draw_adj, .lte },
        .win => .{ &self.win_adj, .gte },
    };

    var i: usize = 0;
    var iter = std.mem.reverseIterator(data.line.constSlice());
    return loop: while (iter.next()) |sm| {
        i += if (i < cond.ply_num) 1 else break :loop true;

        const lhs = @abs(sm.score);
        const rhs = @abs(cond.score);
        if (!std.math.compare(lhs, op, rhs)) {
            break :loop false;
        }
    } else true;
}
