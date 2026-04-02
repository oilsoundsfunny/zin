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

    const Init = struct {
        name: [:0]const u8,
        min: Int,
        max: Int,
        c_end: f32,
    };

    fn init(i: Init, v: Int) Tunable {
        return .{ .name = i.name, .value = v, .min = i.min, .max = i.max, .c_end = i.c_end };
    }
};

const tunables = blk: {
    const zon = @import("spsa.zig.zon");
    const Zon = @TypeOf(zon);

    const fields = std.meta.fields(Zon);
    const ini: [fields.len]Tunable.Init = .{
        .{ .name = "nodetm1", .min = 8, .max = 4096, .c_end = 24.0 },
        .{ .name = "nodetm0", .min = 1024, .max = 2048, .c_end = 48.0 },

        .{ .name = "base_lmr_noisy1", .min = 4, .max = 64, .c_end = 1.0 },
        .{ .name = "base_lmr_noisy0", .min = 256, .max = 4096, .c_end = 16.0 },
        .{ .name = "base_lmr_quiet1", .min = 256, .max = 4096, .c_end = 36.0 },
        .{ .name = "base_lmr_quiet0", .min = 256, .max = 4096, .c_end = 36.0 },

        .{ .name = "see_ordering_pawn", .min = 0, .max = 2340, .c_end = 16.0 },
        .{ .name = "see_ordering_knight", .min = 0, .max = 2340, .c_end = 32.0 },
        .{ .name = "see_ordering_bishop", .min = 0, .max = 2340, .c_end = 32.0 },
        .{ .name = "see_ordering_rook", .min = 0, .max = 2340, .c_end = 64.0 },
        .{ .name = "see_ordering_queen", .min = 0, .max = 2340, .c_end = 128.0 },

        .{ .name = "see_pruning_pawn", .min = 0, .max = 2340, .c_end = 16.0 },
        .{ .name = "see_pruning_knight", .min = 0, .max = 2340, .c_end = 32.0 },
        .{ .name = "see_pruning_bishop", .min = 0, .max = 2340, .c_end = 32.0 },
        .{ .name = "see_pruning_rook", .min = 0, .max = 2340, .c_end = 64.0 },
        .{ .name = "see_pruning_queen", .min = 0, .max = 2340, .c_end = 128.0 },

        .{ .name = "base_time_mul", .min = 32, .max = 128, .c_end = 4.0 },
        .{ .name = "base_incr_mul", .min = 256, .max = 1024, .c_end = 32.0 },

        .{ .name = "max_hist_bonus", .min = 256, .max = 4096, .c_end = 256.0 },
        .{ .name = "hist_bonus2", .min = 32, .max = 2048, .c_end = 64.0 },
        .{ .name = "hist_bonus1", .min = 32, .max = 512, .c_end = 32.0 },
        .{ .name = "hist_bonus0", .min = -768, .max = 768, .c_end = 64.0 },

        .{ .name = "max_hist_malus", .min = 256, .max = 4096, .c_end = 256.0 },
        .{ .name = "hist_malus2", .min = 32, .max = 2048, .c_end = 64.0 },
        .{ .name = "hist_malus1", .min = 32, .max = 512, .c_end = 32.0 },
        .{ .name = "hist_malus0", .min = -768, .max = 768, .c_end = 64.0 },

        .{ .name = "corr_pawn_w", .min = 256, .max = 4096, .c_end = 128.0 },
        .{ .name = "corr_minor_w", .min = 256, .max = 4096, .c_end = 128.0 },
        .{ .name = "corr_major_w", .min = 256, .max = 4096, .c_end = 128.0 },
        .{ .name = "corr_nonpawn_w", .min = 256, .max = 4096, .c_end = 128.0 },

        .{ .name = "corr_pawn_update_w", .min = 512, .max = 8192, .c_end = 256.0 },
        .{ .name = "corr_minor_update_w", .min = 512, .max = 8192, .c_end = 256.0 },
        .{ .name = "corr_major_update_w", .min = 512, .max = 8192, .c_end = 256.0 },
        .{ .name = "corr_nonpawn_update_w", .min = 512, .max = 8192, .c_end = 256.0 },

        .{ .name = "asp_window", .min = 2, .max = 32, .c_end = 2.0 },
        .{ .name = "asp_window_mul", .min = 4, .max = 256, .c_end = 32.0 },

        .{ .name = "tt_depth_w", .min = 4, .max = 4096, .c_end = 64.0 },
        .{ .name = "tt_age_w", .min = 4, .max = 4096, .c_end = 128.0 },
        .{ .name = "tt_pv_w", .min = 4, .max = 4096, .c_end = 8.0 },
        .{ .name = "tt_upperbound_w", .min = 4, .max = 4096, .c_end = 8.0 },
        .{ .name = "tt_exact_w", .min = 4, .max = 4096, .c_end = 8.0 },
        .{ .name = "tt_lowerbound_w", .min = 4, .max = 4096, .c_end = 8.0 },
        .{ .name = "tt_move_w", .min = 4, .max = 4096, .c_end = 8.0 },

        .{ .name = "rfp_depth2", .min = 512, .max = 2048, .c_end = 64.0 },
        .{ .name = "rfp_depth1", .min = 65536, .max = 262144, .c_end = 4096.0 },
        .{ .name = "rfp_depth0", .min = 4096, .max = 16384, .c_end = 512.0 },
        .{ .name = "rfp_ntm_worsening", .min = 8, .max = 128, .c_end = 1.0 },
        .{ .name = "rfp_fail_firm", .min = 0, .max = 1024, .c_end = 1.0 },

        .{ .name = "nmp_eval_margin", .min = 16, .max = 64, .c_end = 1.0 },
        .{ .name = "nmp_base_reduction", .min = 512, .max = 2048, .c_end = 32.0 },
        .{ .name = "nmp_depth_mul", .min = 64, .max = 256, .c_end = 4.0 },
        .{ .name = "nmp_improving_r", .min = 128, .max = 512, .c_end = 8.0 },
        .{ .name = "nmp_deval_mul", .min = 512, .max = 2048, .c_end = 32.0 },
        .{ .name = "nmp_deval_max_r", .min = 512, .max = 2048, .c_end = 64.0 },

        .{ .name = "razoring_mul", .min = 256, .max = 1024, .c_end = 16.0 },

        .{ .name = "fp_margin0", .min = 128, .max = 512, .c_end = 16.0 },
        .{ .name = "fp_margin1", .min = 64, .max = 256, .c_end = 8.0 },
        .{ .name = "fp_hist_mul", .min = 8, .max = 128, .c_end = 2.0 },

        .{ .name = "lmp_improving2", .min = 128, .max = 2048, .c_end = 64.0 },
        .{ .name = "lmp_improving1", .min = -1024, .max = 1024, .c_end = 128.0 },
        .{ .name = "lmp_improving0", .min = -8192, .max = 8192, .c_end = 256.0 },

        .{ .name = "lmp_nonimproving2", .min = 128, .max = 2048, .c_end = 64.0 },
        .{ .name = "lmp_nonimproving1", .min = -1024, .max = 1024, .c_end = 128.0 },
        .{ .name = "lmp_nonimproving0", .min = -8192, .max = 8192, .c_end = 256.0 },

        .{ .name = "pvs_see_quiet_mul", .min = -256, .max = -64, .c_end = 4.0 },
        .{ .name = "pvs_see_noisy_mul", .min = -256, .max = -64, .c_end = 4.0 },
        .{ .name = "pvs_see_max_capthist", .min = 64, .max = 256, .c_end = 4.0 },
        .{ .name = "pvs_see_capthist_mul", .min = 16, .max = 64, .c_end = 1.0 },

        .{ .name = "quiet_hist_pruning_lim", .min = 512, .max = 8192, .c_end = 128.0 },
        .{ .name = "quiet_hist_pruning0", .min = 512, .max = 2048, .c_end = 48.0 },
        .{ .name = "quiet_hist_pruning1", .min = -8192, .max = -512, .c_end = 128.0 },

        .{ .name = "noisy_hist_pruning_lim", .min = 512, .max = 8192, .c_end = 128.0 },
        .{ .name = "noisy_hist_pruning0", .min = 512, .max = 2048, .c_end = 48.0 },
        .{ .name = "noisy_hist_pruning1", .min = -8192, .max = -512, .c_end = 128.0 },

        .{ .name = "se_bmul", .min = 256, .max = 1024, .c_end = 24.0 },
        .{ .name = "se_bmul_pv", .min = 256, .max = 1024, .c_end = 32.0 },
        .{ .name = "se_bmul_was_pv", .min = 256, .max = 1024, .c_end = 32.0 },
        .{ .name = "se_d1", .min = 256, .max = 1024, .c_end = 32.0 },
        .{ .name = "se_d0", .min = 512, .max = 2048, .c_end = 64.0 },

        .{ .name = "dext_quiet", .min = 8, .max = 32, .c_end = 1.0 },
        .{ .name = "dext_noisy", .min = 8, .max = 32, .c_end = 1.0 },
        .{ .name = "dext_pv", .min = 8, .max = 32, .c_end = 1.0 },

        .{ .name = "text_quiet", .min = 64, .max = 256, .c_end = 8.0 },
        .{ .name = "text_noisy", .min = 64, .max = 256, .c_end = 8.0 },
        .{ .name = "text_pv", .min = 256, .max = 1024, .c_end = 32.0 },

        .{ .name = "lmr_non_improving", .min = 0, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmr_cutnode", .min = 0, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmr_noisy_ttm", .min = 0, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmr_gave_check", .min = 0, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmr_is_checked", .min = 0, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmr_is_pv", .min = 0, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmr_was_pv", .min = 0, .max = 4096, .c_end = 64.0 },
        .{ .name = "lmr_was_pv_non_fail_low", .min = 0, .max = 4096, .c_end = 64.0 },

        .{ .name = "deeper_margin1", .min = -1024, .max = 1024, .c_end = 32.0 },
        .{ .name = "deeper_margin0", .min = -1024, .max = 1024, .c_end = 32.0 },
        .{ .name = "shallower_margin1", .min = -1024, .max = 1024, .c_end = 32.0 },
        .{ .name = "shallower_margin0", .min = -1024, .max = 1024, .c_end = 32.0 },

        .{ .name = "qs_fp_margin", .min = 8, .max = 128, .c_end = 2.0 },
    };
    var tbl: [fields.len]Tunable = undefined;

    for (tbl[0..], ini[0..]) |*tunable, i| {
        const name = i.name;
        tunable.* = .init(i, @field(zon, name));
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
    for (tunables[0..]) |*tunable| {
        try writer.print(fmt, .{ tunable.name, tunable.value, tunable.min, tunable.max });
    }
}

pub fn printValues(writer: *std.Io.Writer) !void {
    const fmt = "{s}, int, {d:.1}, {d:.1}, {d:.1}, {d:.3}, 0.002\n";
    for (tunables[0..]) |*tunable| {
        const val: f32 = @floatFromInt(tunable.value);
        const min: f32 = @floatFromInt(tunable.min);
        const max: f32 = @floatFromInt(tunable.max);
        try writer.print(fmt, .{ tunable.name, val, min, max, tunable.c_end });
    }
}
