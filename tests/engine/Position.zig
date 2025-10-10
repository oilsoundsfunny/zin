const base = @import("base");
const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

test {
	var pos = std.mem.zeroInit(engine.Position, .{});
	try pos.parseFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
}

test {
	var pos = std.mem.zeroInit(engine.Position, .{});
	try pos.parseFen(engine.Position.kiwipete);

	const root_moves = engine.movegen.Move.Root.List.init(&pos);
	for (root_moves.constSlice()) |*rm| {
		const m = rm.line.constSlice()[0];
		try std.testing.expect(pos.isMovePseudoLegal(m));
	}

	const illegals = [_]engine.movegen.Move {
		.{.flag = .none, .info = .{.none = 0}, .src = .e2, .dst = .f3},
	};
	for (illegals) |m| {
		try std.testing.expect(!pos.isMovePseudoLegal(m));
	}
}
