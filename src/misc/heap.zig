const std = @import("std");

pub var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub const allocator = arena.allocator();
