const engine = @import("engine");
const std = @import("std");
const types = @import("types");

pub const lmr = @import("lmr.zig");

pub const Int = engine.evaluation.score.Int;
pub const TunableRef = if (tuning) *Tunable else *const Tunable;

pub const Tunable = struct {
	name:	[]const u8,
	value:	i32,
	min:	?i32 = null,
	max:	?i32 = null,
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

const tuning = false;
const defaults = struct {
	pub const iir_min_depth = 4;
	pub const iir_reduction = 1;

	pub const rfp_max_depth = 8;
	pub const rfp_depth_mult = 78;
	pub const rfp_ntm_worsening = 14;
	pub const rfp_min = 20;

	pub const nmp_min_depth = 3;
	pub const nmp_base_reduction = 3;
	pub const nmp_depth_divisor = 4;
	pub const nmp_eval_diff_divisor = 400;
	pub const nmp_eval_diff_div_floor = 3;
	pub const nmp_min_verif_depth = 15;
};

pub const tunables = [_]Tunable {
	.{.name = "iir_min_depth", .value = defaults.iir_min_depth, .min = null, .max = null, .c_end = null},
	.{.name = "iir_reduction", .value = defaults.iir_reduction, .min = null, .max = null, .c_end = null},

	.{.name = "rfp_max_depth", .value = defaults.rfp_max_depth, .min = null, .max = null, .c_end = null},
	.{.name = "rfp_depth_mult", .value = defaults.rfp_depth_mult, .min = null, .max = null, .c_end = null},
	.{.name = "rfp_ntm_worsening", .value = defaults.rfp_ntm_worsening, .min = null, .max = null, .c_end = null},
	.{.name = "rfp_min", .value = defaults.rfp_min, .min = null, .max = null, .c_end = null},

	.{.name = "nmp_min_depth", .value = defaults.nmp_min_depth, .min = null, .max = null, .c_end = null},
	.{.name = "nmp_base_reduction", .value = defaults.nmp_base_reduction, .min = null, .max = null, .c_end = null},
	.{.name = "nmp_depth_divisor", .value = defaults.nmp_depth_divisor, .min = null, .max = null, .c_end = null},
	.{.name = "nmp_eval_diff_divisor", .value = defaults.nmp_eval_diff_divisor, .min = null, .max = null, .c_end = null},
	.{.name = "nmp_eval_diff_div_floor", .value = defaults.nmp_eval_diff_div_floor, .min = null, .max = null, .c_end = null},
	.{.name = "nmp_min_verif_depth", .value = defaults.nmp_min_verif_depth, .min = null, .max = null, .c_end = null},
};

pub const values = if (tuning) struct {
	pub var iir_min_depth = defaults.iir_min_depth;
	pub var iir_reduction = defaults.iir_reduction;

	pub var rfp_max_depth = defaults.rfp_max_depth;
	pub var rfp_depth_mult = defaults.rfp_depth_mult;
	pub var rfp_ntm_worsening = defaults.rfp_ntm_worsening;
	pub var rfp_min = defaults.rfp_min;

	pub var nmp_min_depth = defaults.nmp_min_depth;
	pub var nmp_base_reduction = defaults.nmp_base_reduction;
	pub var nmp_depth_divisor = defaults.nmp_depth_divisor;
	pub var nmp_eval_diff_divisor = defaults.nmp_eval_diff_divisor;
	pub var nmp_eval_diff_div_floor = defaults.nmp_eval_diff_div_floor;
	pub var nmp_min_verif_depth = defaults.nmp_min_verif_depth;
} else defaults;

pub fn deinit() void {
}

pub fn init() !void {
	try lmr.init();
}

pub fn parseTunable(name: []const u8, aux: []const u8,
  tokens: *std.mem.TokenIterator(u8, .any)) engine.uci.Error!void {
	if (!tuning) {
		return;
	}

	var opt_match: ?*Int = null;
	inline for (tunables[0 ..]) |*tunable| {
		if (std.mem.eql(u8, name, tunable.name)) {
			opt_match = &@field(values, tunable.name);
		}
	}
	const match = opt_match orelse return error.UnknownCommand;

	if (!std.mem.eql(u8, aux, "value")) {
		return error.UnknownCommand;
	}

	const value_token = tokens.next() orelse return error.UnknownCommand;
	if (tokens.peek()) |_| {
		return error.UnknownCommand;
	}

	const value = std.fmt.parseInt(Int, value_token, 10) catch return error.UnknownCommand;
	if (value != std.math.clamp(value, match.getMin(), match.getMax())) {
		return error.UnknownCommand;
	}
	match.value = value;
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
		try writer.print("{s}, int, {d:.1}, {d:.1}, {d:.1}, {d}, 0.002\n", .{
		  tunable.name,
		  @as(f32, @floatFromInt(tunable.value)),
		  @as(f32, @floatFromInt(tunable.getMin())),
		  @as(f32, @floatFromInt(tunable.getMax())),
		  tunable.getCEnd(),
		});
	}
	try writer.flush();
}
