const config = @import("config");
const misc = @import("misc");
const std = @import("std");

pub fn printEngine() !void {
	const stdout = std.io.getStdOut();
	try stdout.writer().print("{s} {d}.{d}.{d} by {s}\n", .{
	  config.name, config.version.major, config.version.minor, config.version.patch, config.author,
	});
}

pub fn parseInput() !void {
	const stdin = std.io.getStdIn();
	var buffer = std.mem.zeroes([16384]u8);

	while (true) {
		const read = try stdin.reader().readUntilDelimterOrEof(buffer[0 ..], '\n');
		_ = read[0 ..];
	}
}
