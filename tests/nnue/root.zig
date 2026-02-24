const engine = @import("engine");
const nnue = @import("nnue");
const std = @import("std");
const types = @import("types");

test {
    var board: engine.Board = .{};
    try board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
}
