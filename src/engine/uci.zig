const params = @import("params");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const movegen = @import("movegen.zig");
const Thread = @import("Thread.zig");
const transposition = @import("transposition.zig");

const Command = enum {
    debug,
    go,
    isready,
    none,
    position,
    quit,
    setoption,
    spsa_inputs,
    stop,
    uci,
    ucinewgame,
};

pub const Error = error{
    UnknownCommand,
};

fn parseGo(tokens: *std.mem.TokenIterator(u8, .any), pool: *Thread.Pool) !Command {
    const pos = pool.threads.items[0].board.positions.last();
    const stm = pos.stm;

    const limits = &pool.limits;
    const timer = &pool.timer;

    limits.* = .{};
    timer.reset();

    while (tokens.next()) |token| {
        if (std.mem.eql(u8, token, "infinite")) {
            if (tokens.peek()) |_| {
                return error.UnknownCommand;
            }

            limits.* = .{};
            continue;
        }

        const aux = tokens.next() orelse return error.UnknownCommand;
        if (std.mem.eql(u8, token, "depth")) {
            limits.depth = std.fmt.parseUnsigned(u8, aux, 10) catch
                return error.UnknownCommand;
        } else if (std.mem.eql(u8, token, "movetime")) {
            limits.movetime = std.fmt.parseUnsigned(u64, aux, 10) catch
                return error.UnknownCommand;
        } else if (std.mem.eql(u8, token, "nodes")) {
            limits.hard_nodes = std.fmt.parseUnsigned(u64, aux, 10) catch
                return error.UnknownCommand;
        } else if (std.mem.eql(u8, token, "winc")) {
            limits.incr.put(.white, std.fmt.parseUnsigned(u64, aux, 10) catch
                return error.UnknownCommand);
        } else if (std.mem.eql(u8, token, "wtime")) {
            limits.time.put(.white, std.fmt.parseUnsigned(u64, aux, 10) catch
                return error.UnknownCommand);
        } else if (std.mem.eql(u8, token, "binc")) {
            limits.incr.put(.black, std.fmt.parseUnsigned(u64, aux, 10) catch
                return error.UnknownCommand);
        } else if (std.mem.eql(u8, token, "btime")) {
            limits.time.put(.black, std.fmt.parseUnsigned(u64, aux, 10) catch
                return error.UnknownCommand);
        } else return error.UnknownCommand;
    }

    limits.set(pool.opts.overhead, stm);
    pool.search();
    return .go;
}

fn parseOption(tokens: *std.mem.TokenIterator(u8, .any), pool: *Thread.Pool) !Command {
    const options = &pool.opts;
    const backup = options.*;
    errdefer options.* = backup;

    const first = tokens.next() orelse return error.UnknownCommand;
    if (!std.mem.eql(u8, first, "name")) {
        return error.UnknownCommand;
    }

    const name = tokens.next() orelse return error.UnknownCommand;
    const aux = tokens.next() orelse return error.UnknownCommand;
    if (std.ascii.eqlIgnoreCase(name, "Clear")) {
        if (!std.ascii.eqlIgnoreCase(aux, "Hash")) {
            return error.UnknownCommand;
        } else if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        pool.clearHash();
    } else if (std.ascii.eqlIgnoreCase(name, "Hash")) {
        if (!std.mem.eql(u8, aux, "value")) {
            return error.UnknownCommand;
        }

        const value = tokens.next() orelse return error.UnknownCommand;
        options.hash = std.fmt.parseUnsigned(usize, value, 10) catch return error.UnknownCommand;

        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        try pool.tt.realloc(pool.allocator, options.hash);
    } else if (std.ascii.eqlIgnoreCase(name, "Move")) {
        if (!std.mem.eql(u8, aux, "Overhead")) {
            return error.UnknownCommand;
        }

        const aux1 = tokens.next() orelse return error.UnknownCommand;
        if (!std.mem.eql(u8, aux1, "value")) {
            return error.UnknownCommand;
        }

        const value = tokens.next() orelse return error.UnknownCommand;
        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        options.overhead = std.fmt.parseUnsigned(usize, value, 10) catch
            return error.UnknownCommand;
    } else if (std.ascii.eqlIgnoreCase(name, "Threads")) {
        if (!std.mem.eql(u8, aux, "value")) {
            return error.UnknownCommand;
        }

        const value = tokens.next() orelse return error.UnknownCommand;
        options.threads = std.fmt.parseUnsigned(usize, value, 10) catch return error.UnknownCommand;

        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        try pool.realloc(options.threads);
    } else if (std.ascii.eqlIgnoreCase(name, "UCI_Chess960")) {
        if (!std.mem.eql(u8, aux, "value")) {
            return error.UnknownCommand;
        }

        const value = tokens.next() orelse return error.UnknownCommand;
        const frc = if (std.mem.eql(u8, value, "false"))
            false
        else if (std.mem.eql(u8, value, "true"))
            true
        else
            return error.UnknownCommand;

        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        pool.setFRC(frc);
    } else if (std.ascii.eqlIgnoreCase(name, "UCI_ShowWDL")) {
        if (!std.mem.eql(u8, aux, "value")) {
            return error.UnknownCommand;
        }

        const value = tokens.next() orelse return error.UnknownCommand;
        const show_wdl = if (std.mem.eql(u8, value, "false"))
            false
        else if (std.mem.eql(u8, value, "true"))
            true
        else
            return error.UnknownCommand;

        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        options.show_wdl = show_wdl;
    } else if (!params.tuning) {
        return error.UnknownCommand;
    } else params.parseTunable(name, aux, tokens) catch |err| return err;

    return .setoption;
}

fn parsePosition(tokens: *std.mem.TokenIterator(u8, .any), pool: *Thread.Pool) !Command {
    var board: Board = .{};
    const frc = pool.threads.items[0].board.frc;

    defer pool.setBoard(&board, frc);
    errdefer {
        board = .{};
        board.parseFen(Board.Position.startpos) catch std.debug.panic("invalid startpos", .{});
    }

    const first = tokens.next() orelse return error.UnknownCommand;
    if (std.mem.eql(u8, first, "fen")) {
        board.parseFenTokens(tokens) catch return error.UnknownCommand;
    } else if (std.mem.eql(u8, first, "kiwipete")) {
        board.parseFen(Board.Position.kiwipete) catch return error.UnknownCommand;
    } else if (std.mem.eql(u8, first, "startpos")) {
        board.parseFen(Board.Position.startpos) catch return error.UnknownCommand;
    } else return error.UnknownCommand;

    const aux = tokens.next() orelse return .position;
    if (!std.mem.eql(u8, aux, "moves")) {
        return error.UnknownCommand;
    }

    board.frc = frc;
    while (tokens.next()) |token| {
        var i: usize = 0;
        var n: usize = 0;
        var list: movegen.Move.Scored.List = .{};

        const pos = board.positions.last();
        n += list.genNoisy(pos);
        n += list.genQuiet(pos);
        while (i < n) : (i += 1) {
            const m = list.constSlice()[i].move;
            const s = m.toString(&board);
            const l = m.toStringLen();
            if (!std.mem.eql(u8, token, s[0..l]) or !pos.isMoveLegal(m)) {
                continue;
            }

            board.doMove(m);
            break;
        } else return error.UnknownCommand;
    } else return .position;
}

pub fn parseCommand(command: []const u8, pool: *Thread.Pool) !Command {
    var tokens = std.mem.tokenizeAny(u8, command, &std.ascii.whitespace);
    const first = tokens.next() orelse return error.UnknownCommand;

    if (std.mem.eql(u8, first, "debug")) {
        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        return .debug;
    } else if (std.mem.eql(u8, first, "go")) {
        return parseGo(&tokens, pool);
    } else if (std.mem.eql(u8, first, "isready")) {
        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        pool.mtx.lock();
        defer pool.mtx.unlock();

        try pool.io.writer().print("readyok\n", .{});
        try pool.io.writer().flush();

        return .isready;
    } else if (std.mem.eql(u8, first, "position")) {
        return parsePosition(&tokens, pool);
    } else if (std.mem.eql(u8, first, "quit") or std.mem.eql(u8, first, "stop")) {
        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        pool.stopSearch();
        return if (std.mem.eql(u8, first, "quit")) .quit else .stop;
    } else if (std.mem.eql(u8, first, "setoption")) {
        return parseOption(&tokens, pool);
    } else if (std.mem.eql(u8, first, "spsa_inputs")) {
        if (!params.tuning) {
            return error.UnknownCommand;
        }

        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        pool.mtx.lock();
        defer pool.mtx.unlock();

        try params.printValues(pool.io.writer());
        try pool.io.writer().flush();
        return .spsa_inputs;
    } else if (std.mem.eql(u8, first, "uci")) {
        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        pool.mtx.lock();
        defer pool.mtx.unlock();

        try pool.io.writer().print("id author {s}\n", .{@import("root").author});
        try pool.io.writer().print("id name {s}\n", .{@import("root").name});

        try pool.io.writer().print("option name {s} type {s}\n", .{ "Clear Hash", "button" });
        try pool.io.writer().print(
            "option name {s} type {s} default {d} min {d} max {d}\n",
            .{ "Hash", "spin", 64, 1, 1 << 30 },
        );
        try pool.io.writer().print(
            "option name {s} type {s} default {d} min {d} max {d}\n",
            .{ "Move Overhead", "spin", 10, 0, 5000 },
        );
        try pool.io.writer().print(
            "option name {s} type {s} default {d} min {d} max {d}\n",
            .{ "Threads", "spin", 1, 1, 256 },
        );
        try pool.io.writer().print(
            "option name {s} type {s} default {s}\n",
            .{ "UCI_Chess960", "check", "false" },
        );

        if (params.tuning) {
            try params.printOptions(pool.io.writer());
        }

        try pool.io.writer().print("uciok\n", .{});
        try pool.io.writer().flush();

        return .uci;
    } else if (std.mem.eql(u8, first, "ucinewgame")) {
        if (tokens.peek()) |_| {
            return error.UnknownCommand;
        }

        try pool.reset();
        return .ucinewgame;
    } else return error.UnknownCommand;
}

pub fn loop(pool: *Thread.Pool) !void {
    const reader = pool.io.reader();
    const writer = pool.io.writer();

    while (reader.takeDelimiterInclusive('\n')) |read| {
        const comm = parseCommand(read, pool) catch |err| sw: switch (err) {
            error.UnknownCommand => {
                try writer.print("Unknown command: '{s}'\n", .{read[0 .. read.len - 1]});
                try writer.flush();
                break :sw Command.none;
            },
            else => return err,
        };

        if (comm == .quit) {
            break;
        }
    } else |err| return err;
}
