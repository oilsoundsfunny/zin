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

const tuning = true;
const defaults = struct {
	pub const iir_min_depth: Int = 4;

	pub const rfp_max_depth: Int = 8;
	pub const rfp_depth_mult: Int = 78;
	pub const rfp_ntm_worsening: Int = 14;

	pub const razoring_depth_mult: Int = 460;
};

pub const tunables = [_]Tunable {
	.{.name = "iir_min_depth", .value = defaults.iir_min_depth, .min = 2, .max = 9, .c_end = 1.0},

	.{.name = "rfp_max_depth", .value = defaults.rfp_max_depth, .min = 4, .max = 10, .c_end = 1.0},
	.{.name = "rfp_depth_mult", .value = defaults.rfp_depth_mult, .min = 50, .max = 100, .c_end = 8.0},
	.{.name = "rfp_ntm_worsening", .value = defaults.rfp_ntm_worsening, .min = 5, .max = 100, .c_end = 8.0},

	.{.name = "razoring_depth_mult", .value = defaults.razoring_depth_mult, .min = null, .max = null, .c_end = null},
};

pub const values = if (tuning) struct {
	pub var iir_min_depth = defaults.iir_min_depth;

	pub var rfp_max_depth = defaults.rfp_max_depth;
	pub var rfp_depth_mult = defaults.rfp_depth_mult;
	pub var rfp_ntm_worsening = defaults.rfp_ntm_worsening;

	pub var razoring_depth_mult = defaults.razoring_depth_mult;
} else defaults;

pub fn deinit() void {
}

pub fn init() !void {
	try lmr.init();
}

pub fn parseTunable(name: []const u8, aux: []const u8,
  tokens: *std.mem.TokenIterator(u8, .any)) engine.uci.Error!void {
	if (!tuning) {
		return error.UnknownCommand;
	}

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
	if (!tuning) {
		return;
	}

	const writer = io.writer();
	for (tunables) |tunable| {
		try writer.print("option name {s} type spin default {d} min {d} max {d}\n",
		  .{tunable.name, tunable.value, tunable.getMin(), tunable.getMax()});
	}
	try writer.flush();
}

pub fn printValues(io: *types.Io) !void {
	if (!tuning) {
		return;
	}

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
