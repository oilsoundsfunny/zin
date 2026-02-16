const std = @import("std");

const Modules = enum {
    bitboard,
    engine,
    nnue,
    params,
    selfplay,
    types,

    const dependencies = std.EnumArray(Modules, []const Modules).init(.{
        .bitboard = &.{.types},
        .engine = &.{ .bitboard, .nnue, .params, .selfplay, .types },
        .nnue = &.{ .engine, .types },
        .params = &.{ .engine, .types },
        .selfplay = &.{ .bitboard, .engine, .params, .types },
        .types = &.{},
    });

    const names = std.EnumArray(Modules, []const u8).init(.{
        .bitboard = "bitboard",
        .engine = "engine",
        .nnue = "nnue",
        .params = "params",
        .selfplay = "selfplay",
        .types = "types",
    });

    const srcs = std.EnumArray(Modules, []const u8).init(.{
        .bitboard = "src/bitboard/root.zig",
        .engine = "src/engine/root.zig",
        .nnue = "src/nnue/root.zig",
        .params = "src/params/root.zig",
        .selfplay = "src/selfplay/root.zig",
        .types = "src/types/root.zig",
    });

    const test_files = std.EnumArray(Modules, []const u8).init(.{
        .bitboard = "tests/bitboard/root.zig",
        .engine = "tests/engine/root.zig",
        .nnue = "tests/nnue/root.zig",
        .params = "tests/params/root.zig",
        .selfplay = "tests/selfplay/root.zig",
        .types = "tests/types/root.zig",
    });

    const values = std.enums.values(Modules);
};

const Steps = enum {
    install,
    perft,
    tests,

    const dependencies = std.EnumArray(Steps, []const Modules).init(.{
        .install = &.{ .bitboard, .engine, .params, .selfplay, .types },
        .perft = &.{ .bitboard, .engine, .types },
        .tests = &.{ .bitboard, .engine, .nnue, .params, .selfplay, .types },
    });

    const srcs = std.EnumArray(Steps, []const u8).init(.{
        .install = "src/main.zig",
        .perft = "tests/perft/root.zig",
        .tests = "tests/root.zig",
    });

    const values = std.enums.values(Steps);
};

pub fn build(bld: *std.Build) !void {
    const root = bld.addModule("root", .{
        .root_source_file = bld.path("src/root.zig"),
    });

    const optimize = bld.standardOptimizeOption(.{});
    const target = bld.standardTargetOptions(.{});

    const is_debug = optimize == .Debug;
    const has_debuginfo = is_debug or optimize == .ReleaseSafe;

    const omit_frame_pointer = bld.option(bool, "omit-fp", "") orelse !has_debuginfo;
    const stack_check = bld.option(bool, "stack-check", "") orelse is_debug;
    const strip = bld.option(bool, "strip", "Strip executable(s)") orelse !has_debuginfo;
    const use_llvm = bld.option(bool, "use-llvm", "Use the LLVM code backend") orelse !is_debug;
    const valgrind = bld.option(bool, "valgrind", "") orelse false;

    const Unwind = std.builtin.UnwindTables;
    const unwind_tables: Unwind = bld.option(Unwind, "unwind-tables", "") orelse
        if (has_debuginfo) .async else .none;

    const module_opts: std.Build.Module.CreateOptions = .{
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
        .omit_frame_pointer = omit_frame_pointer,
    };

    const steps = std.EnumArray(Steps, *std.Build.Step).init(.{
        .install = bld.getInstallStep(),
        .perft = bld.step("perft", ""),
        .tests = bld.step("test", ""),
    });
    var modules = std.EnumArray(Modules, *std.Build.Module).initUndefined();

    for (Modules.values) |m| {
        const src = Modules.srcs.get(m);

        var options = module_opts;
        options.root_source_file = bld.path(src);

        const module = bld.createModule(options);
        modules.set(m, module);

        const name = Modules.names.get(m);
        root.addImport(name, module);
    }

    const evalfile = bld.option([]const u8, "evalfile", "");
    const network: std.Build.LazyPath = if (evalfile) |path|
        .{ .cwd_relative = path }
    else
        bld.dependency("networks", .{}).path("hl320.nn");

    for (Modules.values) |m| {
        const deps = Modules.dependencies.get(m);
        const module = modules.get(m);

        for (deps) |dep| {
            const dep_name = Modules.names.get(dep);
            const dep_module = modules.get(dep);

            module.addImport(dep_name, dep_module);
        }

        switch (m) {
            .nnue => module.addAnonymousImport("embed.nn", .{ .root_source_file = network }),
            else => {},
        }
    }

    const lto = bld.option(bool, "lto", "") orelse !has_debuginfo;
    const exe_name = bld.option([]const u8, "name", "") orelse @import("src/root.zig").name;
    const version = @import("src/root.zig").version;

    for (Steps.values) |s| {
        var options = module_opts;
        options.root_source_file = bld.path(Steps.srcs.get(s));

        const module = bld.createModule(options);
        const deps = Steps.dependencies.get(s);
        for (deps) |dep| {
            const dep_name = Modules.names.get(dep);
            const dep_module = modules.get(dep);

            module.addImport(dep_name, dep_module);
        }

        const comp = switch (s) {
            .install => add_exe: {
                const exe = bld.addExecutable(.{
                    .root_module = module,
                    .name = exe_name,
                    .version = version,
                    .use_lld = use_llvm,
                    .use_llvm = use_llvm,
                });
                exe.want_lto = lto;
                break :add_exe exe;
            },
            else => bld.addTest(.{
                .root_module = module,
                .name = if (s == .perft) "perft" else "test",
                .use_lld = use_llvm,
                .use_llvm = use_llvm,
            }),
        };

        const sub_step = switch (s) {
            .install => &bld.addInstallArtifact(comp, .{}).step,
            else => &bld.addRunArtifact(comp).step,
        };

        steps.get(s).dependOn(sub_step);
    }
}
