const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Book = @This();

list: std.ArrayList([]const u8),

pub fn deinit(self: *Book, allocator: std.mem.Allocator) void {
    for (self.list.items) |fen| {
        const startpos = engine.Board.Position.startpos[0..];
        if (fen.ptr != startpos.ptr or fen.len != startpos.len) {
            allocator.free(fen);
        }
    }
    self.list.deinit(allocator);
}

pub fn init(allocator: std.mem.Allocator, opt_path: ?[]const u8) !Book {
    var list: std.ArrayList([]const u8) = .empty;
    const path = opt_path orelse {
        try list.append(allocator, engine.Board.Position.startpos[0..]);
        return .{ .list = list };
    };

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const page_size = std.heap.pageSize();
    var buffer: [65536]u8 align(page_size) = undefined;
    var file_r = file.reader(buffer[0..]);
    const reader = &file_r.interface;

    while (reader.takeDelimiterInclusive('\n')) |line| {
        const duped = try allocator.dupe(u8, line);
        try list.append(allocator, duped);
    } else |_| {}

    return .{ .list = list };
}

pub fn getRandom(self: Book, rand: std.Random) []const u8 {
    return self.list.items[rand.uintLessThan(usize, self.list.items.len)];
}
