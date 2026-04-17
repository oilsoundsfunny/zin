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

fn releaseTargets(bld: *std.Build) !std.ArrayList(std.Build.ResolvedTarget) {
    const triples: [2][]const u8 = .{
        "x86_64-linux-musl",
        "x86_64-windows-msvc",
    };
    const cpus: [9][]const u8 = .{
        // zig fmt: off
        "x86_64", "x86_64_v2", "x86_64_v3", "x86_64_v4",
        "znver1", "znver2", "znver3", "znver4", "znver5",
        // zig fmt: on
    };

    var list: std.ArrayList(std.Build.ResolvedTarget) = .empty;
    for (triples) |triple| {
        for (cpus) |cpu| {
            const query: std.Target.Query = try .parse(.{
                .arch_os_abi = triple,
                .cpu_features = cpu,
            });
            const resolved = bld.resolveTargetQuery(query);
            try list.append(bld.allocator, resolved);
        }
    }
    return list;
}

pub fn build(bld: *std.Build) !void {
    const root = bld.addModule("root", .{
        .root_source_file = bld.path("src/root.zig"),
    });

    const optimize = bld.standardOptimizeOption(.{});
    const target = bld.standardTargetOptions(.{});

    var release_targets = try releaseTargets(bld);
    defer release_targets.deinit(bld.allocator);

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
    const raw_network: std.Build.LazyPath = if (evalfile) |path|
        .{ .cwd_relative = path }
    else
        bld.dependency("networks", .{}).path("1024hl-16b-8ob-100426.nnue");

    // TODO: idk clean this (and the one above)
    const avx512f_network, const avx2_network, const scalar_network = blk: {
        const transformer = bld.addExecutable(.{
            .root_module = bld.createModule(.{
                .root_source_file = bld.path("tools/nn.zig"),
                .target = target,
            }),
            .name = "transformer",
        });

        const avx512f = inner: {
            const run = bld.addRunArtifact(transformer);
            run.addFileArg(raw_network);
            run.addArg("x86-64-v4");
            break :inner run.addOutputFileArg("avx512f.nnue");
        };

        const avx2 = inner: {
            const run = bld.addRunArtifact(transformer);
            run.addFileArg(raw_network);
            run.addArg("x86-64-v3");
            break :inner run.addOutputFileArg("avx2.nnue");
        };

        const scalar = inner: {
            const run = bld.addRunArtifact(transformer);
            run.addFileArg(raw_network);
            run.addArg("x86-64-v2");
            break :inner run.addOutputFileArg("scalar.nnue");
        };

        break :blk .{ avx512f, avx2, scalar };
    };

    for (Modules.values) |m| {
        const deps = Modules.dependencies.get(m);
        const module = modules.get(m);

        for (deps) |dep| {
            const dep_name = Modules.names.get(dep);
            const dep_module = modules.get(dep);
            module.addImport(dep_name, dep_module);
        }

        if (m == .nnue) {
            module.addAnonymousImport("avx512f.nnue", .{ .root_source_file = avx512f_network });
            module.addAnonymousImport("avx2.nnue", .{ .root_source_file = avx2_network });
            module.addAnonymousImport("scalar.nnue", .{ .root_source_file = scalar_network });
        }
    }

    const lto = bld.option(bool, "lto", "") orelse !has_debuginfo;
    const exe_name = bld.option([]const u8, "name", "") orelse @import("src/root.zig").name;
    const version = @import("src/root.zig").version;

    var version_buf: [128]u8 align(std.atomic.cache_line) = undefined;
    const version_string = bld.option([]const u8, "version-string", "") orelse
        try std.fmt.bufPrint(
            version_buf[0..],
            "{}.{}.{}",
            .{ version.major, version.minor, version.patch },
        );

    for (Steps.values) |s| {
        var options = module_defaults;
        options.root_source_file = bld.path(Steps.srcs.get(s));

        if (s == .releases) {
            for (release_targets.items) |release_target| {
                options.target = release_target;
                const module = bld.createModule(options);
                const deps = Steps.dependencies.get(s);
                for (deps) |dep| {
                    const dep_name = Modules.names.get(dep);
                    const dep_module = modules.get(dep);
                    module.addImport(dep_name, dep_module);
                }

                const is_linux = release_target.result.os.tag == .linux;
                const name = try std.mem.concat(bld.allocator, u8, &.{
                    exe_name, "-", version_string, "-", release_target.result.cpu.model.name,
                });
                const comp = add_exe: {
                    const exe = bld.addExecutable(.{
                        .root_module = module,
                        .name = name,
                        .version = version,
                        .use_lld = use_llvm,
                        .use_llvm = use_llvm,
                    });
                    exe.want_lto = if (is_linux) lto else false;
                    break :add_exe exe;
                };
                const sub_step = &bld.addInstallArtifact(comp, .{}).step;
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

            const comp = if (s == .install) add_exe: {
                const exe = bld.addExecutable(.{
                    .root_module = module,
                    .name = exe_name,
                    .version = version,
                    .use_lld = use_llvm,
                    .use_llvm = use_llvm,
                });
                exe.want_lto = lto;
                break :add_exe exe;
            } else bld.addTest(.{
                .root_module = module,
                .name = if (s == .perft) "perft" else "test",
                .use_lld = use_llvm,
                .use_llvm = use_llvm,
            });

            const sub_step = if (s == .install)
                &bld.addInstallArtifact(comp, .{}).step
            else
                &bld.addRunArtifact(comp).step;
            steps.get(s).dependOn(sub_step);
        }
    }
}
