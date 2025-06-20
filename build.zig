const std = @import("std");

const config_src = @import("config.zig");

pub fn build(bld: *std.Build) !void {
	const optimize = bld.standardOptimizeOption(.{});
	const ndebug = optimize == .ReleaseFast or optimize == .ReleaseSmall;
	const target = bld.graph.host;

	const config = bld.createModule(.{
		.root_source_file = bld.path("config.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
		.strip = ndebug,
		.unwind_tables = if (ndebug) .none else .sync,
		.stack_check = !ndebug,
		.sanitize_c = if (ndebug) .off else .full,
		.valgrind = !ndebug,
		.red_zone = !ndebug,
		.omit_frame_pointer = ndebug,
		.error_tracing = !ndebug,
	});

	const misc = bld.createModule(.{
		.root_source_file = bld.path("src/misc/root.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
		.strip = ndebug,
		.unwind_tables = if (ndebug) .none else .sync,
		.stack_check = !ndebug,
		.sanitize_c = if (ndebug) .off else .full,
		.valgrind = !ndebug,
		.red_zone = !ndebug,
		.omit_frame_pointer = ndebug,
		.error_tracing = !ndebug,
	});

	const bitboard = bld.createModule(.{
		.root_source_file = bld.path("src/bitboard/root.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
		.strip = ndebug,
		.unwind_tables = if (ndebug) .none else .sync,
		.stack_check = !ndebug,
		.sanitize_c = if (ndebug) .off else .full,
		.valgrind = !ndebug,
		.red_zone = !ndebug,
		.omit_frame_pointer = ndebug,
		.error_tracing = !ndebug,
	});
	bitboard.addImport("misc", misc);

	const engine = bld.createModule(.{
		.root_source_file = bld.path("src/engine/root.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
		.single_threaded = false,
		.strip = ndebug,
		.unwind_tables = if (ndebug) .none else .sync,
		.stack_check = !ndebug,
		.sanitize_c = if (ndebug) .off else .full,
		.valgrind = !ndebug,
		.red_zone = !ndebug,
		.omit_frame_pointer = ndebug,
		.error_tracing = !ndebug,
	});
	engine.addImport("bitboard", bitboard);
	engine.addImport("config", config);
	engine.addImport("misc", misc);

	const root = bld.createModule(.{
		.root_source_file = bld.path("src/root.zig"),
		.target = target,
		.optimize = optimize,
		.pic = true,
		.link_libc = false,
		.link_libcpp = false,
		.single_threaded = false,
		.strip = ndebug,
		.unwind_tables = if (ndebug) .none else .sync,
		.stack_check = !ndebug,
		.sanitize_c = if (ndebug) .off else .full,
		.valgrind = !ndebug,
		.red_zone = !ndebug,
		.omit_frame_pointer = ndebug,
		.error_tracing = !ndebug,
	});
	root.addImport("bitboard", bitboard);
	root.addImport("config", config);
	root.addImport("engine", engine);
	root.addImport("misc", misc);

	const test_step = bld.step("test", "Test modules");
	const bitboard_test = bld.addTest(.{
		.root_module = bitboard,
		.name = "bitboard",
		.use_llvm = optimize != .Debug,
		.use_lld = optimize != .Debug,
	});
	const engine_test = bld.addTest(.{
		.root_module = engine,
		.name = "engine",
		.use_llvm = optimize != .Debug,
		.use_lld = optimize != .Debug,
	});
	const misc_test = bld.addTest(.{
		.root_module = misc,
		.name = "misc",
		.use_llvm = optimize != .Debug,
		.use_lld = optimize != .Debug,
	});

	bitboard_test.want_lto = ndebug;
	engine_test.want_lto = ndebug;
	misc_test.want_lto = ndebug;

	test_step.dependOn(&bld.addRunArtifact(bitboard_test).step);
	test_step.dependOn(&bld.addRunArtifact(engine_test).step);
	test_step.dependOn(&bld.addRunArtifact(misc_test).step);

	const exe = bld.addExecutable(.{
		.root_module = root,
		.name = config_src.name,
		.version = config_src.version,
		.linkage = .static,
		.use_llvm = optimize != .Debug,
		.use_lld = optimize != .Debug,
	});
	exe.want_lto = ndebug;
	bld.installArtifact(exe);
}
