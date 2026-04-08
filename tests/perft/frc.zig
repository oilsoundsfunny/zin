const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

const root = @import("root.zig");

const suite = [_]root.Result{
    .{
        .fen = "1rqbkrbn/1ppppp1p/1n6/p1N3p1/8/2P4P/PP1PPPP1/1RQBKRBN w KQkq - 0 9",
        .moves = &.{},
        .nodes = &.{ 29, 502, 14569, 287739, 8652810, 191762235 },
    },

    .{
        .fen = "rbbqn1kr/pp2p1pp/6n1/2pp1p2/2P4P/P7/BP1PPPP1/R1BQNNKR w KQkq - 0 9",
        .moves = &.{},
        .nodes = &.{ 27, 916, 25798, 890435, 26302461, 924181432 },
    },

    .{
        .fen = "rqbbknr1/1ppp2pp/p5n1/4pp2/P7/1PP5/1Q1PPPPP/R1BBKNRN w KQkq - 0 9",
        .moves = &.{},
        .nodes = &.{ 24, 600, 15347, 408207, 11029596, 308553169 },
    },

    .{
        .fen = "1rqbkrbn/1ppppp1p/1n6/p1N3p1/8/2P4P/PP1PPPP1/1RQBKRBN w FBfb - 0 9",
        .moves = &.{},
        .nodes = &.{ 29, 502, 14569, 287739, 8652810, 191762235 },
    },

    .{
        .fen = "rbbqn1kr/pp2p1pp/6n1/2pp1p2/2P4P/P7/BP1PPPP1/R1BQNNKR w HAha - 0 9",
        .moves = &.{},
        .nodes = &.{ 27, 916, 25798, 890435, 26302461, 924181432 },
    },

    .{
        .fen = "rqbbknr1/1ppp2pp/p5n1/4pp2/P7/1PP5/1Q1PPPPP/R1BBKNRN w GAga - 0 9",
        .moves = &.{},
        .nodes = &.{ 24, 600, 15347, 408207, 11029596, 308553169 },
    },

    .{
        .fen = "1rqbkrbn/1ppppp1p/1n6/p1N3p1/8/2P4P/PP1PPPP1/1RQBKRBN w FB - 0 9",
        .moves = &.{},
        .nodes = &.{ 29, 502, 14569, 287739, 8652810, 191478380 },
    },

    .{
        .fen = "rbbqn1kr/pp2p1pp/6n1/2pp1p2/2P4P/P7/BP1PPPP1/R1BQNNKR w HA - 0 9",
        .moves = &.{},
        .nodes = &.{ 27, 889, 25018, 840689, 24811321, 851198557 },
    },

    .{
        .fen = "rqbbknr1/1ppp2pp/p5n1/4pp2/P7/1PP5/1Q1PPPPP/R1BBKNRN w GA - 0 9",
        .moves = &.{},
        .nodes = &.{ 24, 600, 15347, 407633, 11013726, 307250511 },
    },
};

test {
    try bitboard.init();
    defer bitboard.deinit();

    try engine.init();
    defer engine.deinit();

    for (suite[0..1]) |result| {
        var board: engine.Board = .{};
        try board.parseFen(result.fen);

        for (result.moves) |ms| {
            const pos = board.positions.last();
            var list: engine.movegen.Move.List = .{};
            _ = list.genNoisy(pos);
            _ = list.genQuiet(pos);

            const m = find_move: for (list.constSlice()) |move| {
                const s = move.toString(&board);
                const l = move.toStringLen();
                if (std.mem.eql(u8, s[0..l], ms)) {
                    break :find_move move;
                }
            } else return error.NotFound;

            try std.testing.expect(pos.isMoveLegal(m));
            board.doMove(m);
        }

        for (result.nodes, 1..) |expected, depth| {
            const actual = try root.perft(&board, @intCast(depth));
            std.testing.expectEqual(expected, actual) catch |err| {
                @breakpoint();
                return err;
            };
        }
    }
}
