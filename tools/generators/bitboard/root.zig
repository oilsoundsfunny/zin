const base = @import("base");
const std = @import("std");

const jumping = @import("jumping.zig");
const sliding = @import("sliding.zig");

fn dump(slice: anytype, path: []const u8) !void {
	const cwd = std.fs.cwd();
	const file = try cwd.createFile(path, .{});
	defer file.close();

	var buffer = std.mem.zeroes([1 << 20]u8);
	var writer = file.writer(buffer[0 ..]);

	try writer.interface.writeAll(std.mem.asBytes(slice));
	try writer.interface.flush();
}

pub fn main() !void {
	try base.init();
	defer base.deinit();

	const args = try std.process.argsAlloc(base.heap.allocator);
	var i: usize = 1;

	var b_magic_path: ?[]const u8 = null;
	var b_nmask_path: ?[]const u8 = null;
	var b_offset_path: ?[]const u8 = null;

	var r_magic_path: ?[]const u8 = null;
	var r_nmask_path: ?[]const u8 = null;
	var r_offset_path: ?[]const u8 = null;

	var sliding_path: ?[]const u8 = null;
	var n_path: ?[]const u8 = null;
	var k_path: ?[]const u8 = null;

	while (i < args.len) : (i += 1) {
		const arg = args[i];

		if (std.mem.eql(u8, arg, "--sliding-atk")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			sliding_path = if (sliding_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			} else args[i];
		} else if (std.mem.eql(u8, arg, "--n-atk")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			n_path = if (n_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			} else args[i];
		} else if (std.mem.eql(u8, arg, "--k-atk")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			k_path = if (k_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			} else args[i];
		} else if (std.mem.eql(u8, arg, "--b-magic")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			b_magic_path = if (b_magic_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			} else args[i];
		} else if (std.mem.eql(u8, arg, "--b-nmask")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			b_nmask_path = if (b_nmask_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			} else args[i];
		} else if (std.mem.eql(u8, arg, "--b-offset")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			b_offset_path = if (b_offset_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			} else args[i];
		} else if (std.mem.eql(u8, arg, "--r-magic")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			r_magic_path = if (r_magic_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			} else args[i];
		} else if (std.mem.eql(u8, arg, "--r-nmask")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			r_nmask_path = if (r_nmask_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			} else args[i];
		} else if (std.mem.eql(u8, arg, "--r-offset")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (r_offset_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			r_offset_path = args[i];
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	jumping.init();
	sliding.init();

	try dump(jumping.n_atk.values[0 ..],
	  n_path orelse std.process.fatal("missing arg '--n-atk'", .{}));

	try dump(jumping.k_atk.values[0 ..],
	  k_path orelse std.process.fatal("missing arg '--k-atk'", .{}));

	try dump(sliding.atk[0 ..],
	  sliding_path orelse std.process.fatal("missing arg '--sliding-atk'", .{}));

	try dump(sliding.b_magic.values[0 ..],
	  b_magic_path orelse std.process.fatal("missing arg '--b-magic'", .{}));
	try dump(sliding.b_nmask.values[0 ..],
	  b_nmask_path orelse std.process.fatal("missing arg '--b-nmask'", .{}));
	try dump(sliding.b_offset.values[0 ..],
	  b_offset_path orelse std.process.fatal("missing arg '--b-offset'", .{}));

	try dump(sliding.r_magic.values[0 ..],
	  r_magic_path orelse std.process.fatal("missing arg '--r-magic'", .{}));
	try dump(sliding.r_nmask.values[0 ..],
	  r_nmask_path orelse std.process.fatal("missing arg '--r-nmask'", .{}));
	try dump(sliding.r_offset.values[0 ..],
	  r_offset_path orelse std.process.fatal("missing arg '--r-offset'", .{}));
}
