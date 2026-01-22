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

const tunables = blk: {
    const zon = @import("spsa.zig.zon");
    const fields = std.meta.fields(@TypeOf(zon));
    var tbl: [fields.len]Tunable = .{
        .{ .name = "base_lmr_noisy1", .value = 20 },
        .{ .name = "base_lmr_noisy0", .value = 326 },
        .{ .name = "base_lmr_quiet1", .value = 713 },
        .{ .name = "base_lmr_quiet0", .value = 748 },

        .{ .name = "see_ordering_pawn", .value = 287 },
        .{ .name = "see_ordering_knight", .value = 744 },
        .{ .name = "see_ordering_bishop", .value = 865 },
        .{ .name = "see_ordering_rook", .value = 1181 },
        .{ .name = "see_ordering_queen", .value = 2333 },

        .{ .name = "see_pruning_pawn", .value = 246 },
        .{ .name = "see_pruning_knight", .value = 674 },
        .{ .name = "see_pruning_bishop", .value = 868 },
        .{ .name = "see_pruning_rook", .value = 1292 },
        .{ .name = "see_pruning_queen", .value = 2152 },

        .{ .name = "base_time_mul", .value = 6 },
        .{ .name = "base_incr_mul", .value = 70 },

        .{ .name = "max_hist_bonus", .value = 1232 },
        .{ .name = "hist_bonus2", .value = 37 },
        .{ .name = "hist_bonus1", .value = 194 },
        .{ .name = "hist_bonus0", .value = -83 },

        .{ .name = "max_hist_malus", .value = 2069 },
        .{ .name = "hist_malus2", .value = 67 },
        .{ .name = "hist_malus1", .value = 235 },
        .{ .name = "hist_malus0", .value = 365 },

        .{ .name = "corr_pawn_w", .value = 812 },
        .{ .name = "corr_minor_w", .value = 636 },
        .{ .name = "corr_major_w", .value = 878 },
        .{ .name = "corr_nonpawn_w", .value = 1045 },

        .{ .name = "corr_pawn_update_w", .value = 2499 },
        .{ .name = "corr_minor_update_w", .value = 2107 },
        .{ .name = "corr_major_update_w", .value = 2523 },
        .{ .name = "corr_nonpawn_update_w", .value = 1931 },

        .{ .name = "asp_min_depth", .value = 7, .c_end = 0.25 },
        .{ .name = "asp_window", .value = 16 },
        .{ .name = "asp_window_mul", .value = 158 },

        .{ .name = "tt_depth_w", .value = 1072 },
        .{ .name = "tt_age_w", .value = 2714 },
        .{ .name = "tt_pv_w", .value = 120 },
        .{ .name = "tt_upperbound_w", .value = 124 },
        .{ .name = "tt_exact_w", .value = 263 },
        .{ .name = "tt_lowerbound_w", .value = 122 },
        .{ .name = "tt_move_w", .value = 342 },

        .{ .name = "iir_min_depth", .value = 3, .c_end = 0.25 },

        .{ .name = "rfp_min_margin", .value = 13 },
        .{ .name = "rfp_max_depth", .value = 7, .c_end = 0.25 },
        .{ .name = "rfp_depth2", .value = 1569 },
        .{ .name = "rfp_depth1", .value = 83220 },
        .{ .name = "rfp_depth0", .value = 9962 },
        .{ .name = "rfp_ntm_worsening", .value = 26 },
        .{ .name = "rfp_fail_firm", .value = 998 },

        .{ .name = "nmp_min_depth", .value = 2, .c_end = 0.25 },
        .{ .name = "nmp_eval_margin", .value = 35 },
        .{ .name = "nmp_base_reduction", .value = 846 },
        .{ .name = "nmp_depth_mul", .value = 90 },
        .{ .name = "nmp_eval_diff_divisor", .value = 378 },
        .{ .name = "nmp_max_eval_reduction", .value = 5 },
        .{ .name = "nmp_min_verif_depth", .value = 16, .c_end = 0.25 },

        .{ .name = "razoring_max_depth", .value = 7, .c_end = 0.25 },
        .{ .name = "razoring_depth_mul", .value = 439 },

        .{ .name = "fp_max_depth", .value = 8, .c_end = 0.25 },
        .{ .name = "fp_margin0", .value = 340 },
        .{ .name = "fp_margin1", .value = 136 },
        .{ .name = "fp_hist_divisor", .value = 374 },

        .{ .name = "lmp_improving2", .value = 865 },
        .{ .name = "lmp_improving1", .value = 27 },
        .{ .name = "lmp_improving0", .value = 3335 },

        .{ .name = "lmp_nonimproving2", .value = 360 },
        .{ .name = "lmp_nonimproving1", .value = -90 },
        .{ .name = "lmp_nonimproving0", .value = 2209 },

        .{ .name = "pvs_see_quiet_mul", .value = -78 },
        .{ .name = "pvs_see_noisy_mul", .value = -118 },
        .{ .name = "pvs_see_max_capthist", .value = 118 },
        .{ .name = "pvs_see_capthist_div", .value = 32 },

        .{ .name = "lmr_min_depth", .value = 3, .c_end = 0.25 },
        .{ .name = "lmr_non_improving", .value = 737 },
        .{ .name = "lmr_cutnode", .value = 1843 },
        .{ .name = "lmr_noisy_ttm", .value = 1236 },
        .{ .name = "lmr_gave_check", .value = 1511 },
        .{ .name = "lmr_is_checked", .value = 75 },
        .{ .name = "lmr_is_pv", .value = 788 },
        .{ .name = "lmr_was_pv", .value = 1375 },
        .{ .name = "lmr_was_pv_non_fail_low", .value = 1022 },

        .{ .name = "deeper_margin1", .value = -412 },
        .{ .name = "deeper_margin0", .value = 372 },
        .{ .name = "shallower_margin1", .value = 350 },
        .{ .name = "shallower_margin0", .value = 151 },

        .{ .name = "qs_fp_margin", .value = 51 },
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
    const min = tunable.getMin();
    const max = tunable.getMax();
    if (value != std.math.clamp(value, min, max)) {
        return error.UnknownCommand;
    }

    dst.* = value;
    if (std.mem.indexOf(u8, name, "base_lmr")) |_| {
        try lmr.init();
    }
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
