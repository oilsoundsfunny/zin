const std = @import("std");

const Network = extern struct {
    l0w: [ib][ft][l1]i16 align(64),
    l0b: [l1]i16 align(64),

    l1w: [ob][l1 / 4][l2 * 4]i8 align(64),
    l1b: [ob][l2]i32 align(64),

    l2w: [ob][l2 * 2][l3]i32 align(64),
    l2b: [ob][l3]i32 align(64),

    l3w: [ob][l3]i32 align(64),
    l3b: [ob]i32 align(64),

    const Raw = extern struct {
        l0w: [ib][ft][l1]i16 align(64),
        l0b: [l1]i16 align(64),

        l1w: [l1][ob][l2]i8 align(64),
        l1b: [ob][l2]i32 align(64),

        l2w: [l2 * 2][ob][l3]i32 align(64),
        l2b: [ob][l3]i32 align(64),

        l3w: [l3][ob]i32 align(64),
        l3b: [ob]i32 align(64),
    };

    const ft = 768;
    const ib = 16;
    const ob = 8;

    const l1 = 768;
    const l2 = 16;
    const l3 = 32;
};

comptime {
    for (std.meta.fields(Network), std.meta.fields(Network.Raw)) |field, raw_field| {
        const name = field.name[0..];
        const raw_name = raw_field.name[0..];
        if (@offsetOf(Network, name) != @offsetOf(Network.Raw, raw_name) or
            @sizeOf(field.type) != @sizeOf(raw_field.type)) {
            @compileError("incompatible fields " ++ name ++ " and " ++ raw_name);
        }
    }
}

fn permute(buffer: []align(64) u8, order: []const u8) void {
    const blocks: []@Vector(16, u8) = @ptrCast(buffer);
    var i: usize = 0;
    var w: [8]@Vector(16, u8) = undefined;

    while (i < blocks.len) : (i += order.len) {
        std.debug.assert(order.len == 0 or order.len == 4 or order.len == 8);
        @memcpy(w[0..order.len], blocks[i..][0..order.len]);
        for (0..order.len) |k| {
            blocks[i + k] = w[order[k]];
        }
    }
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip();
    const input_arg = args.next() orelse std.process.fatal("expected arg", .{});
    const input_file = try std.fs.cwd().openFile(input_arg, .{});

    const input_bytes: []const u8 = try input_file.readToEndAllocOptions(
        allocator,
        128 * 1024 * 1024,
        null,
        .@"64",
        null,
    );
    const raw: *const Network.Raw = @alignCast(@ptrCast(input_bytes));
    defer allocator.free(input_bytes);

    if (input_bytes.len != @sizeOf(Network.Raw)) {
        std.process.fatal("mismatched size: {} != {}", .{ input_bytes.len, @sizeOf(Network.Raw) });
    }

    const output_bytes = try allocator.alignedAlloc(u8, .@"64", input_bytes.len);
    defer allocator.free(output_bytes);

    @memcpy(output_bytes, input_bytes);
    const network: *Network = @alignCast(@ptrCast(output_bytes));

    const cpu_arg = args.next() orelse std.process.fatal("expected arg", .{});
    const cpu: ?*const std.Target.Cpu.Model =
        std.Target.Cpu.Arch.x86_64.parseCpuModel(cpu_arg) catch null;

    const has_avx512f = if (cpu) |p| p.toCpu(.x86_64).has(.x86, .avx512f) else false;
    const has_avx2 = if (cpu) |p| p.toCpu(.x86_64).has(.x86, .avx2) else false;

    if (has_avx512f or has_avx2) {
        permute(
            @ptrCast(&network.l0w),
            if (has_avx512f) &.{ 0, 2, 4, 6, 1, 3, 5, 7 } else &.{ 0, 2, 1, 3 },
        );
        permute(
            @ptrCast(&network.l0b),
            if (has_avx512f) &.{ 0, 2, 4, 6, 1, 3, 5, 7 } else &.{ 0, 2, 1, 3 },
        );
    }

    for (0..Network.ob) |ob| {
        for (0..Network.l1) |l1| {
            for (0..Network.l2) |l2| {
                network.l1w[ob][l1 / 4][l2 * 4 + l1 % 4] = raw.l1w[l1][ob][l2];
            }
        }
    }

    for (0..Network.ob) |ob| {
        for (0..Network.l2) |l2| {
            for (0..Network.l3) |l3| {
                network.l2w[ob][l2][l3] = raw.l2w[l2][ob][l3];
            }
        }
    }

    for (0..Network.ob) |ob| {
        for (0..Network.l3) |l3| {
            network.l3w[ob][l3] = raw.l3w[l3][ob];
        }
    }

    const output_arg = args.next() orelse std.process.fatal("expected arg", .{});
    const output_file = try std.fs.cwd().createFile(output_arg, .{});
    defer output_file.close();

    try output_file.writeAll(output_bytes);
}
