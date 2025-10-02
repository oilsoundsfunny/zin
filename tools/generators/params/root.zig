const base = @import("base");
const std = @import("std");

const lmr = @import("lmr.zig");
const psqt = @import("psqt.zig");
const ptsc = @import("ptsc.zig");

pub const Pair = extern struct {
	mg:	base.defs.score.Int,
	eg:	base.defs.score.Int,
};

fn dump(slice: anytype, path: []const u8) !void {
	const file = try std.fs.cwd().createFile(path, .{});
	defer file.close();

	var buffer = std.mem.zeroes([1 << 12]u8);
	var writer = file.writer(&buffer);

	try writer.interface.writeAll(std.mem.sliceAsBytes(slice));
	try writer.interface.flush();
}

pub fn main() !void {
	try base.init();
	defer base.deinit();

	var lmr_path: ?[]const u8 = null;
	var psqt_path: ?[]const u8 = null;
	var ptsc_path: ?[]const u8 = null;

	const args = try std.process.argsAlloc(base.heap.allocator);
	var i: usize = 1;

	while (i < args.len) : (i += 1) {
		const arg = args[i];

		if (std.mem.eql(u8, arg, "--lmr-path")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (lmr_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			lmr_path = args[i];
		} else if (std.mem.eql(u8, arg, "--psqt-path")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (psqt_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			psqt_path = args[i];
		} else if (std.mem.eql(u8, arg, "--ptsc-path")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (ptsc_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			ptsc_path = args[i];
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	lmr.init();
	try dump(lmr.tbl[0 ..], lmr_path orelse std.process.fatal("missing arg '--lmr-path'", .{}));

	psqt.init();
	try dump(psqt.tbl.values[0 ..],
	  psqt_path orelse std.process.fatal("missing arg '--psqt-path'", .{}));

	ptsc.init();
	try dump(ptsc.tbl.values[0 ..],
	  ptsc_path orelse std.process.fatal("missing arg '--ptsc-path'", .{}));
}
