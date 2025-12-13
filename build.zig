const std = @import("std");

const Modules = enum {
	types,
	bitboard,
	engine,
	nnue,
	params,

	const dependencies = std.EnumArray(Modules, []const Modules).init(.{
		.types = &.{},
		.bitboard = &.{.types},
		.engine = &.{.bitboard, .nnue, .params, .types},
		.nnue = &.{.engine, .types},
		.params = &.{.engine, .types},
	});

	const names = std.EnumArray(Modules, []const u8).init(.{
		.types = "types",
		.bitboard = "bitboard",
		.engine = "engine",
		.nnue = "nnue",
		.params = "params",
	});

	const src_files = std.EnumArray(Modules, []const u8).init(.{
		.types = "src/types/root.zig",
		.bitboard = "src/bitboard/root.zig",
		.engine = "src/engine/root.zig",
		.nnue = "src/nnue/root.zig",
		.params = "src/params/root.zig",
	});

	const test_files = std.EnumArray(Modules, []const u8).init(.{
		.types = "tests/types/root.zig",
		.bitboard = "tests/bitboard/root.zig",
		.engine = "tests/engine/root.zig",
		.nnue = "tests/nnue/root.zig",
		.params = "tests/params/root.zig",
	});

	const values = std.enums.values(Modules);
};

const Steps = enum {
	install,
	perft,
	selfplay,
	tests,

	const dependencies = std.EnumArray(Steps, []const Modules).init(.{
		.install = &.{.bitboard, .engine, .params, .types},
		.perft = &.{.bitboard, .engine, .types},
		.selfplay = &.{.bitboard, .engine, .params, .types},
		.tests = &.{},
	});

	const src_files = std.EnumArray(Steps, []const u8).init(.{
		.install = "src/main.zig",
		.perft = "tests/perft/root.zig",
		.selfplay = "src/selfplay/root.zig",
		.tests = "tests/root.zig",
	});

	const values = std.enums.values(Steps);
};

pub fn build(bld: *std.Build) !void {
	_ = bld.addModule("root", .{
		.root_source_file = bld.path("src/root.zig"),
	});

	const optimize = bld.standardOptimizeOption(.{});
	const ndebug = optimize != .Debug and optimize != .ReleaseSafe;
	const target = bld.standardTargetOptions(.{});

	const stack_check = bld.option(bool, "stack-check", "") orelse !ndebug;
	const strip = bld.option(bool, "strip", "Strip executable(s)") orelse ndebug;
	const unwind_tables = bld.option(std.builtin.UnwindTables, "unwind-tables", "")
	  orelse if (ndebug) std.builtin.UnwindTables.none else std.builtin.UnwindTables.@"async";
	const use_llvm = bld.option(bool, "use-llvm", "Use the LLVM code backend")
	  orelse (optimize != .Debug);
	const valgrind = bld.option(bool, "valgrind", "") orelse false;

	const module_template: std.Build.Module.CreateOptions = .{
		.target = target,
		.optimize = optimize,
		.link_libc = false,
		.link_libcpp = false,
		.single_threaded = false,
		.strip = strip,
		.unwind_tables = unwind_tables,
		.stack_check = stack_check,
		.valgrind = valgrind,
		.pic = true,
	};

	const bounded_array = bld.dependency("bounded_array", .{});

	const steps = std.EnumArray(Steps, *std.Build.Step).init(.{
		.install = bld.getInstallStep(),
		.perft = bld.step("perft", ""),
		.selfplay = bld.step("selfplay", ""),
		.tests = bld.step("test", ""),
	});
	var modules = std.EnumArray(Modules, *std.Build.Module).initUndefined();
	var tests = std.EnumArray(Modules, *std.Build.Step.Compile).initUndefined();

	for (Modules.values) |m| {
		const name = Modules.names.get(m);
		const src = Modules.src_files.get(m);

		var options = module_template;
		options.root_source_file = bld.path(src);

		const module = bld.createModule(options);
		switch (m) {
			.engine => module.addImport("bounded_array", bounded_array.module("bounded_array")),
			else => {},
		}
		modules.set(m, module);

		const test_src = Modules.test_files.get(m);
		var test_options = module_template;
		test_options.root_source_file = bld.path(test_src);

		const test_unit = bld.addTest(.{
			.root_module = bld.createModule(test_options),
			.name = name,
			.use_lld = use_llvm,
			.use_llvm = use_llvm,
		});

		tests.set(m, test_unit);
		steps.get(.tests).dependOn(&bld.addRunArtifact(test_unit).step);
	}

	const evalfile = bld.option([]const u8, "evalfile", "");
	const network: std.Build.LazyPath = if (evalfile) |custom| .{.cwd_relative = custom}
	  else bld.dependency("networks", .{}).path("hl320.nn");

	for (Modules.values) |m| {
		const deps = Modules.dependencies.get(m);
		const module = modules.get(m);
		const test_module = tests.get(m).root_module;

		for (deps) |dep| {
			const dep_name = Modules.names.get(dep);
			const dep_module = modules.get(dep);

			module.addImport(dep_name, dep_module);
			test_module.addImport(dep_name, dep_module);
		}

		switch (m) {
			.nnue => module.addAnonymousImport("default.nn", .{.root_source_file = network}),
			else => {},
		}
	}

	const exe_name = bld.option([]const u8, "name", "") orelse @import("src/main.zig").name;
	const version = @import("src/main.zig").version;

	for (Steps.values) |s| {
		var options = module_template;
		options.root_source_file = bld.path(Steps.src_files.get(s));

		const module = bld.createModule(options);
		const deps = Steps.dependencies.get(s);
		for (deps) |dep| {
			const dep_name = Modules.names.get(dep);
			const dep_module = modules.get(dep);

			module.addImport(dep_name, dep_module);
		}
		if (s == .selfplay) {
			module.addImport("bounded_array", bounded_array.module("bounded_array"));
		}

		const comp = switch (s) {
			.install, .selfplay => bld.addExecutable(.{
				.root_module = module,
				.name = if (s == .install) exe_name else @import("src/selfplay/root.zig").name,
				.version = version,
				.use_lld = use_llvm,
				.use_llvm = use_llvm,
			}),
			else => bld.addTest(.{
				.root_module = module,
				.name = if (s == .perft) "perft" else "test",
				.use_lld = use_llvm,
				.use_llvm = use_llvm,
			}),
		};
		const sub_step = switch (s) {
			.install, .selfplay => &bld.addInstallArtifact(comp, .{}).step,
			else => &bld.addRunArtifact(comp).step,
		};

		steps.get(s).dependOn(sub_step);
	}
}
