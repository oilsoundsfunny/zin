const std = @import("std");

const Self = @This();

const capacity = 65536;

ipath: ?[]const u8,
opath: ?[]const u8,

stdio: std.Io,
imtx: std.Io.Mutex,
omtx: std.Io.Mutex,

fr: std.Io.File.Reader,
fw: std.Io.File.Writer,

pub fn deinit(self: *Self, gpa: std.mem.Allocator, io: std.Io) void {
    gpa.free(self.fr.interface.buffer);
    gpa.free(self.fw.interface.buffer);

    if (self.ipath) |_| {
        self.fr.file.close(io);
    }

    if (self.opath) |_| {
        self.fw.file.close(io);
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
    const ibuf = try gpa.alignedAlloc(u8, .@"64", inp_len);
    const obuf = try gpa.alignedAlloc(u8, .@"64", out_len);

    const cwd = std.Io.Dir.cwd();
    return .{
        .ipath = inp_path,
        .opath = out_path,

        .stdio = stdio,
        .imtx = .init,
        .omtx = .init,

        .fr = if (inp_path) |path| open: {
            const file = try cwd.openFile(stdio, path, .{});
            break :open file.reader(stdio, ibuf);
        } else std.Io.File.stdin().readerStreaming(stdio, ibuf),

        .fw = if (out_path) |path| create: {
            const file = try cwd.createFile(stdio, path, .{});
            break :create file.writer(stdio, obuf);
        } else std.Io.File.stdout().writerStreaming(stdio, obuf),
    };
}

pub fn reader(self: *Self) *std.Io.Reader {
    return &self.fr.interface;
}

pub fn writer(self: *Self) *std.Io.Writer {
    return &self.fw.interface;
}

pub fn lockReader(self: *Self) !void {
    try self.imtx.lock(self.stdio);
}

pub fn lockWriter(self: *Self) !void {
    try self.omtx.lock(self.stdio);
}

pub fn lockReaderUncancelable(self: *Self) void {
    self.imtx.lockUncancelable(self.stdio);
}

pub fn lockWriterUncancelable(self: *Self) void {
    self.omtx.lockUncancelable(self.stdio);
}

pub fn unlockReader(self: *Self) void {
    self.imtx.unlock(self.stdio);
}

pub fn unlockWriter(self: *Self) void {
    self.omtx.unlock(self.stdio);
}
