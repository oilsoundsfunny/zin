const std = @import("std");

const Self = @This();

const capacity = 65536;

inp_buf:	[capacity]u8 align(64),
out_buf:	[capacity]u8 align(64),

inp_mtx:	std.Thread.Mutex = .{},
out_mtx:	std.Thread.Mutex = .{},

inp:	std.fs.File.Reader,
out:	std.fs.File.Writer,

pub fn deinit(self: *const Self) void {
	self.inp.file.close();
	self.out.file.close();
}

pub fn init(inp_path: ?[]const u8, out_path: ?[]const u8) !Self {
	var self: Self = undefined;
	@memset(self.inp_buf[0 ..], 0);
	@memset(self.out_buf[0 ..], 0);

	self.inp = if (inp_path) |path| open_input: {
		const file = try std.fs.cwd().openFile(path, .{});
		break :open_input file.reader(self.inp_buf[0 ..]);
	} else std.fs.File.stdin().readerStreaming(self.inp_buf[0 ..]);

	self.out = if (out_path) |path| create_output: {
		const file = try std.fs.cwd().createFile(path, .{});
		break :create_output file.writer(self.out_buf[0 ..]);
	} else std.fs.File.stdout().writerStreaming(self.out_buf[0 ..]);

	return self;
}

pub fn reader(self: *Self) *std.Io.Reader {
	return &self.inp.interface;
}

pub fn writer(self: *Self) *std.Io.Writer {
	return &self.out.interface;
}

pub fn lockReader(self: *Self) void {
	self.inp_mtx.lock();
}

pub fn lockWriter(self: *Self) void {
	self.out_mtx.lock();
}

pub fn unlockReader(self: *Self) void {
	self.inp_mtx.unlock();
}

pub fn unlockWriter(self: *Self) void {
	self.out_mtx.unlock();
}
