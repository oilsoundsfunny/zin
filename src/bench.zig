const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const fens: [50][]const u8 = .{
    "nrbkrbnq/pppppp1p/6p1/8/8/2P5/PP1PPPPP/NQRNKBBR w KQkq - 0 2",
    "nrbnkbrq/ppppppp1/8/7p/1P6/8/P1PPPPPP/BNNRKQRB w KQkq - 0 2",
    "qbrnkrbn/pp1ppppp/8/2p5/2P5/8/PP1PPPPP/BNQBNRKR w KQkq - 0 2",
    "rknrbbqn/pppppppp/8/8/3P4/8/PPP1PPPP/NRKBBQNR b KQkq - 0 1",
    "bnrknrqb/pp1ppppp/8/2p5/8/2P5/PP1PPPPP/NRNBKRBQ w KQkq - 0 2",
    "r1bbqknr/pppppppp/2n5/8/8/2P2N2/PP1PPPPP/QBBR1NKR b KQkq - 2 2",
    "rkrqbbnn/pppppppp/8/8/6P1/8/PPPPPP1P/BRKNNRQB b KQkq - 0 1",
    "nqrkbbnr/p1pppppp/8/1p6/7P/8/PPPPPPP1/RBNNQKBR w KQkq - 0 2",
    "rknbbrqn/1ppppppp/8/p7/7P/8/PPPPPPP1/NBBRKQNR w KQkq - 0 2",
    "bnnbrkqr/pp1ppppp/2p5/8/6P1/8/PPPPPP1P/NRQKBNRB w KQkq - 0 2",
    "qnrnkbbr/pppppppp/8/8/8/6P1/PPPPPP1P/BNNRKRQB b KQkq - 0 1",
    "rnbbknrq/ppp1pppp/3p4/8/P7/8/1PPPPPPP/QNRKNRBB w KQkq - 0 2",
    "rbbnknrq/pp1ppppp/2p5/8/7P/2N5/PPPPPPP1/R1KBNRBQ b KQkq - 0 2",
    "nnkrbrqb/pppppppp/8/8/3P4/2P5/PP2PPPP/NRBBKRNQ b KQ - 0 2",
    "nnrkqbbr/pppppppp/8/8/4P3/8/PPPP1PPP/RKNBRQBN b KQkq - 0 1",
    "rknnrqbb/pppp1ppp/8/4p3/8/2P5/PP1PPPPP/NBRKBQNR w KQkq - 0 2",
    "bnnrqkrb/p1pppppp/8/1p6/8/1P6/P1PPPPPP/BQRKNNRB w KQkq - 0 2",
    "bqnbrnkr/pppp1ppp/8/4p3/1P6/8/P1PPPPPP/RNNBQKBR w KQkq - 0 2",
    "bqnrknrb/1ppppppp/8/p7/8/5P2/PPPPP1PP/NRKBBQNR w KQkq - 0 2",
    "rnbnkbqr/pppppp1p/6p1/8/4P3/2N5/PPPP1PPP/RQK1RBBN b KQkq - 1 2",
    "bbrknrqn/p1pppppp/1p6/8/4P3/8/PPPP1PPP/BRKNRNQB w KQkq - 0 2",
    "rbbnqnkr/pppppppp/8/8/8/6N1/PPPPPPPP/QRKBBRN1 b KQkq - 1 1",
    "nrnkrbbq/ppppp1pp/8/5p2/2P5/8/PP1PPPPP/NNRQBKRB w KQkq - 0 2",
    "bqrnkbrn/pppppppp/8/8/8/8/PPPPPPPP/RNQKBBRN w GAgc - 0 1",
    "rnqnkbbr/pppppppp/8/8/8/8/PPPPPPPP/RBBQNKNR w HAha - 0 1",

    "4n3/pp1kp2R/2p5/3N4/7P/1P3K2/P7/4r3 w - - 0 30",
    "6b1/8/6Bk/4N2p/5P2/b3K1P1/7P/8 b - - 0 42",
    "3r2k1/p1p1R1pp/8/2B5/2p3PP/8/PPb2P2/6K1 b - - 0 22",
    "8/p4kpp/2n2p2/8/P2N4/4P1P1/5PKP/8 b - - 0 31",
    "4k1n1/2p1n1B1/1p1p2p1/p2P1p1p/2P2P2/1PN3PP/P3K3/8 w - - 0 36",
    "2B5/k7/P1Rb4/6p1/5bP1/6r1/4K3/8 b - - 0 46",
    "5k2/5p1p/1b2p3/5p2/P4P2/4N1PK/3nBP1P/8 w - - 0 45",
    "3kr3/8/1p1r1p2/p2p1Bp1/3B4/3PP1PP/PP3P2/4K3 b - - 0 33",
    "3r2k1/1p3pp1/4b3/p3p2p/4P3/6P1/PP3PKP/R2N4 w - - 0 23",
    "8/6k1/8/4Nb1p/5P2/1B3KP1/7P/b7 w - - 0 43",
    "4r3/p1p2k2/8/2N2p1p/PP1Bp2P/4P1P1/3Kb3/8 b - - 0 39",
    "8/8/3b1kpp/8/2R5/1P1K4/n4PPP/8 b - - 0 59",
    "2b5/5p2/1p2rk1p/5p2/1R6/3BK1P1/7P/8 w - - 0 36",
    "4r3/5kp1/2p5/1pBp4/p1b2Pp1/P1P3P1/3R1K1P/8 b - - 0 35",
    "2R5/5pbk/7p/5NpP/4Pp2/5P1K/6P1/r7 b - - 0 64",
    "1r6/5n2/3pk3/2p1p2p/2NpP1pP/3P2P1/4K3/R7 w - - 0 40",
    "1r4k1/5pp1/2n4p/1p6/7P/1N4P1/1R3P2/6K1 b - - 0 34",
    "8/1k1br1p1/1p3pBp/7P/P1R5/5P2/6K1/8 b - - 0 52",
    "4r1k1/1p3pp1/p7/7p/2b5/P5PP/1P1R1PB1/6K1 w - - 0 24",
    "8/2B2n1p/6p1/3k1p2/7P/3B4/3b2K1/8 b - - 0 45",
    "4b3/p4pkp/B5p1/8/1B1b2PP/5P2/6K1/8 b - - 0 28",
    "2B5/7p/3k2p1/5p2/4n2P/2b1B3/6K1/8 b - - 0 43",
    "2B5/4k2p/6p1/4Bp2/4n2P/b6K/8/8 b - - 0 43",
    "4b3/7r/3kppp1/pp1p3p/3P2PP/2P2PR1/P2K4/7R w - - 0 32",
    "6k1/p7/1p1b2p1/2pP4/P1P2r1P/1P3B2/5BK1/8 b - - 0 42",
};

pub fn run(pool: *engine.Thread.Pool, depth: ?engine.Thread.Depth) !void {
    pool.limits.depth = depth orelse 13;
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
