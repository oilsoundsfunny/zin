const bitboard = @import("bitboard");
const config = @import("config");
const engine = @import("engine");
const misc = @import("misc");
const std = @import("std");

pub const std_options = std.Options {
	.log_level = .info,
	.side_channels_mitigations = .basic,
};

pub fn main() !void {
	try engine.uci.printEngine();
	_ = try engine.uci.parseCommand("setoption name Hash value 64");
	_ = try engine.uci.parseCommand("setoption name Threads value 1");
	_ = try engine.uci.parseCommand("position startpos");

	try misc.time.init();
	defer misc.heap.arena.deinit();

	const input_thread = try std.Thread.spawn(.{}, engine.uci.readInput, .{});
	defer std.Thread.join(input_thread);
}
