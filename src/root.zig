const bitboard = @import("bitboard");
const misc = @import("misc");
const std = @import("std");

pub fn main() !void {
	try bitboard.init();
	try misc.time.init();
	defer misc.heap.arena.deinit();
}
