pub const bitboard = @import("bitboard");
pub const engine = @import("engine");
pub const nnue = @import("nnue");
pub const params = @import("params");
pub const types = @import("types");

pub fn deinit() void {
	defer bitboard.deinit();
	defer params.deinit();
	defer engine.deinit();
}

pub fn init() !void {
	try bitboard.init();
	try params.init();
	try engine.init();
}
