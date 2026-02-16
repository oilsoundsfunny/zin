const bitboard = @import("bitboard");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

test {
    try bitboard.init();
    defer bitboard.deinit();

    try params.init();
    defer params.deinit();

    try engine.init();
    defer engine.deinit();

    var board: engine.Board = .{};
    try board.parseFen("1k1r4/1pp4p/p7/4p3/8/P5P1/1PP4P/2K1R3 w - - 0 1");

    const move: engine.movegen.Move = .{
        .flag = .noisy,
        .src = .e1,
        .dst = .e5,
    };
    const pawn = params.values.see_pruning_pawn;
    try std.testing.expect(board.positions.top().see(.pruning, move, pawn));
}

test {
    try bitboard.init();
    defer bitboard.deinit();

    try params.init();
    defer params.deinit();

    try engine.init();
    defer engine.deinit();

    var board: engine.Board = .{};
    try board.parseFen("1k1r3q/1ppn3p/p4b2/4p3/8/P2N2P1/1PP1R1BP/2K1Q3 w - - 0 1");

    const move: engine.movegen.Move = .{
        .flag = .noisy,
        .src = .d3,
        .dst = .e5,
    };

    const draw = engine.evaluation.score.draw;
    const pawn = params.values.see_pruning_pawn;
    const knight = params.values.see_pruning_knight;

    try std.testing.expect(board.positions.top().see(.pruning, move, draw - knight));
    try std.testing.expect(board.positions.top().see(.pruning, move, pawn - knight));

    // try std.testing.expect(!board.positions.top().see(.pruning, move, -draw));
    // try std.testing.expect(!board.positions.top().see(.pruning, move, -pawn));
}
