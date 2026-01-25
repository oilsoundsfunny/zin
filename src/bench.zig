const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const fens: [75][]const u8 = .{
    "rbqkbrnn/pppppppp/8/8/1P6/8/P1PPPPPP/BRNKNQRB b KQkq - 0 1",
    "nrqkrbbn/ppp1pppp/8/3p4/5P2/8/PPPPP1PP/BNRBKRQN w KQkq - 0 2",
    "rbbnqknr/ppppppp1/8/7p/6P1/8/PPPPPP1P/BRKNNQRB w KQkq - 0 2",
    "nnrbbkqr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/BNRBQKNR w KQkq - 0 2",
    "nrkqbrnb/p1pppppp/1p6/8/8/2P5/PP1PPPPP/NRNBQKBR w KQkq - 0 2",
    "rqnknrbb/pp1ppppp/2p5/8/8/3P4/PPP1PPPP/QRBNKRNB w KQkq - 0 2",
    "nrkrbnqb/pp1ppppp/8/2p5/8/5P2/PPPPP1PP/QBNRBKRN w KQkq - 0 2",
    "rnbqkbrn/pp1ppppp/2p5/8/3P4/8/PPP1PPPP/NBRKBRNQ w KQkq - 0 2",
    "rkrnbbqn/1ppppppp/8/p7/8/2P5/PP1PPPPP/NRBKQBNR w KQkq - 0 2",
    "nrqbbnkr/ppppppp1/7p/8/P7/3P4/1PP1PPPP/RKBNQNRB b KQkq - 0 2",
    "rkqbbrnn/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/BBNNRQKR w KQkq - 0 2",
    "rbqnkrbn/ppppp1pp/5p2/8/5PP1/8/PPPPP2P/RKNBBRQN b KQkq - 0 2",
    "bnqrkbrn/ppppp1pp/8/5p2/3P4/8/PPP1PPPP/QBNNBRKR w KQkq - 0 2",
    "brkbnrq1/pppppppp/6n1/8/1P6/8/P1PPPPPP/BBRQNKRN w KQkq - 1 2",
    "brkbnrnq/ppppppp1/8/7p/8/6P1/PPPPPP1P/BRNQKNRB w KQkq - 0 2",
    "rkbrnqnb/pppppp1p/8/6p1/6P1/4P3/PPPP1P1P/BRNQKBNR b KQkq - 0 2",
    "brkrqbnn/p1pppppp/8/1p6/6P1/8/PPPPPP1P/BBRNNQKR w KQkq - 0 2",
    "rnbkrnqb/ppppp1pp/8/5p2/1P6/8/P1PPPPPP/NQRNBKRB w KQkq - 0 2",
    "nrnbbkrq/ppppppp1/8/7p/8/6P1/PPPPPP1P/NNBRKRQB w KQkq - 0 2",
    "brnqnbkr/p1pppppp/8/1p6/8/3P1N2/PPP1PPPP/NRBBKR1Q b KQkq - 0 2",
    "brkbqnnr/p1pppppp/1p6/8/8/6P1/PPPPPP1P/BNRKNQRB w KQkq - 0 2",
    "r1nbkqbr/pppppppp/2n5/8/2P5/8/PP1PPPPP/NBRKQRBN w KQkq - 1 2",
    "qbrknnbr/pppppppp/8/8/8/1P6/P1PPPPPP/BBQNNRKR b KQkq - 0 1",
    "brnknqrb/ppppp1pp/8/5p2/4P3/8/PPPP1PPP/RQKBBNNR w KQkq - 0 2",
    "bqrbnkrn/pp1ppppp/8/2p5/6P1/8/PPPPPP1P/QNRKNRBB w KQkq - 0 2",

    "3b4/4k3/K3np2/4p1p1/1P2P1P1/8/5P2/3R4 b - - 0 49",
    "2B5/5k1p/6p1/4np2/3b3P/7K/3B4/8 w - - 0 43",
    "4R3/2pk1p2/1p4p1/1n6/1P2P3/1r1NKP2/8/8 w - - 0 35",
    "6k1/5n1p/r5p1/2R2p2/5N2/4PP1P/4K1P1/8 w - - 0 33",
    "4b3/8/6k1/3B1ppp/8/b5P1/P2B1P1P/6K1 w - - 0 28",
    "7b/3n3p/4k1p1/5p2/7P/4BB1K/8/8 b - - 0 42",
    "6k1/pb3pp1/1p5p/n2p3P/3P4/P1BBPP2/5KP1/8 b - - 0 25",
    "2n5/8/1p1pkp2/1b2p3/1N4P1/P2PBK2/8/8 w - - 0 39",
    "1r4k1/p4ppp/1p2n3/8/4N1P1/5P2/P5P1/1R4K1 w - - 0 24",
    "4r3/3k4/p2bpp2/P4p1p/2R2P2/1P4PP/2PBK3/8 b - - 0 30",
    "5r2/pp1b3p/3k1pp1/3p4/3N3P/P1RK1PP1/1P6/8 b - - 0 25",
    "7r/p1r2k2/1p3p2/3p1Bp1/3B4/P2PPPPP/1P2K3/8 w - - 0 35",
    "8/2r4p/6p1/pB6/1b4P1/1k2RK2/6P1/8 b - - 0 36",
    "4R3/2p3b1/2k3r1/8/1P6/2PKP3/8/8 w - - 0 45",
    "1bB5/4k2p/6p1/5p2/4n2P/8/5BK1/8 b - - 0 42",
    "1r4k1/R4p2/5P1p/1p5p/1PpB2b1/2P5/6PP/6K1 w - - 0 35",
    "1k2n3/2p3r1/1p6/p7/P3p1p1/6P1/4PKNP/4R3 b - - 0 37",
    "3k1r2/8/1p1r1p2/p2p1Bp1/8/2BPP1PP/PP3P2/3K4 b - - 0 32",
    "8/1p1k4/p3np2/3pbN2/PP6/3PB3/3K4/8 b - - 0 49",
    "1r5r/p5k1/1p3p2/3p1Bp1/8/P1BPP1PP/1P3P2/3K4 b - - 0 35",
    "8/5pk1/6pn/7p/1R3R1P/3r1PPK/8/8 w - - 0 37",
    "8/4k3/p3p3/2Q5/P7/3K4/2P3P1/q7 b - - 0 34",
    "3r1k2/5p1p/4n1p1/3p4/1R1P3P/5BP1/1P3PK1/8 b - - 0 28",
    "7r/2p5/3b2p1/1p1k1p2/pP3P2/P1KPB1RP/8/8 b - - 0 47",
    "3r4/3kbp2/4p1p1/4P3/2P4p/2K1BN1P/5PP1/8 b - - 0 50",

    "r3r2k/pp3Bp1/5n2/5b2/1B2q3/P2R4/2Q2PPP/5RK1 w - - 0 1",
    "r2q3r/pppkbppp/3p1n2/8/2Q1P3/2N1B2P/PP3PP1/R4RK1 w - - 0 1",
    "r4rk1/p1p2ppp/2p5/2bb4/7q/2PQ4/PP3PPP/RNB1R1K1 w - - 0 1",
    "8/q5pk/p7/1p1pP3/5r1P/NpP5/1P2B3/1K6 w - - 0 5",
    "3r4/6R1/8/2N1p2p/1p6/5kP1/7K/8 w - - 0 1",
    "r6k/pp2npp1/4b3/R2p4/8/1P6/2r3PP/2B2R1K w - - 0 3",
    "r2q1rk1/pp1nbppp/2n1p3/1B1p1b2/3P1B2/1QN1PN2/PP3PPP/R4RK1 w - - 0 1",
    "r1bqk2r/pp4pp/2p3n1/2bPp3/4Pp2/3B1N2/P2B1PPP/R2QK2R w KQkq - 0 1",
    "8/pp3Qpk/2p5/3p3K/8/5PP1/PqP5/8 w - - 0 1",
    "1R6/5kp1/4p2p/8/4q3/5N1P/5PP1/6K1 b - - 0 1",
    "5k2/5ppp/5n2/4b3/pP6/2p5/4BPPP/3R2K1 w - - 0 1",
    "r5k1/1p4bp/p5p1/q1pP1N2/P1P5/3b3P/1P4PB/4R1K1 w - - 0 1",
    "3r1b2/2N2p2/5Ppp/2p1P1P1/2P3RP/p7/2K5/4k2b w - - 0 1",
    "r1b2rk1/pp3ppp/1b1p4/2pPp3/4Pn1q/2P1N2P/PPB2PP1/R1BQR1K1 w - - 0 2",
    "2R2b2/5pk1/7p/3B2p1/1p6/2p2P2/5K1P/r7 b - - 0 1",
    "r1bqk1r1/pp1n1pp1/2p1p2p/4P2P/2PP4/2N2B2/PP1Q1P2/1K1R2R1 w q - 0 1",
    "1r2k1nr/p4ppp/2p1p3/2b5/Q1BnP2q/2N1K3/PP3P1P/R1BR4 b - - 1 1",
    "4r1k1/pp3pb1/5np1/3p1b1p/3P1B2/2P2N1P/PQ1N1PP1/R5K1 b - - 0 3",
    "8/8/3kp1p1/2p1p1P1/1p2Pp2/5K2/8/8 w - - 0 1",
    "2k1r3/2p4p/p5p1/5p2/8/2P4P/P2B1PP1/3R2K1 b - - 0 1",
    "2kr4/ppp1n3/3p1np1/4p1R1/2P1P3/2P4P/PPKN1b2/8 w - - 0 3",
    "1n3rk1/6pp/2p1pq2/3nN3/3P1P2/1B6/1P2Q1PP/r1B1R1K1 w - - 0 1",
    "r1bq1rk1/pppn2pp/5b2/8/PPPN1p2/3Pn3/1B1NQKPP/R4B1R b - - 0 1",
    "1r3b1r/2pk1p1p/p2p3p/4p3/4b3/2P4P/P3NPP1/RN2KB1R w KQ - 0 3",
    "8/2p5/1p1p2B1/p2P1PkP/2P5/1P3K2/P7/8 b - - 0 1",
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
