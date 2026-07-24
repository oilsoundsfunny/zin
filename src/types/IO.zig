const std = @import("std");
const zio = @import("zio");

const Self = @This();

const capacity = 65536;

inp_path: ?[]const u8,
out_path: ?[]const u8,

inp_mtx: zio.Mutex,
out_mtx: zio.Mutex,

zio_rt: *zio.Runtime,
file_reader: std.Io.File.Reader,
file_writer: std.Io.File.Writer,

pub fn deinit(self: *Self, gpa: std.mem.Allocator, zio_rt: *zio.Runtime) void {
    gpa.free(self.file_reader.interface.buffer);
    gpa.free(self.file_writer.interface.buffer);

    if (self.inp_path) |_| {
        self.file_reader.file.close(zio_rt.io());
    }

    if (self.out_path) |_| {
        self.file_writer.file.close(zio_rt.io());
    }
}

pub fn init(
    gpa: std.mem.Allocator,
    zio_rt: *zio.Runtime,
    inp_path: ?[]const u8,
    inp_len: usize,
    out_path: ?[]const u8,
    out_len: usize,
) !Self {
    const inp_buf = try gpa.alignedAlloc(u8, .@"64", inp_len);
    const out_buf = try gpa.alignedAlloc(u8, .@"64", out_len);

    const cwd: std.Io.Dir = .cwd();
    const io = zio_rt.io();
    return .{
        .inp_path = inp_path,
        .out_path = out_path,

        .inp_mtx = .init,
        .out_mtx = .init,

        .zio_rt = zio_rt,

        .file_reader = if (inp_path) |path| open: {
            const file = try cwd.openFile(io, path, .{});
            break :open file.reader(io, inp_buf);
        } else std.Io.File.stdin().readerStreaming(io, inp_buf),

        .file_writer = if (out_path) |path| create: {
            const file = try cwd.createFile(io, path, .{});
            break :create file.writer(io, out_buf);
        } else std.Io.File.stdout().writerStreaming(io, out_buf),
    };
}

pub fn reader(self: *Self) *std.Io.Reader {
    return &self.file_reader.interface;
}

pub fn writer(self: *Self) *std.Io.Writer {
    return &self.file_writer.interface;
}

pub fn lockReader(self: *Self) !void {
    try self.inp_mtx.lock();
}

pub fn lockWriter(self: *Self) !void {
    try self.out_mtx.lock();
}

pub fn lockReaderUncancelable(self: *Self) void {
    self.inp_mtx.lockUncancelable();
}

pub fn lockWriterUncancelable(self: *Self) void {
    self.out_mtx.lockUncancelable();
}

pub fn unlockReader(self: *Self) void {
    self.inp_mtx.unlock();
}

pub fn unlockWriter(self: *Self) void {
    self.out_mtx.unlock();
}
