const bitboard = @import("bitboard");
const engine = @import("engine");
const misc = @import("misc");
const std = @import("std");

pub fn main() !void {
	try bitboard.init();
	try misc.time.init();
	defer misc.heap.arena.deinit();

	const input_thrd = try std.Thread.spawn(.{}, engine.uci.loop, .{});
	defer std.Thread.join(input_thrd);
}
