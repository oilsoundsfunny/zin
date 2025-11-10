const std = @import("std");

const Modules = enum {
	types,
	bitboard,
	engine,
	nnue,
	selfplay,

	const dependencies = std.EnumArray(Modules, []const Modules).init(.{
		.types = &.{},
		.bitboard = &.{.types},
		.engine = &.{.types, .bitboard, .nnue},
		.nnue = &.{.types, .bitboard, .engine},
		.selfplay = &.{.types, .bitboard, .engine},
	});

	const names = std.EnumArray(Modules, []const u8).init(.{
		.types = "types",
		.bitboard = "bitboard",
		.engine = "engine",
		.nnue = "nnue",
		.selfplay = "selfplay",
	});

	const src_files = std.EnumArray(Modules, []const u8).init(.{
		.types = "src/types/root.zig",
		.bitboard = "src/bitboard/root.zig",
		.engine = "src/engine/root.zig",
		.nnue = "src/nnue/root.zig",
		.selfplay = "src/selfplay/root.zig",
	});

	const test_files = std.EnumArray(Modules, []const u8).init(.{
		.types = "tests/types/root.zig",
		.bitboard = "tests/bitboard/root.zig",
		.engine = "tests/engine/root.zig",
		.nnue = "tests/nnue/root.zig",
		.selfplay = "tests/selfplay/root.zig",
	});

	const values = std.enums.values(Modules);

	var array = std.EnumArray(Modules, *std.Build.Module).initUndefined();
	var tests = std.EnumArray(Modules, *std.Build.Step.Compile).initUndefined();
};

pub fn build(bld: *std.Build) !void {
	const optimize = bld.standardOptimizeOption(.{});
	const ndebug = optimize != .Debug and optimize != .ReleaseSafe;
	const target = bld.standardTargetOptions(.{});

	const exe_name = bld.option([]const u8, "name", "") orelse @import("src/root.zig").name;
	const lto = bld.option(bool, "lto", "") orelse false;
	const net = bld.option([]const u8, "net", "") orelse "zin-nets/hl256.nn";
	const stack_check = bld.option(bool, "stack-check", "") orelse !ndebug;
	const strip = bld.option(bool, "strip", "Strip executable(s)") orelse ndebug;
	const unwind_tables = bld.option(std.builtin.UnwindTables, "unwind-tables", "")
	  orelse if (ndebug) std.builtin.UnwindTables.none else std.builtin.UnwindTables.@"async";
	const use_llvm = bld.option(bool, "use-llvm", "Use the LLVM code backend")
	  orelse (optimize != .Debug);

	const bounded_array = bld.dependency("bounded_array", .{});

	const perft = bld.step("perft", "Test movegen");
	const selfplay_step = bld.step("selfplay", "Build the selfplay manager");
	const test_step = bld.step("test", "Test modules");

	const perft_module = bld.createModule(.{
		.root_source_file = bld.path("tests/perft/root.zig"),
		.target = target,
		.optimize = optimize,
		.link_libc = false,
		.link_libcpp = false,
		.single_threaded = false,
		.strip = strip,
		.unwind_tables = unwind_tables,
		.stack_check = stack_check,
		.pic = true,
	});
	const perft_unit = bld.addTest(.{
		.root_module = perft_module,
		.name = "perft",
		.use_lld = use_llvm,
		.use_llvm = use_llvm,
	});
	perft.dependOn(&bld.addRunArtifact(perft_unit).step);

	const root = bld.createModule(.{
		.root_source_file = bld.path("src/root.zig"),
		.target = target,
		.optimize = optimize,
		.link_libc = false,
		.link_libcpp = false,
		.single_threaded = false,
		.strip = strip,
		.unwind_tables = unwind_tables,
		.stack_check = stack_check,
		.pic = true,
	});

	for (Modules.values) |m| {
		const name = Modules.names.get(m);
		const src = Modules.src_files.get(m);

		const module = bld.createModule(.{
			.root_source_file = bld.path(src),
			.imports = &.{
				.{.name = "bounded_array", .module = bounded_array.module("bounded_array")},
			},
			.target = target,
			.optimize = optimize,
			.link_libc = false,
			.link_libcpp = false,
			.single_threaded = false,
			.strip = strip,
			.unwind_tables = unwind_tables,
			.stack_check = stack_check,
			.pic = true,
		});

		Modules.array.set(m, module);
		switch (m) {
			.selfplay => {},
			else => root.addImport(name, module),
		}

		const test_src = Modules.test_files.get(m);
		const test_module = bld.createModule(.{
			.root_source_file = bld.path(test_src),
			.imports = &.{
				.{.name = "bounded_array", .module = bounded_array.module("bounded_array")},
				.{.name = name, .module = module},
			},
			.target = target,
			.optimize = optimize,
			.link_libc = false,
			.link_libcpp = false,
			.single_threaded = false,
			.strip = strip,
			.unwind_tables = unwind_tables,
			.stack_check = stack_check,
			.pic = true,
		});
		const test_unit = bld.addTest(.{
			.root_module = test_module,
			.name = name,
			.use_lld = use_llvm,
			.use_llvm = use_llvm,
		});

		Modules.tests.set(m, test_unit);
		test_step.dependOn(&bld.addRunArtifact(test_unit).step);
	}

	for (Modules.values) |m| {
		const deps = Modules.dependencies.get(m);
		const module = Modules.array.get(m);
		const test_module = Modules.tests.get(m).root_module;

		for (deps) |dep| {
			const dep_name = Modules.names.get(dep);
			const dep_module = Modules.array.get(dep);

			module.addImport(dep_name, dep_module);
			perft_module.addImport(dep_name, dep_module);
			test_module.addImport(dep_name, dep_module);
		}

		switch (m) {
			.nnue => module.addAnonymousImport("default.nn", .{
				.root_source_file = .{.cwd_relative = net},
			}),
			else => {},
		}
	}

	const selfplay_exe = bld.addExecutable(.{
		.root_module = Modules.array.get(.selfplay),
		.name = "selfplay",
		.use_lld = use_llvm,
		.use_llvm = use_llvm,
	});
	selfplay_step.dependOn(&bld.addInstallArtifact(selfplay_exe, .{}).step);

	const exe = bld.addExecutable(.{
		.root_module = root,
		.name = exe_name,
		.version = @import("src/root.zig").version,
		.use_lld = use_llvm,
		.use_llvm = use_llvm,
	});
	exe.want_lto = lto;
	bld.installArtifact(exe);
}
