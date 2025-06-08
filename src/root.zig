const bitboard = @import("bitboard");
const config = @import("config");
const engine = @import("engine");
const misc = @import("misc");
const std = @import("std");

pub fn main() !void {
	try engine.Thread.Pool.global.allocate(1);
	try engine.transposition.Table.global.allocate(64);
	try engine.uci.printEngine();
	try misc.time.init();
	defer misc.heap.arena.deinit();

	const input_thread = try std.Thread.spawn(.{}, engine.uci.parseInput, .{});
	defer std.Thread.join(input_thread);
}
