pub const Board = @import("Board.zig");
pub const evaluation = @import("evaluation.zig");
pub const movegen = @import("movegen.zig");
pub const Thread = @import("Thread.zig");
pub const transposition = @import("transposition.zig");
pub const uci = @import("uci.zig");
pub const zobrist = @import("zobrist.zig");

pub fn deinit() void {}

pub fn init() !void {
    try zobrist.init();
}
