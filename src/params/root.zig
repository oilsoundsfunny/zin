const engine = @import("engine");
const std = @import("std");
const types = @import("types");

pub const lmr = @import("lmr.zig");
pub const tuning = @import("options").tuning;

const TunableValue = if (!tuning) void else struct {
    tunable: *const Tunable,
    value: *Tunable.Int,
};

const Values = blk: {
    const Types: [tunables.len]type = @splat(Tunable.Int);
    var names: [tunables.len][]const u8 = undefined;
    var attrs: [tunables.len]std.builtin.Type.StructField.Attributes = undefined;
    for (tunables[0..], names[0..], attrs[0..]) |*tunable, *name, *attr| {
        name.* = tunable.name[0..];
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
        const name = tunable.name[0..];
        kvs[i] = .{ name, .{ .tunable = tunable, .value = &@field(values, name) } };
    }
    break :blk std.StaticStringMap(TunableValue).initComptime(kvs);
};

pub const Tunable = struct {
    name: []const u8,
    value: Int,
    min: Int,
    max: Int,
    c_end: f64,

    const Init = struct {
        name: [:0]const u8,
        min: Int,
        max: Int,
        c_end: f64,

        fn expand(self: Init, v: Int) Tunable {
            return .{
                .name = self.name,
                .value = v,
                .min = self.min,
                .max = self.max,
                .c_end = self.c_end,
            };
        }
    };

    pub const Int = engine.evaluation.score.Int;
};

const tunables = blk: {
    const zon = @import("spsa.zig.zon");
    const fields = std.meta.fields(@TypeOf(zon));
    const inits: [fields.len]Tunable.Init = .{
        // zig fmt: off
        .{ .name = "tm_time_mult", .min = 0, .max = 1024, .c_end =  4.0 },
        .{ .name = "tm_incr_mult", .min = 0, .max = 1024, .c_end = 64.0 },

        .{ .name = "nodetm_mult", .min = 0, .max = 2097152, .c_end =  98304.0 },
        .{ .name = "nodetm_bias", .min = 0, .max = 3145728, .c_end = 131072.0 },

        .{ .name = "base_lmr_noisy_mult", .min = 0, .max =  48, .c_end =  2.0 },
        .{ .name = "base_lmr_noisy_bias", .min = 0, .max = 512, .c_end = 24.0 },

        .{ .name = "base_lmr_quiet_mult", .min = 0, .max = 1024, .c_end = 48.0 },
        .{ .name = "base_lmr_quiet_bias", .min = 0, .max = 1024, .c_end = 48.0 },

        .{ .name = "ordering_pawn",   .min = 0, .max = 16384, .c_end =  128.0 },
        .{ .name = "ordering_knight", .min = 0, .max = 16384, .c_end =  384.0 },
        .{ .name = "ordering_bishop", .min = 0, .max = 16384, .c_end =  384.0 },
        .{ .name = "ordering_rook",   .min = 0, .max = 16384, .c_end =  512.0 },
        .{ .name = "ordering_queen",  .min = 0, .max = 16384, .c_end = 1024.0 },

        .{ .name = "see_pawn",   .min = 0, .max = 16384, .c_end =  16.0 },
        .{ .name = "see_knight", .min = 0, .max = 16384, .c_end =  48.0 },
        .{ .name = "see_bishop", .min = 0, .max = 16384, .c_end =  48.0 },
        .{ .name = "see_rook",   .min = 0, .max = 16384, .c_end =  96.0 },
        .{ .name = "see_queen",  .min = 0, .max = 16384, .c_end = 128.0 },

        .{ .name = "quiethist_max_bonus",  .min =    0, .max = 4096, .c_end = 128.0 },
        .{ .name = "quiethist_bonus_quad", .min =    0, .max =  128, .c_end =   4.0 },
        .{ .name = "quiethist_bonus_mult", .min = -512, .max =  512, .c_end =  32.0 },
        .{ .name = "quiethist_bonus_bias", .min =    0, .max =  768, .c_end =  32.0 },

        .{ .name = "quiethist_max_malus",  .min =    0, .max = 4096, .c_end = 128.0 },
        .{ .name = "quiethist_malus_quad", .min =    0, .max =  128, .c_end =   4.0 },
        .{ .name = "quiethist_malus_mult", .min = -512, .max =  512, .c_end =  32.0 },
        .{ .name = "quiethist_malus_bias", .min =    0, .max =  768, .c_end =  32.0 },

        .{ .name = "noisyhist_max_bonus",  .min =    0, .max = 4096, .c_end = 128.0 },
        .{ .name = "noisyhist_bonus_quad", .min =    0, .max =  128, .c_end =   4.0 },
        .{ .name = "noisyhist_bonus_mult", .min = -512, .max =  512, .c_end =  32.0 },
        .{ .name = "noisyhist_bonus_bias", .min =    0, .max =  768, .c_end =  32.0 },

        .{ .name = "noisyhist_max_malus",  .min =    0, .max = 4096, .c_end = 128.0 },
        .{ .name = "noisyhist_malus_quad", .min =    0, .max =  128, .c_end =   4.0 },
        .{ .name = "noisyhist_malus_mult", .min = -512, .max =  512, .c_end =  32.0 },
        .{ .name = "noisyhist_malus_bias", .min =    0, .max =  768, .c_end =  32.0 },

        .{ .name = "corr_pawn_w",        .min = 0, .max = 1536, .c_end = 64.0 },
        .{ .name = "corr_minor_w",       .min = 0, .max = 1536, .c_end = 64.0 },
        .{ .name = "corr_major_w",       .min = 0, .max = 1536, .c_end = 64.0 },
        .{ .name = "corr_nonpawn_stm_w", .min = 0, .max = 1536, .c_end = 64.0 },
        .{ .name = "corr_nonpawn_ntm_w", .min = 0, .max = 1536, .c_end = 64.0 },

        .{ .name = "corr_pawn_update_w",        .min = 0, .max = 4096, .c_end = 128.0 },
        .{ .name = "corr_minor_update_w",       .min = 0, .max = 4096, .c_end = 128.0 },
        .{ .name = "corr_major_update_w",       .min = 0, .max = 4096, .c_end = 128.0 },
        .{ .name = "corr_nonpawn_update_stm_w", .min = 0, .max = 4096, .c_end = 128.0 },
        .{ .name = "corr_nonpawn_update_ntm_w", .min = 0, .max = 4096, .c_end = 128.0 },

        .{ .name = "asp_window",      .min = 0, .max =  48, .c_end =  1.0 },
        .{ .name = "asp_window_mult", .min = 0, .max = 768, .c_end = 32.0 },

        .{ .name = "tt_depth_w",      .min = 0, .max = 2048, .c_end =  96.0 },
        .{ .name = "tt_age_w",        .min = 0, .max = 4096, .c_end = 192.0 },
        .{ .name = "tt_pv_w",         .min = 0, .max =  768, .c_end =  24.0 },
        .{ .name = "tt_upperbound_w", .min = 0, .max =  768, .c_end =  24.0 },
        .{ .name = "tt_exact_w",      .min = 0, .max =  768, .c_end =  24.0 },
        .{ .name = "tt_lowerbound_w", .min = 0, .max =  768, .c_end =  24.0 },
        .{ .name = "tt_move_w",       .min = 0, .max =  768, .c_end =  24.0 },

        .{ .name = "rfp_depth_quad",    .min =       0, .max =   2048, .c_end =    96.0 },
        .{ .name = "rfp_depth_mult",    .min = -131072, .max = 131072, .c_end = 12288.0 },
        .{ .name = "rfp_depth_bias",    .min =       0, .max = 196608, .c_end = 12288.0 },
        .{ .name = "rfp_ntm_worsening", .min =       0, .max =     96, .c_end =     2.0 },
        .{ .name = "rfp_fail_firm",     .min =       0, .max =   1024, .c_end =    48.0 },

        .{ .name = "nmp_eval_margin", .min = 0, .max =   64, .c_end =  2.0 },
        .{ .name = "nmp_base_r",      .min = 0, .max = 1536, .c_end = 48.0 },
        .{ .name = "nmp_depth_mult",  .min = 0, .max =  128, .c_end =  6.0 },
        .{ .name = "nmp_improving_r", .min = 0, .max =  512, .c_end = 16.0 },
        .{ .name = "nmp_deval_mult",  .min = 0, .max = 1024, .c_end = 48.0 },
        .{ .name = "nmp_deval_max_r", .min = 0, .max = 2048, .c_end = 96.0 },

        .{ .name = "razoring_mult", .min = 0, .max = 512, .c_end = 24.0 },

        .{ .name = "fp_margin_mult", .min = 0, .max = 256, .c_end =  8.0 },
        .{ .name = "fp_margin_bias", .min = 0, .max = 768, .c_end = 24.0 },
        .{ .name = "fp_hist_mult",   .min = 0, .max =  96, .c_end =  2.0 },

        .{ .name = "bnfp_margin_mult", .min = 0, .max =  512, .c_end = 16.0 },
        .{ .name = "bnfp_margin_bias", .min = 0, .max = 1536, .c_end = 48.0 },
        .{ .name = "bnfp_hist_mult",   .min = 0, .max =   96, .c_end =  2.0 },

        .{ .name = "lmp_improving_quad", .min =     0, .max = 1536, .c_end =  64.0 },
        .{ .name = "lmp_improving_mult", .min = -4096, .max = 4096, .c_end = 256.0 },
        .{ .name = "lmp_improving_bias", .min =     0, .max = 6144, .c_end = 256.0 },

        .{ .name = "lmp_nonimproving_quad", .min =     0, .max =  512, .c_end =  24.0 },
        .{ .name = "lmp_nonimproving_mult", .min = -2048, .max = 2048, .c_end = 192.0 },
        .{ .name = "lmp_nonimproving_bias", .min =     0, .max = 3072, .c_end = 192.0 },

        .{ .name = "pvs_see_quiet_mult",    .min = -192, .max =   0, .c_end = 6.0 },
        .{ .name = "pvs_see_noisy_mult",    .min = -256, .max =   0, .c_end = 8.0 },
        .{ .name = "pvs_see_max_capthist",  .min =    0, .max = 192, .c_end = 6.0 },
        .{ .name = "pvs_see_capthist_mult", .min =    0, .max =  64, .c_end = 2.0 },

        .{ .name = "quiethist_pruning_lim",  .min =     0, .max = 6144, .c_end = 256.0 },
        .{ .name = "quiethist_pruning_mult", .min = -6144, .max = 6144, .c_end = 384.0 },
        .{ .name = "quiethist_pruning_bias", .min =     0, .max = 8192, .c_end = 384.0 },

        .{ .name = "noisyhist_pruning_lim",  .min =     0, .max = 6144, .c_end = 256.0 },
        .{ .name = "noisyhist_pruning_mult", .min = -6144, .max = 6144, .c_end = 384.0 },
        .{ .name = "noisyhist_pruning_bias", .min =     0, .max = 8192, .c_end = 384.0 },

        .{ .name = "se_beta_mult",        .min = 0, .max = 1024, .c_end = 32.0 },
        .{ .name = "se_beta_mult_pv",     .min = 0, .max = 1024, .c_end = 32.0 },
        .{ .name = "se_beta_mult_was_pv", .min = 0, .max = 1024, .c_end = 32.0 },
        .{ .name = "se_depth_mult",       .min = 0, .max =  768, .c_end = 32.0 },
        .{ .name = "se_depth_bias",       .min = 0, .max = 1536, .c_end = 32.0 },

        .{ .name = "ldse_margin", .min = 0, .max = 256, .c_end = 8.0 },

        .{ .name = "dext_quiet", .min = 0, .max = 48, .c_end = 1.0 },
        .{ .name = "dext_noisy", .min = 0, .max = 48, .c_end = 1.0 },
        .{ .name = "dext_pv",    .min = 0, .max = 48, .c_end = 2.0 },

        .{ .name = "text_quiet", .min = 0, .max = 128, .c_end =  6.0 },
        .{ .name = "text_noisy", .min = 0, .max = 128, .c_end =  6.0 },
        .{ .name = "text_pv",    .min = 0, .max = 768, .c_end = 32.0 },

        .{ .name = "lmr_non_improving",       .min = 0, .max = 3072, .c_end = 128.0 },
        .{ .name = "lmr_cutnode",             .min = 0, .max = 3072, .c_end = 128.0 },
        .{ .name = "lmr_noisy_ttm",           .min = 0, .max = 3072, .c_end = 128.0 },
        .{ .name = "lmr_found_pv",            .min = 0, .max = 3072, .c_end = 128.0 },
        .{ .name = "lmr_gave_check",          .min = 0, .max = 3072, .c_end = 128.0 },
        .{ .name = "lmr_is_checked",          .min = 0, .max = 3072, .c_end = 128.0 },
        .{ .name = "lmr_is_pv",               .min = 0, .max = 3072, .c_end = 128.0 },
        .{ .name = "lmr_was_pv",              .min = 0, .max = 3072, .c_end = 128.0 },
        .{ .name = "lmr_was_pv_non_fail_low", .min = 0, .max = 3072, .c_end = 128.0 },

        .{ .name = "deeper_margin0_mult",   .min = 0, .max = 32768, .c_end = 1024.0 },
        .{ .name = "deeper_margin0_bias",   .min = 0, .max =  3072, .c_end =   96.0 },
        .{ .name = "deeper_margin1_mult",   .min = 0, .max = 65536, .c_end = 2048.0 },
        .{ .name = "deeper_margin1_bias",   .min = 0, .max =  6144, .c_end =  192.0 },
        .{ .name = "shallower_margin_mult", .min = 0, .max =  3072, .c_end =   96.0 },
        .{ .name = "shallower_margin_bias", .min = 0, .max =  1024, .c_end =   32.0 },

        .{ .name = "qs_fp_margin", .min = 0, .max = 96, .c_end = 4.0 },
        // zig fmt: on
    };

    var tbl: [fields.len]Tunable = undefined;
    for (tbl[0..], inits[0..]) |*tunable, tunable_init| {
        const v = @field(zon, tunable_init.name);
        if (v != std.math.clamp(v, tunable_init.min, tunable_init.max)) {
            @compileError(std.fmt.comptimePrint(
                "tunable {s} has value {} outside of [{}, {}]",
                .{ tunable_init.name, v, tunable_init.min, tunable_init.max },
            ));
        }
        tunable.* = tunable_init.expand(v);
    }
    break :blk tbl;
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

    const value = std.fmt.parseInt(Tunable.Int, value_token, 10) catch return error.UnknownCommand;
    if (value != std.math.clamp(value, tunable.min, tunable.max)) {
        return error.UnknownCommand;
    }

    dst.* = value;
    if (std.mem.startsWith(u8, name, "base_lmr")) {
        try lmr.init();
    }
}

pub fn printOptions(writer: *std.Io.Writer) !void {
    const fmt = "option name {s} type spin default {d} min {d} max {d}\n";
    for (tunables[0..]) |*tunable| {
        try writer.print(fmt, .{ tunable.name, tunable.value, tunable.min, tunable.max });
    }
}

pub fn printValues(writer: *std.Io.Writer) !void {
    const fmt = "{s}, int, {d:.1}, {d:.1}, {d:.1}, {d:.3}, 0.002\n";
    for (tunables[0..]) |*tunable| {
        const val: f64 = @floatFromInt(tunable.value);
        const min: f64 = @floatFromInt(tunable.min);
        const max: f64 = @floatFromInt(tunable.max);
        try writer.print(fmt, .{ tunable.name, val, min, max, tunable.c_end });
    }
}
