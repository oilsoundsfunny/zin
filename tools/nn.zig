const std = @import("std");

const Args = struct {
    cpu: *const std.Target.Cpu.Model,
    inp: std.Io.File,
    out: std.Io.File,

    const Error = error{NotFound};

    fn init(args: *std.process.Args.Iterator, io: std.Io) !Args {
        const cpu_arg = args.next() orelse return error.NotFound;
        const inp_arg = args.next() orelse return error.NotFound;
        const out_arg = args.next() orelse return error.NotFound;

        return .{
            .cpu = try std.Target.Cpu.Arch.x86_64.parseCpuModel(cpu_arg),
            .inp = try std.Io.Dir.cwd().openFile(io, inp_arg, .{}),
            .out = try std.Io.Dir.cwd().createFile(io, out_arg, .{}),
        };
    }

    fn deinit(self: Args, io: std.Io) void {
        self.inp.close(io);
        self.out.close(io);
    }
};

pub const Network = extern struct {
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

    pub const input_buckets: [64]u8 = .{
        // zig fmt: off
         0,  1,  2,  3,  3,  2,  1,  0,
         4,  5,  6,  7,  7,  6,  5,  4,
         8,  9, 10, 11, 11, 10,  9,  8,
         8,  9, 10, 11, 11, 10,  9,  8,
        12, 12, 13, 13, 13, 13, 12, 12,
        12, 12, 13, 13, 13, 13, 12, 12,
        14, 14, 15, 15, 15, 15, 14, 14,
        14, 14, 15, 15, 15, 15, 14, 14,
        // zig fmt: on
    };

    pub const ft = 768;
    pub const ib = std.mem.max(u8, input_buckets[0..]) + 1;
    pub const ob = 8;

    pub const l1 = 1024;
    pub const l2 = 16;
    pub const l3 = 32;
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

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    _ = args.skip();
    defer args.deinit();

    const parsed: Args = try .init(&args, init.io);
    defer parsed.deinit(init.io);

    const has_avx512f = parsed.cpu.toCpu(.x86_64).has(.x86, .avx512f);
    const has_avx2 = parsed.cpu.toCpu(.x86_64).has(.x86, .avx2);

    const input_bytes: []align(64) u8 =
        try init.gpa.alignedAlloc(u8, .@"64", @sizeOf(Network.Raw));
    const raw: *const Network.Raw = @ptrCast(input_bytes);
    defer init.gpa.free(input_bytes);

    if (input_bytes.len != @sizeOf(Network.Raw)) {
        std.process.fatal("mismatched size: {} != {}", .{ input_bytes.len, @sizeOf(Network.Raw) });
    } else if (input_bytes.len != try parsed.inp.readPositionalAll(init.io, input_bytes, 0)) {
        std.process.fatal("expected size {}", .{input_bytes.len});
    }

    const output_bytes: []align(64) u8 =
        try init.gpa.alignedAlloc(u8, .@"64", @sizeOf(Network));
    const network: *Network = @ptrCast(output_bytes);
    defer init.gpa.free(output_bytes);

    if (output_bytes.len != @sizeOf(Network)) {
        std.process.fatal("mismatched size: {} != {}", .{ output_bytes.len, @sizeOf(Network) });
    }

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

    try parsed.out.writeStreamingAll(init.io, output_bytes);
}
