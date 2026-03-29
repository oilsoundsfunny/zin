const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const fens: [25][]const u8 = .{
    "1k5r/1p1bbR2/p2pp3/2q4N/4p1P1/2N4P/PPP5/K3QR2 b - - 0 1",
    "6k1/6p1/R3pb1p/8/7P/3N1PB1/b2r2PK/8 w - - 0 1",
    "3r1k2/pp3ppp/2pr4/4NP2/nP4P1/3PR3/P2K3P/7R w - - 0 1",
    "5R2/p5pp/1p2p3/4p3/2k3P1/6PP/PPP4K/8 b - - 0 1",
    "r5k1/ppp2pp1/6p1/1P2B3/P3P3/3B1P1b/2P2b1P/3R3K b - - 0 1",
    "8/1K6/8/8/b2P2k1/8/8/4B3 b - - 0 1",
    "4r3/1p1k1p1p/pnrb2b1/3pp1P1/1PP5/PQ1P1B1P/1B3P2/2R2K1R b - - 0 1",
    "6k1/6p1/4p3/3b1pB1/8/2bB4/r1P2PP1/5R1K w - - 0 1",
    "1k4rr/ppp5/2nqp1np/3p1p2/B2P1PpP/4B1P1/PPPQ1P2/R3R1K1 w - - 0 1",
    "r1bq2k1/p2n1pp1/1p5p/3p4/2pPr3/5NP1/PPPQ1PP1/2KR3R w - - 0 3",
    "8/7p/pp6/8/4kn2/1N2pp2/8/4K3 w - - 0 2",
    "1k1r3r/8/pp1pR2p/6p1/8/1P4P1/P4P1P/4R1K1 w - - 0 1",
    "8/p1p1rn2/3k4/1P1p4/P2P2P1/2P5/3K4/R4B2 b - - 0 2",
    "2R5/8/3B4/1k5b/7P/8/5K2/8 b - - 0 1",
    "5r2/3b4/6kp/1p1p2p1/pR1Pp1q1/P3R1P1/4PP1P/5QK1 b - - 0 1",
    "5r2/1br2pk1/p3pnpp/8/1P1R4/P1p3NP/B1P2PP1/4R1K1 b - - 0 1",
    "8/7p/1P1r2p1/P1RP1k2/4p3/4K1P1/7P/8 b - - 0 1",
    "r2q1rk1/p2bbp1p/1p2p1p1/3n4/P2N4/N1PB2P1/1P2QPP1/R4RK1 w - - 0 2",
    "r2qk2r/pp3p2/2pp1p2/2b1pN1p/4Pn2/1PNP1Q2/1PP2PPP/R4RK1 w kq - 0 1",
    "2r2rk1/8/3Q2P1/3pp2P/8/3q4/PP3p2/K4R1R b - - 0 1",
    "r2qk2r/1bpnn3/pp1p2pb/3Ppp2/1PP1P3/2N2NP1/P2Q1PBP/R4RK1 w kq - 0 1",
    "4k3/p7/7p/8/4K3/r7/2n2P1P/8 b - - 0 1",
    "r7/5pk1/6p1/1p6/pP1q4/7p/1RKP4/8 w - - 0 1",
    "5kr1/pp3p2/1b1P4/2p1r2p/2P5/1P3N1P/P5P1/5R1K b - - 0 1",
    "8/7p/6k1/6B1/5P2/3p2P1/1P4K1/4r3 b - - 0 1",
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
