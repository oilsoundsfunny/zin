const misc = @import("misc");
const std = @import("std");

const search = @import("search.zig");

pub var overhead: u64 = 10;

pub var depth: ?search.Depth = null;
pub var increment = std.EnumArray(misc.types.Color, ?u64).initFill(null);
pub var movetime: ?u64 = null;
pub var time = std.EnumArray(misc.types.Color, ?u64).initFill(null);

pub var start: u64 = undefined;
pub var stop: ?u64 = null;
