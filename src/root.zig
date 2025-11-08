const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

pub const author = "oilsoundsfunny";
pub const name = "zin";
pub const version = std.SemanticVersion {
	.major = 0,
	.minor = 1,
	.patch = 0,
};

pub const std_options = std.Options {
	.side_channels_mitigations = .basic,
};

pub fn main() !void {
	try bitboard.init();
	defer bitboard.deinit();

	try engine.init();
	defer engine.deinit();

	try engine.uci.loop();
}
