const std = @import("std");

const Self = @This();

const capacity = 65536;

inp_path: ?[]const u8,
out_path: ?[]const u8,

inp: std.Io.File.Reader,
out: std.Io.File.Writer,

pub fn deinit(self: *Self, gpa: std.mem.Allocator, io: std.Io) void {
    gpa.free(self.inp.interface.buffer);
    gpa.free(self.out.interface.buffer);

    if (self.inp_path) |_| {
        self.inp.file.close(io);
    }

    if (self.out_path) |_| {
        self.out.file.close(io);
    }
}

pub fn init(
    gpa: std.mem.Allocator,
    io: std.Io,
    inp_path: ?[]const u8,
    inp_capacity: usize,
    out_path: ?[]const u8,
    out_capacity: usize,
) !Self {
    const inp_buf = try gpa.alignedAlloc(u8, .@"64", inp_capacity);
    const out_buf = try gpa.alignedAlloc(u8, .@"64", out_capacity);

    const cwd = std.Io.Dir.cwd();
    return .{
        .inp_path = inp_path,
        .out_path = out_path,

        .inp = if (inp_path) |path| open: {
            const file = try cwd.openFile(io, path, .{});
            break :open file.reader(io, inp_buf);
        } else std.Io.File.stdin().readerStreaming(io, inp_buf),

        .out = if (out_path) |path| create: {
            const file = try cwd.createFile(io, path, .{});
            break :create file.writer(io, out_buf);
        } else std.Io.File.stdout().writerStreaming(io, out_buf),
    };
}

pub fn reader(self: *Self) *std.Io.Reader {
    return &self.inp.interface;
}

pub fn writer(self: *Self) *std.Io.Writer {
    return &self.out.interface;
}
