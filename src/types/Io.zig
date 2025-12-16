const std = @import("std");

const Self = @This();

const capacity = 65536;

allocator:	std.mem.Allocator,
inp_buf:	[]u8,
out_buf:	[]u8,

inp_mtx:	std.Thread.Mutex,
out_mtx:	std.Thread.Mutex,

inp_path:	?[]const u8,
out_path:	?[]const u8,

inp:	std.fs.File.Reader,
out:	std.fs.File.Writer,

pub fn deinit(self: *Self) void {
	if (self.inp_path) |_| {
		self.inp.file.close();
	}

	if (self.out_path) |_| {
		self.out.file.close();
	}

	self.allocator.free(self.inp_buf);
	self.allocator.free(self.out_buf);

	self.inp_buf = undefined;
	self.out_buf = undefined;

	self.inp_mtx = .{};
	self.out_mtx = .{};
}

pub fn init(allocator: std.mem.Allocator,
  inp_path: ?[]const u8,
  inp_capacity: usize,
  out_path: ?[]const u8,
  out_capacity: usize) !Self {
	var self: Self = .{
		.allocator = allocator,
		.inp_buf = try allocator.alloc(u8, inp_capacity),
		.out_buf = try allocator.alloc(u8, out_capacity),

		.inp_mtx = .{},
		.out_mtx = .{},

		.inp_path = inp_path,
		.out_path = out_path,

		.inp = undefined,
		.out = undefined,
	};

	self.inp = if (self.inp_path) |path| open_input: {
		const file = try std.fs.cwd().openFile(path, .{});
		break :open_input file.reader(self.inp_buf);
	} else std.fs.File.stdin().readerStreaming(self.inp_buf);

	self.out = if (self.out_path) |path| create_output: {
		const file = try std.fs.cwd().createFile(path, .{});
		break :create_output file.writer(self.out_buf);
	} else std.fs.File.stdout().writerStreaming(self.out_buf);

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

pub fn lineCount(self: *const Self) !usize {
	const path = self.inp_path orelse return 0;
	const file = try std.fs.cwd().openFile(path, .{});

	var buf: [65536]u8 align(64) = undefined;
	var cnt: u64 = 0;
	while (true) {
		const bytes = try file.read(buf[0 ..]);
		if (bytes == 0) {
			return cnt;
		}

		const slice = buf[0 .. bytes];
		cnt += std.mem.count(u8, slice, "\n");
	} else return cnt;
}
