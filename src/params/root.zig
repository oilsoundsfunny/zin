const engine = @import("engine");
const std = @import("std");
const types = @import("types");

pub const lmr = @import("lmr.zig");

const TunableValue = if (!tuning) void else struct {
    tunable: *const Tunable,
    value: *Int,
};

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

const map = if (!tuning)
{} else blk: {
    const KV = struct { []const u8, TunableValue };
    var kvs: [tunables.len]KV = undefined;

    for (tunables[0..], 0..) |*tunable, i| {
        const name = tunable.name[0..];
        kvs[i] = .{ name, .{ .tunable = tunable, .value = &@field(values, name) } };
    }

    break :blk std.StaticStringMap(TunableValue).initComptime(kvs);
};

pub const Int = engine.evaluation.score.Int;
pub const Tunable = struct {
    name: [:0]const u8,
    value: Int,
    min: Int,
    max: Int,
    c_end: f32,
};

const tunables = blk: {
    const zon = @import("spsa.zig.zon");
    const Zon = @TypeOf(zon);

    const fields = std.meta.fields(Zon);
    var tbl: [fields.len]Tunable = .{
        .{ .name = "base_lmr_noisy1", .value = 20, .min = 4, .max = 4096, .c_end = 1.0 },
        .{ .name = "base_lmr_noisy0", .value = 326, .min = 4, .max = 4096, .c_end = 16.0 },
        .{ .name = "base_lmr_quiet1", .value = 713, .min = 4, .max = 4096, .c_end = 32.0 },
        .{ .name = "base_lmr_quiet0", .value = 748, .min = 4, .max = 4096, .c_end = 32.0 },

        .{ .name = "see_ordering_pawn", .value = 287, .min = 0, .max = 2340, .c_end = 16.0 },
        .{ .name = "see_ordering_knight", .value = 744, .min = 0, .max = 2340, .c_end = 32.0 },
        .{ .name = "see_ordering_bishop", .value = 865, .min = 0, .max = 2340, .c_end = 32.0 },
        .{ .name = "see_ordering_rook", .value = 1181, .min = 0, .max = 2340, .c_end = 64.0 },
        .{ .name = "see_ordering_queen", .value = 2333, .min = 0, .max = 2340, .c_end = 128.0 },

        .{ .name = "see_pruning_pawn", .value = 246, .min = 0, .max = 2340, .c_end = 16.0 },
        .{ .name = "see_pruning_knight", .value = 674, .min = 0, .max = 2340, .c_end = 32.0 },
        .{ .name = "see_pruning_bishop", .value = 868, .min = 0, .max = 2340, .c_end = 32.0 },
        .{ .name = "see_pruning_rook", .value = 1292, .min = 0, .max = 2340, .c_end = 64.0 },
        .{ .name = "see_pruning_queen", .value = 2152, .min = 0, .max = 2340, .c_end = 128.0 },

        .{ .name = "base_time_mul", .value = 6, .min = 3, .max = 13, .c_end = 1.0 },
        .{ .name = "base_incr_mul", .value = 70, .min = 4, .max = 80, .c_end = 8.0 },

        .{ .name = "max_hist_bonus", .value = 1232, .min = 768, .max = 3072, .c_end = 256.0 },
        .{ .name = "hist_bonus2", .value = 37, .min = 24, .max = 1536, .c_end = 64.0 },
        .{ .name = "hist_bonus1", .value = 194, .min = 24, .max = 384, .c_end = 32.0 },
        .{ .name = "hist_bonus0", .value = -83, .min = -768, .max = 768, .c_end = 64.0 },

        .{ .name = "max_hist_malus", .value = 2069, .min = 768, .max = 3072, .c_end = 256.0 },
        .{ .name = "hist_malus2", .value = 67, .min = 24, .max = 1536, .c_end = 64.0 },
        .{ .name = "hist_malus1", .value = 235, .min = 24, .max = 384, .c_end = 32.0 },
        .{ .name = "hist_malus0", .value = 365, .min = -768, .max = 768, .c_end = 64.0 },

        .{ .name = "corr_pawn_w", .value = 812, .min = 384, .max = 6144, .c_end = 64.0 },
        .{ .name = "corr_minor_w", .value = 636, .min = 384, .max = 6144, .c_end = 64.0 },
        .{ .name = "corr_major_w", .value = 878, .min = 384, .max = 6144, .c_end = 64.0 },
        .{ .name = "corr_nonpawn_w", .value = 1045, .min = 384, .max = 6144, .c_end = 64.0 },

        .{ .name = "corr_pawn_update_w", .value = 2499, .min = 384, .max = 6144, .c_end = 64.0 },
        .{ .name = "corr_minor_update_w", .value = 2107, .min = 384, .max = 6144, .c_end = 64.0 },
        .{ .name = "corr_major_update_w", .value = 2523, .min = 384, .max = 6144, .c_end = 64.0 },
        .{ .name = "corr_nonpawn_update_w", .value = 1931, .min = 384, .max = 6144, .c_end = 64.0 },

        .{ .name = "asp_min_depth", .value = 7, .min = 3, .max = 7, .c_end = 0.25 },
        .{ .name = "asp_window", .value = 16, .min = 5, .max = 25, .c_end = 2.0 },
        .{ .name = "asp_window_mul", .value = 158, .min = 2, .max = 512, .c_end = 16.0 },

        .{ .name = "tt_depth_w", .value = 1072, .min = 64, .max = 4096, .c_end = 256.0 },
        .{ .name = "tt_age_w", .value = 2714, .min = 64, .max = 4096, .c_end = 256.0 },
        .{ .name = "tt_pv_w", .value = 120, .min = 64, .max = 4096, .c_end = 256.0 },
        .{ .name = "tt_upperbound_w", .value = 124, .min = 64, .max = 4096, .c_end = 256.0 },
        .{ .name = "tt_exact_w", .value = 263, .min = 64, .max = 4096, .c_end = 256.0 },
        .{ .name = "tt_lowerbound_w", .value = 122, .min = 64, .max = 4096, .c_end = 256.0 },
        .{ .name = "tt_move_w", .value = 342, .min = 64, .max = 4096, .c_end = 256.0 },

        .{ .name = "iir_min_depth", .value = 3, .min = 1, .max = 6, .c_end = 0.25 },

        .{ .name = "rfp_min_margin", .value = 13, .min = 4, .max = 100, .c_end = 8.0 },
        .{ .name = "rfp_max_depth", .value = 7, .min = 3, .max = 14, .c_end = 0.25 },
        .{ .name = "rfp_depth2", .value = 1569, .min = 64, .max = 16384, .c_end = 512.0 },
        .{ .name = "rfp_depth1", .value = 83220, .min = 64, .max = 262144, .c_end = 2048.0 },
        .{ .name = "rfp_depth0", .value = 9962, .min = 64, .max = 16384, .c_end = 512.0 },
        .{ .name = "rfp_ntm_worsening", .value = 26, .min = 4, .max = 100, .c_end = 8.0 },
        .{ .name = "rfp_fail_firm", .value = 998, .min = 0, .max = 1024, .c_end = 16.0 },

        .{ .name = "nmp_min_depth", .value = 2, .min = 1, .max = 4, .c_end = 0.25 },
        .{ .name = "nmp_eval_margin", .value = 35, .min = 4, .max = 64, .c_end = 8.0 },
        .{ .name = "nmp_base_reduction", .value = 846, .min = 256, .max = 4096, .c_end = 128.0 },
        .{ .name = "nmp_depth_mul", .value = 90, .min = 32, .max = 512, .c_end = 16.0 },
        .{ .name = "nmp_eval_diff_divisor", .value = 378, .min = 128, .max = 512, .c_end = 64.0 },
        .{ .name = "nmp_max_eval_reduction", .value = 5, .min = 2, .max = 10, .c_end = 0.25 },
        .{ .name = "nmp_min_verif_depth", .value = 16, .min = 8, .max = 32, .c_end = 0.25 },

        .{ .name = "razoring_max_depth", .value = 7, .min = 3, .max = 14, .c_end = 0.25 },
        .{ .name = "razoring_depth_mul", .value = 439, .min = 128, .max = 2048, .c_end = 64.0 },

        .{ .name = "fp_max_depth", .value = 8, .min = 4, .max = 16, .c_end = 0.25 },
        .{ .name = "fp_margin0", .value = 340, .min = 128, .max = 512, .c_end = 32.0 },
        .{ .name = "fp_margin1", .value = 136, .min = 128, .max = 512, .c_end = 32.0 },
        .{ .name = "fp_hist_divisor", .value = 374, .min = 128, .max = 512, .c_end = 32.0 },

        .{ .name = "lmp_improving2", .value = 865, .min = 16, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmp_improving1", .value = 27, .min = -1024, .max = 1024, .c_end = 32.0 },
        .{ .name = "lmp_improving0", .value = 3335, .min = 16, .max = 16384, .c_end = 256.0 },

        .{ .name = "lmp_nonimproving2", .value = 360, .min = 16, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmp_nonimproving1", .value = -90, .min = -1024, .max = 1024, .c_end = 32.0 },
        .{ .name = "lmp_nonimproving0", .value = 2209, .min = 16, .max = 16384, .c_end = 256.0 },

        .{ .name = "pvs_see_quiet_mul", .value = -78, .min = -128, .max = 128, .c_end = 16.0 },
        .{ .name = "pvs_see_noisy_mul", .value = -118, .min = -128, .max = 128, .c_end = 16.0 },
        .{ .name = "pvs_see_max_capthist", .value = 118, .min = 16, .max = 256, .c_end = 16.0 },
        .{ .name = "pvs_see_capthist_div", .value = 32, .min = 16, .max = 64, .c_end = 8.0 },

        .{ .name = "quiet_hist_pruning_lim", .value = 3467, .min = 1024, .max = 8192, .c_end = 192.0 },
        .{ .name = "quiet_hist_pruning0", .value = 962, .min = -2048, .max = 1024, .c_end = 128.0 },
        .{ .name = "quiet_hist_pruning1", .value = -2606, .min = -8192, .max = 0, .c_end = 294.0 },

        .{ .name = "noisy_hist_pruning_lim", .value = 3560, .min = 1024, .max = 8192, .c_end = 192.0 },
        .{ .name = "noisy_hist_pruning0", .value = 869, .min = -2048, .max = 1024, .c_end = 128.0 },
        .{ .name = "noisy_hist_pruning1", .value = -2919, .min = -8192, .max = 0, .c_end = 294.0 },

        .{ .name = "lmr_min_depth", .value = 3, .min = 1, .max = 6, .c_end = 0.25 },
        .{ .name = "lmr_non_improving", .value = 737, .min = 0, .max = 4096, .c_end = 32.0 },
        .{ .name = "lmr_cutnode", .value = 1843, .min = 0, .max = 4096, .c_end = 32.0 },
        .{ .name = "lmr_noisy_ttm", .value = 1236, .min = 0, .max = 4096, .c_end = 32.0 },
        .{ .name = "lmr_gave_check", .value = 1511, .min = 0, .max = 4096, .c_end = 32.0 },
        .{ .name = "lmr_is_checked", .value = 75, .min = 0, .max = 4096, .c_end = 32.0 },
        .{ .name = "lmr_is_pv", .value = 788, .min = 0, .max = 4096, .c_end = 32.0 },
        .{ .name = "lmr_was_pv", .value = 1375, .min = 0, .max = 4096, .c_end = 32.0 },
        .{ .name = "lmr_was_pv_non_fail_low", .value = 1022, .min = 0, .max = 4096, .c_end = 32.0 },

        .{ .name = "deeper_margin1", .value = -412, .min = -1024, .max = 1024, .c_end = 16.0 },
        .{ .name = "deeper_margin0", .value = 372, .min = -1024, .max = 1024, .c_end = 16.0 },
        .{ .name = "shallower_margin1", .value = 350, .min = -1024, .max = 1024, .c_end = 16.0 },
        .{ .name = "shallower_margin0", .value = 151, .min = -1024, .max = 1024, .c_end = 16.0 },

        .{ .name = "qs_fp_margin", .value = 51, .min = 4, .max = 100, .c_end = 8.0 },
    };

    for (tbl[0..]) |*tunable| {
        const name = tunable.name;
        tunable.value = @field(zon, name);
    }

    break :blk tbl;
};

pub const tuning = true;

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
    const tv = map.get(name) orelse return error.UnknownCommand;
    const tunable = tv.tunable;
    const dst = tv.value;

    if (!std.mem.eql(u8, aux, "value")) {
        return error.UnknownCommand;
    }

    const value_token = tokens.next() orelse return error.UnknownCommand;
    if (tokens.peek()) |_| {
        return error.UnknownCommand;
    }

    const value = std.fmt.parseInt(Int, value_token, 10) catch return error.UnknownCommand;
    if (value != std.math.clamp(value, tunable.min, tunable.max)) {
        return error.UnknownCommand;
    }

    dst.* = value;
    if (std.mem.indexOf(u8, name, "base_lmr")) |_| {
        try lmr.init();
    }
}

pub fn printOptions(writer: *std.Io.Writer) !void {
    const fmt = "option name {s} type spin default {d} min {d} max {d}\n";
    for (tunables) |tunable| {
        try writer.print(fmt, .{ tunable.name, tunable.value, tunable.min, tunable.max });
    }
}

pub fn printValues(writer: *std.Io.Writer) !void {
    const fmt = "{s}, int, {d:.1}, {d:.1}, {d:.1}, {d:.3}, 0.002\n";
    for (tunables) |tunable| {
        const val: f32 = @floatFromInt(tunable.value);
        const min: f32 = @floatFromInt(tunable.min);
        const max: f32 = @floatFromInt(tunable.max);
        try writer.print(fmt, .{ tunable.name, val, min, max, tunable.c_end });
    }
}
