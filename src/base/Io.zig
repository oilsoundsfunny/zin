const std = @import("std");

const Self = @This();

const capacity = 65536;

reader_buf:	[capacity]u8 align(64),
writer_buf:	[capacity]u8 align(64),

std_reader:	std.fs.File.Reader,
std_writer:	std.fs.File.Writer,

pub fn deinit(self: *const Self) void {
	self.std_reader.file.close();
	self.std_writer.file.close();
}

pub fn init(inp_path: ?[]const u8, out_path: ?[]const u8) !Self {
	var self: Self = undefined;
	@memset(self.reader_buf[0 ..], 0);
	@memset(self.writer_buf[0 ..], 0);

	self.std_reader = if (inp_path) |path| open_input: {
		const file = try std.fs.cwd().openFile(path, .{});
		break :open_input file.reader(self.reader_buf[0 ..]);
	} else std.fs.File.stdin().readerStreaming(self.reader_buf[0 ..]);

	self.std_writer = if (out_path) |path| create_output: {
		const file = try std.fs.cwd().createFile(path, .{});
		break :create_output file.writer(self.writer_buf[0 ..]);
	} else std.fs.File.stdout().writerStreaming(self.writer_buf[0 ..]);

	return self;
}

pub fn reader(self: *Self) *std.Io.Reader {
	return &self.std_reader.interface;
}

pub fn writer(self: *Self) *std.Io.Writer {
	return &self.std_writer.interface;
}
