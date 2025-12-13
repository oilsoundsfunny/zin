const engine = @import("engine");
const std = @import("std");
const types = @import("types");

pub const lmr = @import("lmr.zig");

pub const Int = engine.evaluation.score.Int;
pub const TunableRef = if (tuning) *Tunable else *const Tunable;

pub const Tunable = struct {
	name:	[]const u8,
	value:	Int,
	min:	?Int = null,
	max:	?Int = null,
	c_end:	?f32 = null,

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

const defaults = struct {
	pub const base_time_mul: Int = 5;
	pub const base_incr_mul: Int = 50;

	pub const max_hist_bonus: Int = 768;
	pub const hist_bonus2: Int = 0;
	pub const hist_bonus1: Int = 64;
	pub const hist_bonus0: Int = 0;

	pub const max_hist_malus: Int = 768;
	pub const hist_malus2: Int = 0;
	pub const hist_malus1: Int = 64;
	pub const hist_malus0: Int = 0;

	pub const iir_min_depth: Int = 4;

	pub const rfp_max_depth: Int = 8;
	pub const rfp_depth_mul: Int = 78;
	pub const rfp_ntm_worsening: Int = 14;

	pub const nmp_min_depth: Int = 3;
	pub const nmp_eval_margin: Int = 0;
	pub const nmp_base_reduction: Int = 768;
	pub const nmp_depth_mul: Int = 64;
	pub const nmp_eval_diff_divisor: Int = 400;
	pub const nmp_max_eval_reduction: Int = 3;

	pub const razoring_max_depth: Int = 7;
	pub const razoring_depth_mul: Int = 460;

	pub const lmr_min_depth: Int = 3;
	pub const lmr_non_improving: Int = 1024;
	pub const lmr_cutnode: Int = 1024;
	pub const lmr_noisy_ttm: Int = 1024;
	pub const lmr_gave_check: Int = 1024;
	pub const lmr_is_checked: Int = 1024;
	pub const lmr_is_pv: Int = 1024;
	pub const lmr_was_pv: Int = 1024;
	pub const lmr_was_pv_non_fail_low: Int = 1024;

	pub const qs_fp_margin: Int = 64;
};

pub const tuning = false;
pub const tunables = [_]Tunable {
	.{.name = "base_time_mul", .value = defaults.base_time_mul, .min = 2, .max = 13, .c_end = 1.0},
	.{.name = "base_incr_mul", .value = defaults.base_incr_mul, .min = 25, .max = 100, .c_end = 5.0},

	.{.name = "max_hist_bonus", .value = defaults.max_hist_bonus, .min = 512, .max = 3072, .c_end = 256},
	.{.name = "hist_bonus2", .value = defaults.hist_bonus2, .min = 0, .max = 1536, .c_end = 64},
	.{.name = "hist_bonus1", .value = defaults.hist_bonus1, .min = 64, .max = 384, .c_end = 32},
	.{.name = "hist_bonus0", .value = defaults.hist_bonus0, .min = -768, .max = 384, .c_end = 64},

	.{.name = "max_hist_malus", .value = defaults.max_hist_malus, .min = 512, .max = 3072, .c_end = 256},
	.{.name = "hist_malus2", .value = defaults.hist_malus2, .min = 0, .max = 1536, .c_end = 64},
	.{.name = "hist_malus1", .value = defaults.hist_malus1, .min = 64, .max = 384, .c_end = 32},
	.{.name = "hist_malus0", .value = defaults.hist_malus0, .min = -768, .max = 384, .c_end = 64},

	.{.name = "iir_min_depth", .value = defaults.iir_min_depth, .min = 2, .max = 9, .c_end = 1.0},

	.{.name = "rfp_max_depth", .value = defaults.rfp_max_depth, .min = 4, .max = 10, .c_end = 1.0},
	.{.name = "rfp_depth_mul", .value = defaults.rfp_depth_mul, .min = 50, .max = 100, .c_end = 8.0},
	.{.name = "rfp_ntm_worsening", .value = defaults.rfp_ntm_worsening, .min = 5, .max = 100, .c_end = 8.0},

	.{.name = "nmp_min_depth", .value = defaults.nmp_min_depth, .min = 2, .max = 5, .c_end = 1.0},
	.{.name = "nmp_eval_margin", .value = defaults.nmp_eval_margin, .min = 0, .max = 100, .c_end = 10.0},
	.{.name = "nmp_base_reduction", .value = defaults.nmp_base_reduction, .min = 512, .max = 2048, .c_end = 64.0},
	.{.name = "nmp_depth_mul", .value = defaults.nmp_depth_mul, .min = 32, .max = 96, .c_end = 12.0},
	.{.name = "nmp_eval_diff_divisor", .value = defaults.nmp_eval_diff_divisor, .min = 50, .max = 400, .c_end = 10.0},
	.{.name = "nmp_max_eval_reduction", .value = defaults.nmp_max_eval_reduction, .min = 2, .max = 5, .c_end = 1.0},

	.{.name = "razoring_max_depth", .value = defaults.razoring_max_depth, .min = 1, .max = 10, .c_end = 1.0},
	.{.name = "razoring_depth_mul", .value = defaults.razoring_depth_mul, .min = 250, .max = 650, .c_end = 10.0},

	.{.name = "lmr_min_depth", .value = defaults.lmr_min_depth, .min = 2, .max = 5, .c_end = 1.0},
	.{.name = "lmr_non_improving", .value = defaults.lmr_non_improving, .min = 0, .max = 2048, .c_end = 256.0},
	.{.name = "lmr_cutnode", .value = defaults.lmr_cutnode, .min = 0, .max = 2048, .c_end = 256.0},
	.{.name = "lmr_noisy_ttm", .value = defaults.lmr_noisy_ttm, .min = 0, .max = 2048, .c_end = 256.0},
	.{.name = "lmr_gave_check", .value = defaults.lmr_gave_check, .min = 0, .max = 2048, .c_end = 256.0},
	.{.name = "lmr_is_checked", .value = defaults.lmr_is_checked, .min = 0, .max = 2048, .c_end = 256.0},
	.{.name = "lmr_is_pv", .value = defaults.lmr_is_pv, .min = 0, .max = 2048, .c_end = 256.0},
	.{.name = "lmr_was_pv", .value = defaults.lmr_was_pv, .min = 0, .max = 2048, .c_end = 256.0},
	.{.name = "lmr_was_pv_non_fail_low", .value = defaults.lmr_was_pv_non_fail_low, .min = 0, .max = 2048, .c_end = 256.0},

	.{.name = "qs_fp_margin", .value = defaults.qs_fp_margin, .min = 0, .max = 250, .c_end = 16.0},
};

pub const values = if (tuning) struct {
	pub var base_time_mul = defaults.base_time_mul;
	pub var base_incr_mul = defaults.base_incr_mul;

	pub var max_hist_bonus = defaults.max_hist_bonus;
	pub var hist_bonus2 = defaults.hist_bonus2;
	pub var hist_bonus1 = defaults.hist_bonus1;
	pub var hist_bonus0 = defaults.hist_bonus0;

	pub var max_hist_malus = defaults.max_hist_malus;
	pub var hist_malus2 = defaults.hist_malus2;
	pub var hist_malus1 = defaults.hist_malus1;
	pub var hist_malus0 = defaults.hist_malus0;

	pub var iir_min_depth = defaults.iir_min_depth;

	pub var rfp_max_depth = defaults.rfp_max_depth;
	pub var rfp_depth_mul = defaults.rfp_depth_mul;
	pub var rfp_ntm_worsening = defaults.rfp_ntm_worsening;

	pub var nmp_min_depth = defaults.nmp_min_depth;
	pub var nmp_eval_margin = defaults.nmp_eval_margin;
	pub var nmp_base_reduction = defaults.nmp_base_reduction;
	pub var nmp_depth_mul = defaults.nmp_depth_mul;
	pub var nmp_eval_diff_divisor = defaults.nmp_eval_diff_divisor;
	pub var nmp_max_eval_reduction = defaults.nmp_max_eval_reduction;

	pub var razoring_max_depth = defaults.razoring_max_depth;
	pub var razoring_depth_mul = defaults.razoring_depth_mul;

	pub var lmr_min_depth = defaults.lmr_min_depth;
	pub var lmr_non_improving = defaults.lmr_non_improving;
	pub var lmr_cutnode = defaults.lmr_cutnode;
	pub var lmr_noisy_ttm = defaults.lmr_noisy_ttm;
	pub var lmr_gave_check = defaults.lmr_gave_check;
	pub var lmr_is_checked = defaults.lmr_is_checked;
	pub var lmr_is_pv = defaults.lmr_is_pv;
	pub var lmr_was_pv = defaults.lmr_was_pv;
	pub var lmr_was_pv_non_fail_low = defaults.lmr_was_pv_non_fail_low;

	pub var qs_fp_margin = defaults.qs_fp_margin;
} else defaults;

pub fn deinit() void {
}

pub fn init() !void {
	try lmr.init();
}

pub fn parseTunable(name: []const u8, aux: []const u8,
  tokens: *std.mem.TokenIterator(u8, .any)) engine.uci.Error!void {
	var opt_tunable: ?*const Tunable = null;
	var opt_value: ?*Int = null;
	inline for (tunables[0 ..]) |*tunable| {
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

pub fn printOptions(io: *types.Io) !void {
	const writer = io.writer();
	for (tunables) |tunable| {
		try writer.print("option name {s} type spin default {d} min {d} max {d}\n",
		  .{tunable.name, tunable.value, tunable.getMin(), tunable.getMax()});
	}
	try writer.flush();
}

pub fn printValues(io: *types.Io) !void {
	const writer = io.writer();
	for (tunables) |tunable| {
		try writer.print("{s}, int, {d:.1}, {d:.1}, {d:.1}, {d:.3}, 0.002\n", .{
		  tunable.name,
		  @as(f32, @floatFromInt(tunable.value)),
		  @as(f32, @floatFromInt(tunable.getMin())),
		  @as(f32, @floatFromInt(tunable.getMax())),
		  tunable.getCEnd(),
		});
	}
	try writer.flush();
}
