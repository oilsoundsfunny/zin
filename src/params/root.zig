pub const psqt = @import("psqt.zig").tbl;
pub const pts = @import("pts.zig").tbl;

test {
	@import("std").testing.refAllDecls(@This());
}
