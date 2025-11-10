const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

const root = @import("root.zig");

const suite = [_]root.Result {
	.{
		.fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		.nodes = .{20, 400, 8902, 197281, 4865609, 119060324},
	}, .{
		.fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
		.nodes = .{48, 2039, 97862, 4085603, 193690690, 8031647685},
	}, .{
		.fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
		.nodes = .{14, 191, 2812, 43238, 674624, 11030083},
	}, .{
		.fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
		.nodes = .{6, 264, 9467, 422333, 15833292, 706045033},
	}, .{
		.fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
		.nodes = .{44, 1486, 62379, 2103487, 89941194, 3048196529},
	}, .{
		.fen = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
		.nodes = .{46, 2079, 89890, 3894594, 164075551, 6923051137},
	},
};

test {
	try bitboard.init();
	defer bitboard.deinit();

	const first = 0;
	const len = 0;
	for (suite[first ..][0 .. len]) |result| {
		var pos = engine.Position.zero;
		try pos.parseFen(result.fen);
		for (result.nodes, 1 ..) |expected, depth| {
			const actual = try root.div(&pos, @intCast(depth));
			try std.testing.expectEqual(expected, actual);
		}
	}
}
