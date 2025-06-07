pub const heap = @import("heap.zig");
pub const rand = @import("rand.zig");
pub const time = @import("time.zig");
pub const types = @import("types.zig");

test {
	@import("std").testing.refAllDecls(@This());
}
