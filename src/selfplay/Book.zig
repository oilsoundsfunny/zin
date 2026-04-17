const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Book = @This();

list: std.ArrayList([]const u8),

pub fn deinit(self: *Book, gpa: std.mem.Allocator) void {
    for (self.list.items) |fen| {
        const startpos = engine.Board.Position.startpos[0..];
        if (fen.ptr != startpos.ptr or fen.len != startpos.len) {
            gpa.free(fen);
        }
    }
    self.list.deinit(gpa);
}

pub fn init(gpa: std.mem.Allocator, io: std.Io, opt_path: ?[]const u8) !Book {
    var list: std.ArrayList([]const u8) = .empty;
    const path = opt_path orelse {
        try list.append(gpa, engine.Board.Position.startpos[0..]);
        return .{ .list = list };
    };

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const page_size = std.heap.pageSize();
    var buffer: [65536]u8 align(page_size) = undefined;
    var file_r = file.reader(io, buffer[0..]);
    const reader = &file_r.interface;

    while (reader.takeDelimiterInclusive('\n')) |line| {
        const duped = try gpa.dupe(u8, line);
        try list.append(gpa, duped);
    } else |_| {}

    return .{ .list = list };
}

pub fn getRandom(self: Book, rand: std.Random) []const u8 {
    return self.list.items[rand.uintLessThan(usize, self.list.items.len)];
}
