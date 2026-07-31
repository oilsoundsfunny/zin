const std = @import("std");

pub const Target = struct {
    triple: []const u8,
    features: []const u8,
    link_mode: std.builtin.LinkMode,
    suffix: []const u8,

    pub fn name(self: Target, bld: *std.Build, exe: []const u8, version: []const u8) []const u8 {
        return bld.fmt("{s}-{s}-{s}", .{ exe, version, self.suffix });
    }

    pub fn resolve(self: Target, bld: *std.Build) !std.Build.ResolvedTarget {
        return bld.resolveTargetQuery(try .parse(.{
            .arch_os_abi = self.triple,
            .cpu_features = self.features,
        }));
    }
};

pub const targets: []const Target = &.{
    .{
        .triple = "aarch64-macos",
        .features = "apple_m1",
        .link_mode = .dynamic,
        .suffix = "macos-m1",
    },
    .{
        .triple = "aarch64-macos",
        .features = "apple_m2",
        .link_mode = .dynamic,
        .suffix = "macos-m2",
    },
    .{
        .triple = "aarch64-macos",
        .features = "apple_m3",
        .link_mode = .dynamic,
        .suffix = "macos-m3",
    },
    .{
        .triple = "aarch64-macos",
        .features = "apple_m4",
        .link_mode = .dynamic,
        .suffix = "macos-m4",
    },

    .{
        .triple = "x86_64-macos",
        .features = "x86_64",
        .link_mode = .dynamic,
        .suffix = "macos-x86_64",
    },
    .{
        .triple = "x86_64-macos",
        .features = "x86_64_v2",
        .link_mode = .dynamic,
        .suffix = "macos-x86_64_v2",
    },
    .{
        .triple = "x86_64-macos",
        .features = "x86_64_v3",
        .link_mode = .dynamic,
        .suffix = "macos-x86_64_v3",
    },
    .{
        .triple = "x86_64-macos",
        .features = "x86_64_v4",
        .link_mode = .dynamic,
        .suffix = "macos-x86_64_v4",
    },

    .{
        .triple = "aarch64-linux-musl",
        .features = "baseline",
        .link_mode = .static,
        .suffix = "linux-aarch64",
    },
    .{
        .triple = "aarch64-linux-musl",
        .features = "baseline+v8_4a",
        .link_mode = .static,
        .suffix = "linux-aarch64-v84a",
    },
    .{
        .triple = "aarch64-linux-musl",
        .features = "baseline+v8_6a",
        .link_mode = .static,
        .suffix = "linux-aarch64-v86a",
    },
    .{
        .triple = "aarch64-linux-musl",
        .features = "baseline+v9a",
        .link_mode = .static,
        .suffix = "linux-aarch64-v9a",
    },

    .{
        .triple = "aarch64-openbsd",
        .features = "baseline",
        .link_mode = .dynamic,
        .suffix = "openbsd-aarch64",
    },
    .{
        .triple = "aarch64-openbsd",
        .features = "baseline+v8_4a",
        .link_mode = .dynamic,
        .suffix = "openbsd-aarch64-v84a",
    },
    .{
        .triple = "aarch64-openbsd",
        .features = "baseline+v8_6a",
        .link_mode = .dynamic,
        .suffix = "openbsd-aarch64-v86a",
    },
    .{
        .triple = "aarch64-openbsd",
        .features = "baseline+v9a",
        .link_mode = .dynamic,
        .suffix = "openbsd-aarch64-v9a",
    },

    .{
        .triple = "aarch64-windows-gnu",
        .features = "baseline",
        .link_mode = .static,
        .suffix = "windows-aarch64",
    },
    .{
        .triple = "aarch64-windows-gnu",
        .features = "baseline+v8_4a",
        .link_mode = .static,
        .suffix = "windows-aarch64-v84a",
    },
    .{
        .triple = "aarch64-windows-gnu",
        .features = "baseline+v8_6a",
        .link_mode = .static,
        .suffix = "windows-aarch64-v86a",
    },
    .{
        .triple = "aarch64-windows-gnu",
        .features = "baseline+v9a",
        .link_mode = .static,
        .suffix = "windows-aarch64-v9a",
    },

    .{
        .triple = "x86_64-linux-musl",
        .features = "x86_64",
        .link_mode = .static,
        .suffix = "linux-x86_64",
    },
    .{
        .triple = "x86_64-linux-musl",
        .features = "x86_64_v2",
        .link_mode = .static,
        .suffix = "linux-x86_64_v2",
    },
    .{
        .triple = "x86_64-linux-musl",
        .features = "x86_64_v3",
        .link_mode = .static,
        .suffix = "linux-x86_64_v3",
    },
    .{
        .triple = "x86_64-linux-musl",
        .features = "x86_64_v4",
        .link_mode = .static,
        .suffix = "linux-x86_64_v4",
    },
    .{
        .triple = "x86_64-linux-musl",
        .features = "znver1",
        .link_mode = .static,
        .suffix = "linux-znver1",
    },
    .{
        .triple = "x86_64-linux-musl",
        .features = "znver2",
        .link_mode = .static,
        .suffix = "linux-znver2",
    },
    .{
        .triple = "x86_64-linux-musl",
        .features = "znver3",
        .link_mode = .static,
        .suffix = "linux-znver3",
    },
    .{
        .triple = "x86_64-linux-musl",
        .features = "znver4",
        .link_mode = .static,
        .suffix = "linux-znver4",
    },
    .{
        .triple = "x86_64-linux-musl",
        .features = "znver5",
        .link_mode = .static,
        .suffix = "linux-znver5",
    },

    .{
        .triple = "x86_64-openbsd",
        .features = "x86_64",
        .link_mode = .dynamic,
        .suffix = "openbsd-x86_64",
    },
    .{
        .triple = "x86_64-openbsd",
        .features = "x86_64_v2",
        .link_mode = .dynamic,
        .suffix = "openbsd-x86_64_v2",
    },
    .{
        .triple = "x86_64-openbsd",
        .features = "x86_64_v3",
        .link_mode = .dynamic,
        .suffix = "openbsd-x86_64_v3",
    },
    .{
        .triple = "x86_64-openbsd",
        .features = "x86_64_v4",
        .link_mode = .dynamic,
        .suffix = "openbsd-x86_64_v4",
    },
    .{
        .triple = "x86_64-openbsd",
        .features = "znver1",
        .link_mode = .dynamic,
        .suffix = "openbsd-znver1",
    },
    .{
        .triple = "x86_64-openbsd",
        .features = "znver2",
        .link_mode = .dynamic,
        .suffix = "openbsd-znver2",
    },
    .{
        .triple = "x86_64-openbsd",
        .features = "znver3",
        .link_mode = .dynamic,
        .suffix = "openbsd-znver3",
    },
    .{
        .triple = "x86_64-openbsd",
        .features = "znver4",
        .link_mode = .dynamic,
        .suffix = "openbsd-znver4",
    },
    .{
        .triple = "x86_64-openbsd",
        .features = "znver5",
        .link_mode = .dynamic,
        .suffix = "openbsd-znver5",
    },

    .{
        .triple = "x86_64-windows-gnu",
        .features = "x86_64",
        .link_mode = .static,
        .suffix = "windows-x86_64",
    },
    .{
        .triple = "x86_64-windows-gnu",
        .features = "x86_64_v2",
        .link_mode = .static,
        .suffix = "windows-x86_64_v2",
    },
    .{
        .triple = "x86_64-windows-gnu",
        .features = "x86_64_v3",
        .link_mode = .static,
        .suffix = "windows-x86_64_v3",
    },
    .{
        .triple = "x86_64-windows-gnu",
        .features = "x86_64_v4",
        .link_mode = .static,
        .suffix = "windows-x86_64_v4",
    },
    .{
        .triple = "x86_64-windows-gnu",
        .features = "znver1",
        .link_mode = .static,
        .suffix = "windows-znver1",
    },
    .{
        .triple = "x86_64-windows-gnu",
        .features = "znver2",
        .link_mode = .static,
        .suffix = "windows-znver2",
    },
    .{
        .triple = "x86_64-windows-gnu",
        .features = "znver3",
        .link_mode = .static,
        .suffix = "windows-znver3",
    },
    .{
        .triple = "x86_64-windows-gnu",
        .features = "znver4",
        .link_mode = .static,
        .suffix = "windows-znver4",
    },
    .{
        .triple = "x86_64-windows-gnu",
        .features = "znver5",
        .link_mode = .static,
        .suffix = "windows-znver5",
    },
};
