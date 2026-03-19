const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const fens: [50][]const u8 = .{
    "2k4r/pppr3p/6p1/3p2q1/8/3PR3/PbPQ2PP/RN4K1 w - - 0 1",
    "4r3/5Rpk/p6p/1p6/2pBp1b1/2P5/P1P3P1/1K3R2 b - - 0 1",
    "r1q2r1k/pp1np1bp/2p2np1/8/3P4/1QN1BN2/PP3PPP/3R1RK1 b - - 0 1",
    "8/1R4pp/4p1k1/3p4/2pP2P1/2n1KP1r/8/8 w - - 0 1",
    "rr4k1/4ppb1/b2p2pp/q1pPn3/P3P3/2N2P2/1PQ1N1PP/2BR1RK1 w - - 0 1",
    "1r1q1rk1/pbp1npp1/1p1p1n1p/3P4/2P1PN2/P1PB4/R5PP/2BQ1RK1 w - - 0 1",
    "2r1k2r/p2bbppp/1qn2n2/1B1p4/1P1Pp3/PQN1P3/1B3PPP/R3K1NR w KQk - 0 1",
    "r2q1rk1/p3bppp/bp2p3/n1ppP3/3P1P1n/1PP3P1/P3N1BP/R1BQK2R w KQ - 0 1",
    "5k2/2q3p1/5b2/P2Q4/8/8/P4PKP/1q6 b - - 0 1",
    "r1bqk2r/ppp2pp1/7p/b4p2/2PP4/B1P2N2/P1Q2PPP/R4RK1 w kq - 0 1",
    "8/7p/8/p2p1k2/P2P4/2P5/6K1/8 w - - 0 1",
    "1r3r2/5pk1/1p4p1/p6p/2B4P/8/P1RQ1PP1/6K1 w - - 0 1",
    "r4rk1/5pbp/p1p2np1/1p2p3/2P5/R6P/1P2RPP1/2BN2K1 b - - 0 2",
    "2k3n1/pp1n2p1/2p1r2p/3p4/6PQ/2PP3P/PP4P1/R5K1 w - - 0 2",
    "r1bq1rk1/p3bppp/2p2n2/3p4/3P4/1P4P1/2P2PBP/RNBQ1RK1 w - - 0 1",
    "6k1/5ppp/r3pb2/3p4/1P1P4/2Q1PPBP/q5P1/6K1 b - - 0 1",
    "r2r2k1/5ppp/1n2p3/8/1q2PP2/1pN3P1/1P1NQ1KP/4R3 w - - 0 1",
    "r1b1k2r/2p2p1p/p1N5/2p1Pp2/8/2P5/PP3PPP/R3K2R b KQkq - 0 1",
    "3q1rk1/p5bp/3ppnp1/4p3/1rP5/2BP2P1/3NPPBP/R2QK2R b KQ - 0 1",
    "8/3n1P2/1P6/8/P7/3k4/8/6K1 w - - 0 1",
    "r5k1/5p1p/bN2p1p1/pB6/P2P4/6P1/1P3PP1/6K1 b - - 0 1",
    "r1b1k3/ppp4p/3p1np1/8/6q1/2N5/PPP2PPP/5RK1 w - - 0 1",
    "7r/4n1kp/6p1/4Pp2/NBB5/8/5PPP/1R4K1 b - - 0 1",
    "r3rbk1/6pp/pp1q4/8/5P2/3RB3/P3Q1PP/2R3K1 b - - 0 3",
    "5r2/2p2pk1/p1N4p/1p2P3/1P2nP2/1Q4P1/P3K3/R7 w - - 0 1",
    "8/1p4pp/4k3/1pR5/1P2P3/6P1/6KP/8 b - - 0 2",
    "r4rk1/pp4pp/3p1b2/3Pp3/6b1/3B4/PP1N1PPP/R3R1K1 b - - 0 1",
    "r4rk1/1p1q2p1/p2b3p/1b1N1p2/4p3/4Q1P1/PPP1NPP1/R4RK1 b - - 0 1",
    "8/pB6/3p4/3P4/P1Pk4/1P3K2/8/8 b - - 0 1",
    "6k1/p2PR2p/1p6/2p2p2/2P5/2P5/P6r/2K5 b - - 0 1",
    "5bk1/4qp2/8/5K2/2P5/1P1R4/8/8 b - - 0 1",
    "5r2/p5kb/1p5p/2pB4/2Pp3p/1P1n3P/K5P1/8 w - - 0 1",
    "rn1q1r2/p2bppkp/5np1/1P2N3/2pQP3/2N2P2/1P4PP/R3KB1R b KQ - 0 3",
    "6rk/1p5p/p4q2/2Rb1N2/6p1/1P4N1/P4PP1/6K1 b - - 0 1",
    "8/3R1bk1/7p/6p1/PR3p2/4n3/r7/7K b - - 0 1",
    "4r1k1/5Np1/p3Ppp1/1prp4/2n5/2P4P/P4PP1/3RR1K1 b - - 0 1",
    "7k/4Q3/7P/2p1R3/p7/P6R/1P2K3/3r2q1 b - - 0 1",
    "rn3rk1/pbpq1pbp/1p1p2p1/3N4/2PpPBn1/3B1P2/PP1QN1PP/R4RK1 b - - 0 1",
    "8/pp2k3/6p1/5p2/1n1N3P/1P3P2/6P1/6K1 w - - 0 1",
    "3q3k/p7/8/4p3/1pP1B1r1/4P1P1/6K1/8 w - - 0 1",
    "3R4/5p2/2k5/4K3/6p1/4P3/b7/8 b - - 0 1",
    "3rr1k1/3Rb2p/5qp1/p2p4/2pPpPQ1/2P1P2P/3N2BK/1R6 w - - 0 1",
    "rn3rk1/1bq1bppp/pp1ppn2/8/2PQP3/1PN2NP1/PB3PBP/3R1RK1 b - - 0 1",
    "4k3/8/8/p4N2/1r6/3K4/6PP/8 w - - 0 1",
    "3rr3/2p3kp/Q4n2/2P2Bp1/8/P1Bp3P/6b1/1R1K4 b - - 0 1",
    "5k2/7p/5p2/6p1/PK1N4/5P2/6R1/r7 w - - 0 1",
    "r1bq1rk1/pp1p2bp/4p1p1/2p1npB1/2P1P3/1PP5/P2QNPPP/RN2K2R b KQ - 0 1",
    "rnb1k1nr/5ppp/p2qp3/8/1p6/5N2/PP1PKPPP/R1BQ3R w kq - 0 1",
    "3q1rk1/1R3pp1/3P1n1p/2Q1p1b1/4P3/5B2/r4PPP/5RK1 b - - 0 1",
    "8/8/3k1p2/1ppp1Bp1/p5P1/P1PK4/1P5P/8 b - - 0 1",
};

pub fn run(pool: *engine.Thread.Pool, depth: ?engine.Thread.Depth) !void {
    pool.limits.depth = depth orelse 10;
    pool.limits.infinite = false;

    var sum: u64 = 0;
    var time: u64 = 0;

    for (fens) |fen| {
        var board: engine.Board = .{};
        try board.parseFen(fen);

        pool.setBoard(&board, true);
        pool.bench();

        time += pool.timer.lap();
        sum += pool.nodes();
    }

    const nps = sum * std.time.ns_per_s / time;
    try pool.io.writer().print("{d} nodes {d} nps\n", .{ sum, nps });
    try pool.io.writer().flush();
}
