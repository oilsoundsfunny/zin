const base = @import("base");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");

const Player = @import("Player.zig");

pub const author = "oilsoundsfunny";
pub const name = "selfplay";

pub const io = struct {
	var book: std.fs.File = undefined;
	var data: std.fs.File = undefined;

	var reader_buf align(64) = std.mem.zeroes([65536]u8);
	var writer_buf align(64) = std.mem.zeroes([65536]u8);

	pub var book_reader: std.fs.File.Reader = undefined;
	pub var data_writer: std.fs.File.Writer = undefined;

	pub var reader_mtx: std.Thread.Mutex = .{};
	pub var writer_mtx: std.Thread.Mutex = .{};

	fn deinit() void {
		book.close();
		data.close();
	}

	fn init(book_path: []const u8, data_path: []const u8) !void {
		book = try std.fs.cwd().openFile(book_path, .{});
		data = try std.fs.cwd().createFile(data_path, .{});

		book_reader = book.reader(&reader_buf);
		data_writer = data.writer(&writer_buf);
	}
};

pub fn main() !void {
	try base.init();
	defer base.deinit();

	try engine.init();
	engine.uci.options.frc = true;
	defer engine.deinit();

	const args = try std.process.argsAlloc(base.heap.allocator);
	var i: usize = 1;

	var book_path: ?[]const u8 = null;
	var data_path: ?[]const u8 = null;
	var games: ?u64 = null;
	var nodes: ?u64 = null;
	var threads: ?usize = null;

	while (i < args.len) : (i += 1) {
		const arg = args[i];

		if (std.mem.eql(u8, arg, "--book")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (book_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			book_path = args[i];
		} else if (std.mem.eql(u8, arg, "--data")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (data_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			data_path = args[i];
		} else if (std.mem.eql(u8, arg, "--games")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (games) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			games = try std.fmt.parseUnsigned(u64, args[i], 10);
		} else if (std.mem.eql(u8, arg, "--nodes")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (nodes) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			nodes = try std.fmt.parseUnsigned(u64, args[i], 10);
		} else if (std.mem.eql(u8, arg, "--threads")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (threads) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			threads = try std.fmt.parseUnsigned(usize, args[i], 10);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	try io.init(book_path orelse std.process.fatal("missing arg '{s}'", .{"--book"}),
	  data_path orelse std.process.fatal("missing arg '{s}'", .{"--data"}));
	defer io.deinit();

	var tourney = try Player.Tourney.alloc(threads orelse 1,
	  games, nodes orelse std.process.fatal("missing arg '--nodes'", .{}));
	try tourney.start();
}
