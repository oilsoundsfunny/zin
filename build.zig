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

    const test_srcs = std.EnumArray(Modules, []const u8).init(.{
        .bitboard = "tests/bitboard/root.zig",
        .engine = "tests/engine/root.zig",
        .nnue = "tests/nnue/root.zig",
        .params = "tests/params/root.zig",
        .selfplay = "tests/selfplay/root.zig",
        .types = "tests/types/root.zig",
    });

    const values = std.enums.values(Modules);

    fn create(
        self: Modules,
        bld: *std.Build,
        defaults: std.Build.Module.CreateOptions,
    ) *std.Build.Module {
        var options = defaults;
        options.root_source_file = bld.path(srcs.get(self));
        return bld.createModule(options);
    }
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
        .install = "src/root.zig",
        .releases = "src/root.zig",
        .perft = "tests/perft/root.zig",
        .tests = "tests/root.zig",
    });

    const values = std.enums.values(Steps);

    fn create(
        self: Steps,
        bld: *std.Build,
        defaults: std.Build.Module.CreateOptions,
        target: std.Build.ResolvedTarget,
        modules: *const std.EnumArray(Modules, *std.Build.Module),
        lto: std.zig.LtoMode,
        name: []const u8,
        version: Version,
    ) *std.Build.Step {
        var options = defaults;
        options.root_source_file = bld.path(srcs.get(self));
        options.target = target;
        switch (target.result.os.tag) {
            .openbsd => options.link_libc = true,
            .windows => options.stack_check = false,
            else => {},
        }

        const module = bld.createModule(options);
        for (dependencies.get(self)) |dependency| {
            const n = Modules.names.get(dependency);
            const m = modules.get(dependency);
            module.addImport(n, m);
        }

        return switch (self) {
            .install, .releases => blk: {
                module.addOptions("version", version.options);
                const exe = bld.addExecutable(.{
                    .root_module = module,
                    .name = name,
                    .version = version.raw,
                    .use_lld = target.result.os.tag != .macos,
                    .use_llvm = true,
                });
                exe.lto = switch (target.result.os.tag) {
                    .linux, .openbsd => lto,
                    else => .none,
                };
                break :blk &bld.addInstallArtifact(exe, .{}).step;
            },
            else => blk: {
                const tests = bld.addTest(.{
                    .root_module = module,
                    .name = name,
                    .use_lld = target.result.os.tag != .macos,
                    .use_llvm = true,
                });
                break :blk &bld.addRunArtifact(tests).step;
            },
        };
    }
};

const Version = struct {
    raw: std.SemanticVersion,
    string: []const u8,
    options: *std.Build.Step.Options,

    fn init(bld: *std.Build) !Version {
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
        return .{ .raw = v, .string = s, .options = o };
    }
};

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
    const optimize = bld.standardOptimizeOption(.{});
    const target = bld.standardTargetOptions(.{});
    const is_debug, const has_debuginfo = switch (optimize) {
        .Debug => .{ true, true },
        .ReleaseSafe => .{ false, true },
        else => .{ false, false },
    };

    const omit_frame_pointer =
        bld.option(bool, "omit-fp", "Omit frame pointer") orelse
        !has_debuginfo;
    const stack_check = bld.option(bool, "stack-check", "") orelse is_debug;
    const strip = bld.option(bool, "strip", "Strip executable(s)") orelse !has_debuginfo;
    const valgrind = bld.option(bool, "valgrind", "") orelse false;

    const unwind_tables: std.builtin.UnwindTables =
        bld.option(std.builtin.UnwindTables, "unwind-tables", "") orelse
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

    const steps: std.EnumArray(Steps, *std.Build.Step) = .init(.{
        .install = bld.getInstallStep(),
        .releases = bld.step("releases", ""),
        .perft = bld.step("perft", ""),
        .tests = bld.step("tests", ""),
    });
    var modules: std.EnumArray(Modules, *std.Build.Module) = .initUndefined();

    for (Modules.values) |m| {
        modules.set(m, m.create(bld, module_defaults));
    }

    const evalfile = bld.option([]const u8, "evalfile", "") orelse
        std.process.fatal("-Devalfile must be set", .{});
    const network: std.Build.LazyPath = .{ .cwd_relative = evalfile };

    for (Modules.values) |m| {
        const module = modules.get(m);
        for (Modules.dependencies.get(m)) |dependency| {
            module.addImport(Modules.names.get(dependency), modules.get(dependency));
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

    const version: Version = try .init(bld);
    const lto: std.zig.LtoMode =
        bld.option(std.zig.LtoMode, "lto", "Perform link-time optimizations") orelse
        if (!has_debuginfo) .thin else .none;
    const exe_name = bld.option([]const u8, "name", "") orelse @import("src/root.zig").name;

    for (Steps.values) |s| {
        const step = steps.get(s);
        switch (s) {
            // zig fmt: off
            .releases => {
                const release_targets = @import("tools/release.zig").targets;
                for (release_targets) |release_target| {
                    const resolved = try release_target.resolve(bld);
                    const bin_name = release_target.name(bld, exe_name, version.string);
                    step.dependOn(s.create(
                        bld, module_defaults, resolved, &modules, lto, bin_name, version,
                    ));
                }
            },
            else => {
                const bin_name = switch (s) {
                    .install => exe_name,
                    .perft => "perft",
                    .tests => "tests",
                    else => unreachable,
                };
                step.dependOn(s.create(
                    bld, module_defaults, target, &modules, lto, bin_name, version,
                ));
            },
            // zig fmt: on
        }
    }
}
