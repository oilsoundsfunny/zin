const std = @import("std");

const config_src = @import("src/config.zig");

pub fn build(bld: *std.Build) !void {
	const target = bld.graph.host;

	const optimize = bld.option(std.builtin.OptimizeMode, "optimize-mode", "")
		orelse bld.standardOptimizeOption(.{});
	const use_llvm = bld.option(bool, "use-llvm", "");

	const misc = bld.createModule(.{
		.root_source_file = bld.path("src/misc/root.zig"),
		.target = target,
		.pic = true,
	});

	const bitboard = bld.createModule(.{
		.root_source_file = bld.path("src/bitboard/root.zig"),
		.target = target,
		.pic = true,
	});
	bitboard.addImport("misc", misc);

	const root = bld.createModule(.{
		.root_source_file = bld.path("src/root.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
	});
	root.addImport("bitboard", bitboard);
	root.addImport("misc", misc);

	const exe = bld.addExecutable(.{
		.root_module = root,
		.name = config_src.name,
		.version = config_src.version,
		.use_llvm = use_llvm orelse (optimize != .Debug),
		.use_lld = use_llvm orelse (optimize != .Debug),
	});
	bld.installArtifact(exe);
}
