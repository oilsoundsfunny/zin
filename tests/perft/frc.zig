const base = @import("base");
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
	try base.init();
	defer base.deinit();

	try bitboard.init();
	defer bitboard.deinit();

	var pos = std.mem.zeroInit(engine.Position, .{});
	engine.uci.options.frc = true;

	for (suite[3 ..]) |result| {
		try pos.parseFen(result.fen);
		for (result.nodes, 1 ..) |expected, depth| {
			try std.testing.expectEqual(expected, root.div(&pos, @intCast(depth)));
		}
	}
}
