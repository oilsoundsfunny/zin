const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const fens: [25][]const u8 = .{
    "6k1/4r1p1/1Q2p2p/3b1q2/3R4/P3P3/1P3P1P/5BK1 b - - 0 2",
    "2r2rk1/pp3ppp/4p3/2Pp3q/4b2N/1P3PPP/P3Q2K/2R2R2 b - - 0 1",
    "r4r2/p4pkp/3pqbp1/1pp5/4P3/2P3QP/PP1N1PPK/R3R3 b - - 0 1",
    "rn3rk1/p3p2p/1p3b1P/1Np1qbBQ/P5p1/8/1PP1BR2/R3K3 b - - 0 1",
    "r2k3r/1b1pb2p/4pp2/pN5q/P7/1PB5/2P2PPP/2R2RK1 b - - 0 4",
    "r4rk1/5p2/p1Q1pp2/1pP4p/1P6/P6P/5PP1/3RR1K1 b - - 0 3",
    "8/8/6pk/8/1p3R1P/1Bq3PK/P7/8 w - - 0 1",
    "r7/3R2p1/6kp/8/p4B1P/P2p4/4b1K1/8 b - - 0 1",
    "2r3k1/7p/R1nqbQ2/2p2B2/1pPp3p/1P1P2P1/1B3P1P/6K1 b - - 0 1",
    "8/8/R7/p2k4/4p1Np/P7/6PK/4q3 b - - 0 1",
    "6k1/4r2p/1p6/2p5/8/1P4P1/P1P5/2K5 w - - 0 1",
    "8/8/8/1R3pk1/1P6/P1P3KP/8/8 b - - 0 1",
    "rk5r/pp1n2pp/2p1bn2/4p3/2P1P3/1PN1B2P/PK4P1/3R1B1R b - - 0 1",
    "8/5kp1/7p/5r2/5P1P/r5PK/8/5R2 w - - 0 1",
    "r5k1/p4q1p/6bB/1p1p4/3Qp3/8/PPP3PP/5RK1 b - - 0 1",
    "8/8/7R/4p1k1/8/4KP2/8/1r6 w - - 0 1",
    "1rr3k1/1q3ppp/3bpn2/1p1p4/pP1P4/P1N1PP2/1B2Q1PP/2R2RK1 b - - 0 1",
    "4R3/pp3pk1/2p5/3n3p/1P3P2/P1b3PP/5PK1/2R5 w - - 0 1",
    "2r1b1k1/5pN1/1q5p/3p3N/1p1P4/2R4P/3r2P1/5RK1 w - - 0 1",
    "1r1r1bk1/2q2p2/2pp1np1/p1n1p2p/2P1P3/1PB2B1P/P3QPP1/1NRR2K1 w - - 0 1",
    "8/8/6R1/p4p2/P2p1r1k/1P1P4/2P1K3/8 b - - 0 1",
    "8/k1pR4/2r5/2N1Q2P/2K2p2/2P5/PP6/n7 b - - 0 1",
    "r3kb1r/2p2ppp/p1q1p3/8/8/2B2P1R/1PPQ2PP/5BK1 b kq - 0 1",
    "5r2/3b1kp1/5q1p/1p1p4/p2Pp3/P1Q1P1P1/4P2P/RR4K1 b - - 0 1",
    "1k1rr3/1pp1np2/pq3n1p/3p2p1/PP6/3NPB2/2PN1PPP/1R1Q1RK1 w - - 0 1",
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
