const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const fens: [20][]const u8 = .{
    "2r1k3/pp3pp1/4p1p1/8/3nP3/2P4P/PP6/2K2R2 w - - 0 1",
    "8/pk6/1p6/3N1R1p/2P3nP/1P6/r5P1/2K2R2 b - - 0 1",
    "8/5pk1/6p1/2R2b2/8/8/r7/4K3 b - - 0 1",
    "1r4k1/5pp1/pnR4p/1p3P1P/1P6/P2PrB1N/6P1/6K1 w - - 0 3",
    "3r2k1/p4pp1/1p1P3p/4P3/1R6/7b/PP1r3P/2R4K b - - 0 1",
    "8/1B6/6pk/1R5p/5K1P/8/5P2/4r3 b - - 0 1",
    "1r4k1/5p1p/p1B1p1p1/3p2q1/3P4/2P2Q1P/5PP1/R5K1 w - - 0 1",
    "3r2k1/pp3ppp/8/8/5Q2/2P2N1P/Pq3PP1/5RK1 w - - 0 1",
    "r2q2k1/pppn2pp/8/2bP1p2/5P2/P7/1PPBN1PP/2KR3R b - - 0 2",
    "5r1k/2p3bp/4Q3/4np2/3q4/1PN4P/3B1PP1/5RK1 w - - 0 1",
    "r2q1rk1/pQp1bp1p/5np1/8/2N1p3/8/PP3PPP/R1B2RK1 w - - 0 1",
    "2r2rk1/1p3ppp/4p3/3pP3/1b1P1PP1/8/3NK2P/R6R b - - 0 1",
    "2r5/p4kp1/4p2p/2p2p2/5P2/PP3P2/3R1KPP/8 b - - 0 1",
    "5rk1/pr1q1ppp/4p1n1/8/1Pp5/2P1BN2/6PP/R3Q2K w - - 0 1",
    "r3kb1r/1b3ppp/p3p3/1p6/3Nn3/8/PPP2PPP/R1B2RK1 b kq - 0 1",
    "6k1/3R2p1/p6p/1p6/1rb5/7P/5PPK/8 b - - 0 1",
    "6k1/p5p1/1pp2p1p/8/2pP4/2PnB1P1/P6P/6K1 w - - 0 1",
    "8/6bq/8/2p3P1/1k4KP/8/8/8 b - - 0 1",
    "2k4r/5pp1/1pp1p3/4P2p/PP3P2/2P1R1PK/2r4P/R7 b - - 0 1",
    "3rr1k1/ppq2ppp/2p5/2R1pb2/1P6/P2PPN1P/3QBPP1/6K1 b - - 0 1",
};

pub fn run(pool: *engine.Thread.Pool, depth: ?engine.Thread.Depth) !void {
    pool.limits.depth = depth orelse 12;
    pool.limits.infinite = false;

    const board = try pool.allocator.create(engine.Board);
    defer pool.allocator.destroy(board);

    var sum: u64 = 0;
    var time: u64 = 0;

    for (fens) |fen| {
        try board.parseFen(fen);

        pool.setBoard(board, true);
        pool.bench();

        time += pool.timer.lap();
        sum += pool.nodes();
    }

    const nps = sum * std.time.ns_per_s / time;
    try pool.io.writer().print("{d} nodes {d} nps\n", .{ sum, nps });
    try pool.io.writer().flush();
}
