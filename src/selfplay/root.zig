const base = @import("base");
const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

fn match(fen: []const u8) !void {
	var player: engine.search.Info.List = .{};
	try player.alloc(1);
	defer base.heap.allocator(player.slice);

	try player.pos.parseFen(fen);
	while (true) {
		player.prep();
		player.search();

		const sm: engine.movegen.Move.Scored = .{
			.move = player.rms.constSlice()[0].line.constSlice()[0],
			.score = @intCast(player.rms.constSlice()[0].score),
		};
	}
}

fn tourney() !void {
}

pub fn main() !void {
}
