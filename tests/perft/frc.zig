const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

const root = @import("root.zig");

const suite = [_]root.Result {
	.{
		.fen = "1rqbkrbn/1ppppp1p/1n6/p1N3p1/8/2P4P/PP1PPPP1/1RQBKRBN w KQkq - 0 9",
		.nodes = .{29, 502, 14569, 287739, 8652810, 191762235},
	}, .{
		.fen = "rbbqn1kr/pp2p1pp/6n1/2pp1p2/2P4P/P7/BP1PPPP1/R1BQNNKR w KQkq - 0 9",
		.nodes = .{27, 916, 25798, 890435, 26302461, 924181432},
	}, .{
		.fen = "rqbbknr1/1ppp2pp/p5n1/4pp2/P7/1PP5/1Q1PPPPP/R1BBKNRN w KQkq - 0 9",
		.nodes = .{24, 600, 15347, 408207, 11029596, 308553169},
	},

	.{
		.fen = "1rqbkrbn/1ppppp1p/1n6/p1N3p1/8/2P4P/PP1PPPP1/1RQBKRBN w FBfb - 0 9",
		.nodes = .{29, 502, 14569, 287739, 8652810, 191762235},
	}, .{
		.fen = "rbbqn1kr/pp2p1pp/6n1/2pp1p2/2P4P/P7/BP1PPPP1/R1BQNNKR w HAha - 0 9",
		.nodes = .{27, 916, 25798, 890435, 26302461, 924181432},
	}, .{
		.fen = "rqbbknr1/1ppp2pp/p5n1/4pp2/P7/1PP5/1Q1PPPPP/R1BBKNRN w GAga - 0 9",
		.nodes = .{24, 600, 15347, 408207, 11029596, 308553169},
	},
};

test {
	try bitboard.init();
	defer bitboard.deinit();

	const first = 3;
	const len = 3;
	for (suite[first ..][0 .. len]) |result| {
		var pos = engine.Position.zero;
		try pos.parseFen(result.fen);
		for (result.nodes, 1 ..) |expected, depth| {
			const actual = try root.div(&pos, @intCast(depth));
			try std.testing.expectEqual(expected, actual);
		}
	}
}
