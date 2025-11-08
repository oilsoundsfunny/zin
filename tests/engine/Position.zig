const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

test {
	var pos = std.mem.zeroInit(engine.Position, .{});
	try pos.parseFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
}

test {
	const fens = [_][]const u8 {
		"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
		"8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
		// TODO: checked pos
		// "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
		"rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
		"r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
		"1rqbkrbn/1ppppp1p/1n6/p1N3p1/8/2P4P/PP1PPPP1/1RQBKRBN w FBfb - 0 9",
		"rbbqn1kr/pp2p1pp/6n1/2pp1p2/2P4P/P7/BP1PPPP1/R1BQNNKR w HAha - 0 9",
		"rqbbknr1/1ppp2pp/p5n1/4pp2/P7/1PP5/1Q1PPPPP/R1BBKNRN w GAga - 0 9",
	};

	for (fens) |fen| {
		var pos = engine.Position.zero;
		var rma: [1 << 16]bool = undefined;
		var list: engine.movegen.Move.Scored.List = .{};

		try pos.parseFen(fen);
		_ = list.genNoisy(&pos);
		_ = list.genQuiet(&pos);
		@memset(rma[0 ..], false);

		for (list.constSlice()) |sm| {
			const m = sm.move;
			const i = @as(u16, @bitCast(m));

			rma[i] = true;
			try std.testing.expect(pos.isMovePseudoLegal(m));
		}

		for (0 .. 1 << 16) |idx| {
			const i = @as(u16, @truncate(idx));
			const m = @as(engine.movegen.Move, @bitCast(i));

			std.testing.expectEqual(rma[i], pos.isMovePseudoLegal(m)) catch |err| {
				std.debug.print("flag: {s}\n", .{switch (m.flag) {
					inline else => |f| @tagName(f),
				}});

				std.debug.print("src: {c}{c}\n", .{m.src.file().char(), m.src.rank().char()});
				std.debug.print("dst: {c}{c}\n", .{m.dst.file().char(), m.dst.rank().char()});

				return err;
			};
		}
	}
}
