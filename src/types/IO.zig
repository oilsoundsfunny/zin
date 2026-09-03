const std = @import("std");

const Self = @This();

const capacity = 65536;

inp_path: ?[]const u8,
out_path: ?[]const u8,

stdio: std.Io,
inp_mtx: std.Io.Mutex,
out_mtx: std.Io.Mutex,

file_reader: std.Io.File.Reader,
file_writer: std.Io.File.Writer,

pub fn deinit(self: *Self, gpa: std.mem.Allocator, stdio: std.Io) void {
    gpa.free(self.file_reader.interface.buffer);
    gpa.free(self.file_writer.interface.buffer);

    if (self.inp_path) |_| {
        self.file_reader.file.close(stdio);
    }

    if (self.out_path) |_| {
        self.file_writer.file.close(stdio);
    }
}

pub fn init(
    gpa: std.mem.Allocator,
    stdio: std.Io,
    inp_path: ?[]const u8,
    inp_len: usize,
    out_path: ?[]const u8,
    out_len: usize,
) !Self {
    const inp_buf = try gpa.alignedAlloc(u8, .@"64", inp_len);
    const out_buf = try gpa.alignedAlloc(u8, .@"64", out_len);

    const cwd: std.Io.Dir = .cwd();
    return .{
        .inp_path = inp_path,
        .out_path = out_path,

        .stdio = stdio,
        .inp_mtx = .init,
        .out_mtx = .init,

        .file_reader = if (inp_path) |path| open: {
            const file = try cwd.openFile(stdio, path, .{});
            break :open file.reader(stdio, inp_buf);
        } else std.Io.File.stdin().readerStreaming(stdio, inp_buf),

        .file_writer = if (out_path) |path| create: {
            const file = try cwd.createFile(stdio, path, .{});
            break :create file.writer(stdio, out_buf);
        } else std.Io.File.stdout().writerStreaming(stdio, out_buf),
    };
}

pub fn reader(self: *Self) *std.Io.Reader {
    return &self.file_reader.interface;
}

pub fn writer(self: *Self) *std.Io.Writer {
    return &self.file_writer.interface;
}

pub fn lockReader(self: *Self) !void {
    try self.inp_mtx.lock(self.stdio);
}

pub fn lockWriter(self: *Self) !void {
    try self.out_mtx.lock(self.stdio);
}

pub fn lockReaderUncancelable(self: *Self) void {
    self.inp_mtx.lockUncancelable(self.stdio);
}

pub fn lockWriterUncancelable(self: *Self) void {
    self.out_mtx.lockUncancelable(self.stdio);
}

pub fn unlockReader(self: *Self) void {
    self.inp_mtx.unlock(self.stdio);
}

pub fn unlockWriter(self: *Self) void {
    self.out_mtx.unlock(self.stdio);
}
