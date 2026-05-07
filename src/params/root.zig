const engine = @import("engine");
const options = @import("options");
const std = @import("std");
const types = @import("types");

pub const lmr = @import("lmr.zig");

const TunableValue = if (!tuning) void else struct {
    tunable: *const Tunable,
    value: *Int,
};

const Values = blk: {
    const Types: [tunables.len]type = @splat(Int);
    var names: [tunables.len][]const u8 = undefined;
    var attrs: [tunables.len]std.builtin.Type.StructField.Attributes = undefined;
    for (tunables[0..], names[0..], attrs[0..]) |*tunable, *name, *attr| {
        name.* = tunable.init.name[0..];
        attr.* = .{
            .@"comptime" = !tuning,
            .default_value_ptr = &tunable.value,
        };
    }
    break :blk @Struct(.auto, null, names[0..], Types[0..], attrs[0..]);
};

const map = if (!tuning) {} else blk: {
    const KV = struct { []const u8, TunableValue };
    var kvs: [tunables.len]KV = undefined;

    for (tunables[0..], 0..) |*tunable, i| {
        const name = tunable.init.name[0..];
        kvs[i] = .{ name, .{ .tunable = tunable, .value = &@field(values, name) } };
    }

    break :blk std.StaticStringMap(TunableValue).initComptime(kvs);
};

pub const Int = engine.evaluation.score.Int;
pub const Tunable = struct {
    init: Init,
    value: Int,

    const Init = struct {
        name: [:0]const u8,
        min: ?Int = null,
        max: ?Int = null,
        c_end: ?f32 = null,

        fn expand(self: Init, v: Int) Tunable {
            return .{
                .init = self,
                .value = v,
            };
        }
    };

    fn margin(self: Tunable) Int {
        const v = self.value;
        return @divTrunc(if (v < 0) -v else v, 2) + 10;
    }

    fn min(self: Tunable) Int {
        return self.init.min orelse if (self.value < 0) self.value - self.margin() else 0;
    }

    fn max(self: Tunable) Int {
        return self.init.max orelse if (self.value > 0) self.value + self.margin() else 0;
    }

    fn cEnd(self: Tunable) f32 {
        return self.init.c_end orelse blk: {
            const r: f32 = @floatFromInt(self.max() - self.min());
            break :blk r * 0.05;
        };
    }
};

const tunables = blk: {
    const zon = @import("spsa.zig.zon");
    const Zon = @TypeOf(zon);

    const fields = std.meta.fields(Zon);
    const inits: [fields.len]Tunable.Init = .{
        .{ .name = "tm_time_mult" },
        .{ .name = "tm_incr_mult" },

        .{ .name = "nodetm_mult" },
        .{ .name = "nodetm_bias" },

        .{ .name = "base_lmr_noisy_mult" },
        .{ .name = "base_lmr_noisy_bias" },

        .{ .name = "base_lmr_quiet_mult" },
        .{ .name = "base_lmr_quiet_bias" },

        .{ .name = "ordering_pawn", .min = 0, .max = 16384 },
        .{ .name = "ordering_knight", .min = 0, .max = 16384 },
        .{ .name = "ordering_bishop", .min = 0, .max = 16384 },
        .{ .name = "ordering_rook", .min = 0, .max = 16384 },
        .{ .name = "ordering_queen", .min = 0, .max = 16384 },

        .{ .name = "see_pawn", .min = 0, .max = 16384 },
        .{ .name = "see_knight", .min = 0, .max = 16384 },
        .{ .name = "see_bishop", .min = 0, .max = 16384 },
        .{ .name = "see_rook", .min = 0, .max = 16384 },
        .{ .name = "see_queen", .min = 0, .max = 16384 },

        .{ .name = "quiethist_max_bonus" },
        .{ .name = "quiethist_bonus_quad" },
        .{ .name = "quiethist_bonus_mult" },
        .{ .name = "quiethist_bonus_bias" },

        .{ .name = "quiethist_max_malus" },
        .{ .name = "quiethist_malus_quad" },
        .{ .name = "quiethist_malus_mult" },
        .{ .name = "quiethist_malus_bias" },

        .{ .name = "noisyhist_max_bonus" },
        .{ .name = "noisyhist_bonus_quad" },
        .{ .name = "noisyhist_bonus_mult" },
        .{ .name = "noisyhist_bonus_bias" },

        .{ .name = "noisyhist_max_malus" },
        .{ .name = "noisyhist_malus_quad" },
        .{ .name = "noisyhist_malus_mult" },
        .{ .name = "noisyhist_malus_bias" },

        .{ .name = "corr_pawn_w" },
        .{ .name = "corr_minor_w" },
        .{ .name = "corr_major_w" },
        .{ .name = "corr_nonpawn_stm_w" },
        .{ .name = "corr_nonpawn_ntm_w" },

        .{ .name = "corr_pawn_update_w" },
        .{ .name = "corr_minor_update_w" },
        .{ .name = "corr_major_update_w" },
        .{ .name = "corr_nonpawn_update_stm_w" },
        .{ .name = "corr_nonpawn_update_ntm_w" },

        .{ .name = "asp_window" },
        .{ .name = "asp_window_mult" },

        .{ .name = "tt_depth_w" },
        .{ .name = "tt_age_w" },
        .{ .name = "tt_pv_w" },
        .{ .name = "tt_upperbound_w" },
        .{ .name = "tt_exact_w" },
        .{ .name = "tt_lowerbound_w" },
        .{ .name = "tt_move_w" },

        .{ .name = "rfp_depth_quad" },
        .{ .name = "rfp_depth_mult" },
        .{ .name = "rfp_depth_bias" },
        .{ .name = "rfp_ntm_worsening" },
        .{ .name = "rfp_fail_firm", .min = 0, .max = 1024 },

        .{ .name = "nmp_eval_margin" },
        .{ .name = "nmp_base_r" },
        .{ .name = "nmp_depth_mult" },
        .{ .name = "nmp_improving_r" },
        .{ .name = "nmp_deval_mult" },
        .{ .name = "nmp_deval_max_r" },

        .{ .name = "razoring_mult" },

        .{ .name = "fp_margin_mult" },
        .{ .name = "fp_margin_bias" },
        .{ .name = "fp_hist_mult" },

        .{ .name = "bnfp_margin_mult" },
        .{ .name = "bnfp_margin_bias" },
        .{ .name = "bnfp_hist_mult" },

        .{ .name = "lmp_improving_quad" },
        .{ .name = "lmp_improving_mult" },
        .{ .name = "lmp_improving_bias" },

        .{ .name = "lmp_nonimproving_quad" },
        .{ .name = "lmp_nonimproving_mult" },
        .{ .name = "lmp_nonimproving_bias" },

        .{ .name = "pvs_see_quiet_mult" },
        .{ .name = "pvs_see_noisy_mult" },
        .{ .name = "pvs_see_max_capthist" },
        .{ .name = "pvs_see_capthist_mult" },

        .{ .name = "quiethist_pruning_lim" },
        .{ .name = "quiethist_pruning_mult" },
        .{ .name = "quiethist_pruning_bias" },

        .{ .name = "noisyhist_pruning_lim" },
        .{ .name = "noisyhist_pruning_mult" },
        .{ .name = "noisyhist_pruning_bias" },

        .{ .name = "se_beta_mult" },
        .{ .name = "se_beta_mult_pv" },
        .{ .name = "se_beta_mult_was_pv" },
        .{ .name = "se_depth_mult" },
        .{ .name = "se_depth_bias" },

        .{ .name = "dext_quiet" },
        .{ .name = "dext_noisy" },
        .{ .name = "dext_pv" },

        .{ .name = "text_quiet" },
        .{ .name = "text_noisy" },
        .{ .name = "text_pv" },

        .{ .name = "lmr_non_improving" },
        .{ .name = "lmr_cutnode" },
        .{ .name = "lmr_noisy_ttm" },
        .{ .name = "lmr_found_pv" },
        .{ .name = "lmr_gave_check" },
        .{ .name = "lmr_is_checked" },
        .{ .name = "lmr_is_pv" },
        .{ .name = "lmr_was_pv" },
        .{ .name = "lmr_was_pv_non_fail_low" },

        .{ .name = "deeper_margin_mult" },
        .{ .name = "deeper_margin_bias" },
        .{ .name = "shallower_margin_mult" },
        .{ .name = "shallower_margin_bias" },

        .{ .name = "qs_fp_margin" },
    };
    var tbl: [fields.len]Tunable = undefined;

    for (tbl[0..], inits[0..]) |*tunable, tunable_init| {
        const name = tunable_init.name[0..];
        const v = @field(zon, name);
        tunable.* = tunable_init.expand(v);

        const min = tunable.min();
        const max = tunable.max();
        if (v != std.math.clamp(v, min, max)) {
            const msg = std.fmt.comptimePrint(
                "tunable {s} has value {} outside of [{}, {}]",
                .{ name, v, min, max },
            );
            @compileError(msg);
        }
    }

    break :blk tbl;
};

pub const tuning = options.tuning;

pub var values: Values = .{};

pub fn deinit() void {}

pub fn init() !void {
    try lmr.init();
}

pub fn parseTunable(
    name: []const u8,
    aux: []const u8,
    tokens: *std.mem.TokenIterator(u8, .scalar),
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
    if (value != std.math.clamp(value, tunable.min(), tunable.max())) {
        return error.UnknownCommand;
    }

    dst.* = value;
    if (std.mem.indexOf(u8, name, "base_lmr")) |_| {
        try lmr.init();
    }
}

pub fn printOptions(writer: *std.Io.Writer) !void {
    const fmt = "option name {s} type spin default {d} min {d} max {d}\n";
    for (tunables[0..]) |*tunable| {
        try writer.print(fmt, .{ tunable.init.name, tunable.value, tunable.min(), tunable.max() });
    }
}

pub fn printValues(writer: *std.Io.Writer) !void {
    const fmt = "{s}, int, {d:.1}, {d:.1}, {d:.1}, {d:.3}, 0.002\n";
    for (tunables[0..]) |*tunable| {
        const val: f32 = @floatFromInt(tunable.value);
        const min: f32 = @floatFromInt(tunable.min());
        const max: f32 = @floatFromInt(tunable.max());
        try writer.print(fmt, .{ tunable.init.name, val, min, max, tunable.cEnd() });
    }
}
