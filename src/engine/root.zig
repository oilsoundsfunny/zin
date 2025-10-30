pub const evaluation = @import("evaluation.zig");
pub const movegen = @import("movegen.zig");
pub const Position = @import("Position.zig");
pub const search = @import("search.zig");
pub const transposition = @import("transposition.zig");
pub const uci = @import("uci.zig");
pub const zobrist = @import("zobrist.zig");

pub fn deinit() void {
}

pub fn init() !void {
	try uci.init();
	try zobrist.init();

	search.io = try @TypeOf(search.io).init(null, null);
}
