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

    const Options = struct {
        omit_frame_pointer: bool,
        stack_check: bool,
        strip: bool,
        valgrind: bool,

        fn init(bld: *std.Build) Options {
            const optimize = bld.standardOptimizeOption(.{});
            const is_debug = optimize == .Debug;
            const has_debuginfo = is_debug or optimize == .ReleaseSafe;
            return .{
                .omit_frame_pointer = bld.option(bool, "omit-fp", "") orelse !has_debuginfo,
                .stack_check = bld.option(bool, "stack-check", "") orelse is_debug,
                .strip = bld.option(bool, "strip", "Strip executable(s)") orelse !has_debuginfo,
                .valgrind = bld.option(bool, "valgrind", "") orelse false,
            };
        }
    };
};

const Steps = enum {
    install,
    releases,
    perft,
    tests,

    const dependencies = std.EnumArray(Steps, []const Modules).init(.{
        .install = &.{ .bitboard, .engine, .params, .selfplay, .types },
        .releases = &.{ .bitboard, .engine, .params, .selfplay, .types },
        .perft = &.{ .bitboard, .engine, .types },
        .tests = &.{ .bitboard, .engine, .nnue, .params, .selfplay, .types },
    });

    const srcs = std.EnumArray(Steps, []const u8).init(.{
        .install = "src/main.zig",
        .releases = "src/main.zig",
        .perft = "tests/perft/root.zig",
        .tests = "tests/root.zig",
    });

    const values = std.enums.values(Steps);
};

fn createModule(
    bld: *std.Build,
    root_source_file: []const u8,
    defaults: std.Build.Module.CreateOptions,
) *std.Build.Module {
    var opts = defaults;
    opts.root_source_file = bld.path(root_source_file);
    return bld.createModule(opts);
}

fn shortHash(bld: *std.Build) ?[]const u8 {
    const argv: []const []const u8 = if (bld.build_root.path) |root|
        &.{ "git", "-C", root, "rev-parse", "--short=7", "HEAD" }
    else
        &.{ "git", "rev-parse", "--short=7", "HEAD" };
    var exit: u8 = undefined;
    const stdout = bld.runAllowFail(argv, &exit, .ignore) catch return null;
    const short_hash = std.mem.trim(u8, stdout, std.ascii.whitespace[0..]);
    return if (short_hash.len != 0) short_hash else null;
}

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
    const valgrind = bld.option(bool, "valgrind", "") orelse false;

    const Unwind = std.builtin.UnwindTables;
    const unwind_tables: Unwind = bld.option(Unwind, "unwind-tables", "") orelse
        if (has_debuginfo) .async else .none;

    const module_defaults: std.Build.Module.CreateOptions = .{
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
        .releases = bld.step("releases", ""),
        .perft = bld.step("perft", ""),
        .tests = bld.step("test", ""),
    });
    var modules = std.EnumArray(Modules, *std.Build.Module).initUndefined();

    for (Modules.values) |m| {
        const src = Modules.srcs.get(m);
        const module = createModule(bld, src, module_defaults);
        modules.set(m, module);

        const name = Modules.names.get(m);
        root.addImport(name, module);
    }

    const evalfile = bld.option([]const u8, "evalfile", "");
    const network: std.Build.LazyPath = if (evalfile) |path|
        .{ .cwd_relative = path }
    else
        bld.dependency("nets", .{}).path("1024hl-16b-8ob-100426.nnue");

    for (Modules.values) |m| {
        const deps = Modules.dependencies.get(m);
        const module = modules.get(m);

        for (deps) |dep| {
            const dep_name = Modules.names.get(dep);
            const dep_module = modules.get(dep);
            module.addImport(dep_name, dep_module);
        }

        switch (m) {
            .nnue => module.addAnonymousImport("embed.nnue", .{ .root_source_file = network }),
            .params => {
                const options = bld.addOptions();
                options.addOption(bool, "tuning", bld.option(bool, "tuning", "") orelse false);
                module.addOptions("options", options);
            },
            else => {},
        }
    }

    const lto: std.zig.LtoMode =
        bld.option(std.zig.LtoMode, "lto", "") orelse
        if (has_debuginfo) .none else .thin;
    const exe_name = bld.option([]const u8, "name", "") orelse @import("src/root.zig").name;

    const version, const version_string, const version_options = blk: {
        const v: std.SemanticVersion = .{
            .major = 0,
            .minor = 3,
            .patch = 0,
            .pre = "dev",
            .build = shortHash(bld),
        };

        const s = bld.option([]const u8, "version-string", "") orelse inner: {
            const buf = bld.allocator.alloc(u8, 256) catch @panic("OOM");
            var w: std.Io.Writer = .fixed(buf);
            try v.format(&w);
            break :inner w.buffered();
        };

        const o = bld.addOptions();
        o.addOption(@TypeOf(v), "resolved", v);
        o.addOption(@TypeOf(s), "string", s);

        break :blk .{ v, s, o };
    };

    for (Steps.values) |s| {
        var options = module_defaults;
        options.root_source_file = bld.path(Steps.srcs.get(s));

        if (s == .releases) {
            const release_targets = @import("tools/release.zig").targets;
            for (release_targets) |release_target| {
                const resolved = try release_target.resolve(bld);
                options.target = resolved;

                const module = bld.createModule(options);
                module.addOptions("version", version_options);

                const deps = Steps.dependencies.get(.releases);
                for (deps) |dep| {
                    const dep_name = Modules.names.get(dep);
                    const dep_module = modules.get(dep);
                    module.addImport(dep_name, dep_module);
                }

                const exe = bld.addExecutable(.{
                    .root_module = module,
                    .name = release_target.name(bld, exe_name, version_string),
                    .version = version,
                    .use_lld = resolved.result.os.tag != .macos,
                    .use_llvm = true,
                });
                exe.lto = if (resolved.result.os.tag == .linux) lto else .none;

                const sub_step = &bld.addInstallArtifact(exe, .{}).step;
                steps.get(s).dependOn(sub_step);
            }
        } else {
            const module = bld.createModule(options);
            const deps = Steps.dependencies.get(s);
            for (deps) |dep| {
                const dep_name = Modules.names.get(dep);
                const dep_module = modules.get(dep);
                module.addImport(dep_name, dep_module);
            }

            const artifact = if (s == .install) add_exe: {
                module.addOptions("version", version_options);
                const exe = bld.addExecutable(.{
                    .root_module = module,
                    .name = exe_name,
                    .version = version,
                    .use_lld = target.result.os.tag != .macos,
                    .use_llvm = true,
                });
                exe.lto = if (target.result.os.tag == .linux) lto else .none;
                break :add_exe exe;
            } else bld.addTest(.{
                .root_module = module,
                .name = if (s == .perft) "perft" else "test",
                .use_lld = true,
                .use_llvm = true,
            });

            const sub_step = if (s == .install)
                &bld.addInstallArtifact(artifact, .{}).step
            else
                &bld.addRunArtifact(artifact).step;
            steps.get(s).dependOn(sub_step);
        }
    }
}
