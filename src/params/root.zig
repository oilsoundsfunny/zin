const engine = @import("engine");
const std = @import("std");
const types = @import("types");

pub const lmr = @import("lmr.zig");

const Values = blk: {
    var fields: [tunables.len]std.builtin.Type.StructField = undefined;
    for (tunables, 0..) |tunable, i| {
        fields[i] = .{
            .name = tunable.name,
            .type = Int,
            .default_value_ptr = &tunable.value,
            .is_comptime = !tuning,
            .alignment = @alignOf(Int),
        };
    }

    break :blk @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields[0..],
        .decls = &.{},
        .is_tuple = false,
    } });
};

pub const Int = engine.evaluation.score.Int;
pub const Tunable = struct {
    name: [:0]const u8,
    value: Int,
    min: ?Int = null,
    max: ?Int = null,
    c_end: ?f32 = null,

    fn range(self: Tunable) Int {
        const abs = if (self.value < 0) -self.value else self.value;
        return @divTrunc(abs, 2) + 10;
    }

    pub fn getMin(self: Tunable) Int {
        return self.min orelse blk: {
            const d = self.value * 2;
            const h = @divTrunc(self.value, 2);
            const r = self.range();
            break :blk if (self.value > 0) h - r else d - r;
        };
    }

    pub fn getMax(self: Tunable) Int {
        return self.max orelse blk: {
            const d = self.value * 2;
            const h = @divTrunc(self.value, 2);
            const r = self.range();
            break :blk if (self.value > 0) d + r else h + r;
        };
    }

    pub fn getCEnd(self: Tunable) f32 {
        return self.c_end orelse blk: {
            const abs: f32 = @floatFromInt(@abs(self.value));
            break :blk @max(abs / 10.0, 0.5);
        };
    }
};

pub const tuning = false;
pub const tunables = [_]Tunable{
    .{ .name = "see_pawn_value", .value = 256 },
    .{ .name = "see_knight_value", .value = 704 },
    .{ .name = "see_bishop_value", .value = 832 },
    .{ .name = "see_rook_value", .value = 1280 },
    .{ .name = "see_queen_value", .value = 2304 },

    .{ .name = "mvv_pawn_value", .value = 1792 },
    .{ .name = "mvv_knight_value", .value = 4928 },
    .{ .name = "mvv_bishop_value", .value = 5824 },
    .{ .name = "mvv_rook_value", .value = 8960 },
    .{ .name = "mvv_queen_value", .value = 16128 },

    .{ .name = "base_time_mul", .value = 5, .min = 2, .max = 13, .c_end = 1.0 },
    .{ .name = "base_incr_mul", .value = 50, .min = 25, .max = 100, .c_end = 5.0 },

    .{ .name = "max_hist_bonus", .value = 768, .min = 512, .max = 3072, .c_end = 256.0 },
    .{ .name = "hist_bonus2", .value = 0, .min = 0, .max = 1536, .c_end = 64.0 },
    .{ .name = "hist_bonus1", .value = 64, .min = 64, .max = 384, .c_end = 32.0 },
    .{ .name = "hist_bonus0", .value = 0, .min = -768, .max = 384, .c_end = 64.0 },

    .{ .name = "max_hist_malus", .value = 768, .min = 512, .max = 3072, .c_end = 256.0 },
    .{ .name = "hist_malus2", .value = 0, .min = 0, .max = 1536, .c_end = 64.0 },
    .{ .name = "hist_malus1", .value = 64, .min = 64, .max = 384, .c_end = 32.0 },
    .{ .name = "hist_malus0", .value = 0, .min = -768, .max = 384, .c_end = 64.0 },

    .{ .name = "corr_pawn_w", .value = 986 },
    .{ .name = "corr_minor_w", .value = 1006 },
    .{ .name = "corr_major_w", .value = 1149 },

    .{ .name = "corr_pawn_update_w", .value = 2379 },
    .{ .name = "corr_minor_update_w", .value = 2035 },
    .{ .name = "corr_major_update_w", .value = 1921 },

    .{ .name = "asp_min_depth", .value = 6, .min = 3, .max = 7, .c_end = 1.0 },
    .{ .name = "asp_window", .value = 10, .min = 5, .max = 20, .c_end = 2.0 },
    .{ .name = "asp_window_mul", .value = 58, .min = 1, .max = 512, .c_end = 24.0 },

    .{ .name = "iir_min_depth", .value = 4, .min = 2, .max = 9, .c_end = 1.0 },

    .{ .name = "rfp_max_depth", .value = 8, .min = 4, .max = 10, .c_end = 1.0 },
    .{ .name = "rfp_depth_mul", .value = 78, .min = 50, .max = 100, .c_end = 8.0 },
    .{ .name = "rfp_ntm_worsening", .value = 14, .min = 5, .max = 100, .c_end = 8.0 },

    .{ .name = "nmp_min_depth", .value = 3, .min = 2, .max = 5, .c_end = 1.0 },
    .{ .name = "nmp_eval_margin", .value = 0, .min = 0, .max = 100, .c_end = 10.0 },
    .{ .name = "nmp_base_reduction", .value = 768, .min = 512, .max = 2048, .c_end = 64.0 },
    .{ .name = "nmp_depth_mul", .value = 64, .min = 32, .max = 96, .c_end = 12.0 },
    .{ .name = "nmp_eval_diff_divisor", .value = 400, .min = 50, .max = 400, .c_end = 10.0 },
    .{ .name = "nmp_max_eval_reduction", .value = 3, .min = 2, .max = 5, .c_end = 1.0 },

    .{ .name = "razoring_max_depth", .value = 7, .min = 1, .max = 10, .c_end = 1.0 },
    .{ .name = "razoring_depth_mul", .value = 460, .min = 250, .max = 650, .c_end = 10.0 },

    .{ .name = "fp_max_depth", .value = 8, .min = 4, .max = 9, .c_end = 1.0 },
    .{ .name = "fp_margin0", .value = 146, .min = 60, .max = 360, .c_end = 12.0 },
    .{ .name = "fp_margin1", .value = 128, .min = 10, .max = 180, .c_end = 12.0 },
    .{ .name = "fp_hist_divisor", .value = 393, .min = 256, .max = 512, .c_end = 16.0 },

    .{ .name = "pvs_see_quiet_mul", .value = -67, .min = -120, .max = -30, .c_end = 6.0 },
    .{ .name = "pvs_see_noisy_mul", .value = -96, .min = -120, .max = -30, .c_end = 6.0 },
    .{ .name = "pvs_see_max_capthist", .value = 103, .min = 50, .max = 200, .c_end = 6.0 },
    .{ .name = "pvs_see_capthist_div", .value = 30, .min = 16, .max = 96, .c_end = 2.0 },

    .{ .name = "lmr_min_depth", .value = 3, .min = 2, .max = 5, .c_end = 1.0 },
    .{ .name = "lmr_non_improving", .value = 1024, .min = 0, .max = 2048, .c_end = 256.0 },
    .{ .name = "lmr_cutnode", .value = 1024, .min = 0, .max = 2048, .c_end = 256.0 },
    .{ .name = "lmr_noisy_ttm", .value = 1024, .min = 0, .max = 2048, .c_end = 256.0 },
    .{ .name = "lmr_gave_check", .value = 1024, .min = 0, .max = 2048, .c_end = 256.0 },
    .{ .name = "lmr_is_checked", .value = 1024, .min = 0, .max = 2048, .c_end = 256.0 },
    .{ .name = "lmr_is_pv", .value = 1024, .min = 0, .max = 2048, .c_end = 256.0 },
    .{ .name = "lmr_was_pv", .value = 1024, .min = 0, .max = 2048, .c_end = 256.0 },
    .{ .name = "lmr_was_pv_non_fail_low", .value = 1024, .min = 0, .max = 2048, .c_end = 256.0 },

    .{ .name = "deeper_margin0", .value = 0 },
    .{ .name = "deeper_margin1", .value = 0 },
    .{ .name = "shallower_margin", .value = 0 },

    .{ .name = "qs_fp_margin", .value = 64, .min = 0, .max = 250, .c_end = 16.0 },
};

pub var values: Values = .{};

pub fn deinit() void {}

pub fn init() !void {
    try lmr.init();
}

pub fn parseTunable(
    name: []const u8,
    aux: []const u8,
    tokens: *std.mem.TokenIterator(u8, .any),
) engine.uci.Error!void {
    var opt_tunable: ?*const Tunable = null;
    var opt_value: ?*Int = null;
    inline for (tunables[0..]) |*tunable| {
        if (std.mem.eql(u8, name, tunable.name)) {
            opt_tunable = tunable;
            opt_value = &@field(values, tunable.name);
        }
    }
    const tunable = opt_tunable orelse return error.UnknownCommand;

    if (!std.mem.eql(u8, aux, "value")) {
        return error.UnknownCommand;
    }

    const value_token = tokens.next() orelse return error.UnknownCommand;
    if (tokens.peek()) |_| {
        return error.UnknownCommand;
    }

    const value = std.fmt.parseInt(Int, value_token, 10) catch return error.UnknownCommand;
    if (value != std.math.clamp(value, tunable.getMin(), tunable.getMax())) {
        return error.UnknownCommand;
    }

    opt_value.?.* = value;
}

pub fn printOptions(writer: *std.Io.Writer) !void {
    for (tunables) |tunable| {
        try writer.print("option name {s} type spin default {d} min {d} max {d}\n", .{
            tunable.name,
            tunable.value,
            tunable.getMin(),
            tunable.getMax(),
        });
    }
}

pub fn printValues(writer: *std.Io.Writer) !void {
    for (tunables) |tunable| {
        try writer.print("{s}, int, {d:.1}, {d:.1}, {d:.1}, {d:.3}, 0.002\n", .{
            tunable.name,
            @as(f32, @floatFromInt(tunable.value)),
            @as(f32, @floatFromInt(tunable.getMin())),
            @as(f32, @floatFromInt(tunable.getMax())),
            tunable.getCEnd(),
        });
    }
}
