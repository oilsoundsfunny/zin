pub const heap = @import("heap.zig");
pub const time = @import("time.zig");
pub const types = @import("types.zig");

pub fn deinit() void {
	heap.deinit();
}

pub fn init() !void {
	try time.init();
}
