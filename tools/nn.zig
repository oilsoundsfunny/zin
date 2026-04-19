const std = @import("std");

const Network = extern struct {
    l0w: [ib][ft][l1]i16,
    l0b: [l1]i16,

    l1w: [ob][l1 / 4][l2 * 4]i8,
    l1b: [ob][l2]i32,

    l2w: [ob][l2 * 2][l3]i32,
    l2b: [ob][l3]i32,

    l3w: [ob][l3]i32,
    l3b: [ob]i32 align(64),

    const Raw = extern struct {
        l0w: [ib][ft][l1]i16,
        l0b: [l1]i16,

        l1w: [l1][ob][l2]i8,
        l1b: [ob][l2]i32,

        l2w: [l2 * 2][ob][l3]i32,
        l2b: [ob][l3]i32,

        l3w: [l3][ob]i32,
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
            @sizeOf(field.type) != @sizeOf(raw_field.type))
        {
            @compileError("incompatible fields " ++ name ++ " and " ++ raw_name);
        }
    }
}

fn permute(ptr: anytype, order: []const usize) void {
    const block_n = @sizeOf(@TypeOf(ptr.*)) / 16;
    const blocks: *[block_n]@Vector(8, i16) = @ptrCast(ptr);
    var t: [8]@Vector(8, i16) = @splat(@splat(0));
    var i: usize = 0;
    while (i < blocks.len) : (i += order.len) {
        @memcpy(t[0..order.len], blocks[i..][0..order.len]);
        for (0..order.len) |k| {
            blocks[i + k] = t[order[k]];
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

    const input_bytes: []align(64) const u8 =
        try input_file.readToEndAllocOptions(allocator, 64 * 1024 * 1024, null, .@"64", null);
    const raw: *const Network.Raw = @ptrCast(input_bytes);
    defer allocator.free(input_bytes);

    if (input_bytes.len != @sizeOf(Network.Raw)) {
        std.process.fatal("mismatched size: {} != {}", .{ input_bytes.len, @sizeOf(Network.Raw) });
    }

    const output_bytes = try allocator.alignedAlloc(u8, .@"64", input_bytes.len);
    const network: *Network = @ptrCast(output_bytes);
    defer allocator.free(output_bytes);

    if (output_bytes.len != @sizeOf(Network)) {
        std.process.fatal("mismatched size: {} != {}", .{ output_bytes.len, @sizeOf(Network) });
    }

    const cpu_arg = args.next() orelse std.process.fatal("expected arg", .{});
    const cpu = try std.Target.Cpu.Arch.x86_64.parseCpuModel(cpu_arg);

    const has_avx512f = cpu.toCpu(.x86_64).has(.x86, .avx512f);
    const has_avx2 = cpu.toCpu(.x86_64).has(.x86, .avx2);

    @memcpy(&network.l0w, &raw.l0w);
    @memcpy(&network.l0b, &raw.l0b);

    if (has_avx512f or has_avx2) {
        const order: []const usize = if (has_avx512f)
            &.{ 0, 2, 4, 6, 1, 3, 5, 7 }
        else
            &.{ 0, 2, 1, 3 };
        permute(&network.l0w, order);
        permute(&network.l0b, order);
    }

    for (0..Network.ob) |ob| {
        for (0..Network.l1) |l1| {
            for (0..Network.l2) |l2| {
                network.l1w[ob][l1 / 4][l2 * 4 + l1 % 4] = raw.l1w[l1][ob][l2];
            }
        }
    }

    for (0..Network.ob) |ob| {
        for (0..Network.l2 * 2) |l2| {
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

    @memcpy(&network.l1b, &raw.l1b);
    @memcpy(&network.l2b, &raw.l2b);
    @memcpy(&network.l3b, &raw.l3b);

    const output_arg = args.next() orelse std.process.fatal("expected arg", .{});
    const output_file = try std.fs.cwd().createFile(output_arg, .{});
    defer output_file.close();

    try output_file.writeAll(output_bytes);
}
