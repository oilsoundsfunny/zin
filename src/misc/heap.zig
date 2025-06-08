const builtin = @import("builtin");
const std = @import("std");

pub var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const allocator = if (builtin.is_test) std.testing.allocator else arena.allocator();
