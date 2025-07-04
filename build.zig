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
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
	});

	const bitboard = bld.createModule(.{
		.root_source_file = bld.path("src/bitboard/root.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
	});

	const engine = bld.createModule(.{
		.root_source_file = bld.path("src/engine/root.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
		.single_threaded = false,
	});

	const params = bld.createModule(.{
		.root_source_file = bld.path("src/params/root.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
	});

	bitboard.addImport("misc", misc);

	engine.addImport("bitboard", bitboard);
	engine.addImport("misc", misc);
	engine.addImport("params", params);

	params.addImport("bitboard", bitboard);
	params.addImport("engine", engine);
	params.addImport("misc", misc);

	const test_step = bld.step("test", "Test modules");

	const bitboard_test = bld.addTest(.{
		.root_module = bitboard,
		.name = "bitboard",
	});

	const engine_test = bld.addTest(.{
		.root_module = engine,
		.name = "engine",
	});

	const misc_test = bld.addTest(.{
		.root_module = misc,
		.name = "misc",
	});

	const params_test = bld.addTest(.{
		.root_module = params,
		.name = "params",
	});

	test_step.dependOn(&bld.addRunArtifact(bitboard_test).step);
	test_step.dependOn(&bld.addRunArtifact(engine_test).step);
	test_step.dependOn(&bld.addRunArtifact(misc_test).step);
	test_step.dependOn(&bld.addRunArtifact(params_test).step);

	const root = bld.createModule(.{
		.root_source_file = bld.path("src/root.zig"),
		.target = target,
		.pic = true,
		.single_threaded = false,
	});
	root.addImport("bitboard", bitboard);
	root.addImport("engine", engine);
	root.addImport("misc", misc);
	root.addImport("params", params);

	const exe = bld.addExecutable(.{
		.root_module = root,
		.name = config_src.name,
		.version = config_src.version,
		.use_llvm = use_llvm orelse (optimize != .Debug),
		.use_lld = use_llvm orelse (optimize != .Debug),
	});
	bld.installArtifact(exe);
}
