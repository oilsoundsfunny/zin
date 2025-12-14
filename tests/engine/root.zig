pub const Board = @import("Board.zig");
pub const movegen = @import("movegen.zig");

test {
	@import("std").testing.refAllDecls(@This());
}
