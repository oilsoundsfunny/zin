const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const arch = @import("arch.zig");
const Network = @import("Network.zig");
const root = @import("root.zig");

const Accumulator = @This();

perspectives: std.EnumArray(types.Color, Vec) = .initFill(Network.verbatim.l0b),
mirrored: std.EnumArray(types.Color, bool) = .initFill(false),

dirty: bool = false,
hm_q: ?types.Color = null,
add_q: types.BoundedArray(Dirty, null, 2) = .{},
sub_q: types.BoundedArray(Dirty, null, 2) = .{},

pub const Half = @Vector(arch.hl0_len / 2, arch.Int);
pub const Vec = @Vector(arch.hl0_len, arch.Int);

pub const Dirty = struct {
    piece: types.Piece,
    square: types.Square,
};

fn indices(
    self: *const Accumulator,
    s: types.Square,
    p: types.Piece,
) std.EnumArray(types.Color, usize) {
    var ret: std.EnumArray(types.Color, usize) = .initUndefined();
    inline for (types.Color.values) |c| {
        const mirrored = self.mirrored.get(c);
        const kingsided = if (mirrored) s.flipFile() else s;
        const pov = switch (c) {
            .white => kingsided,
            .black => kingsided.flipRank(),
        };

        const ci: usize = if (p.color() == c) 0 else arch.ptype_n;
        const pi: usize = p.ptype().int();
        const si: usize = pov.int();
        ret.set(c, (ci + pi) * arch.square_n + si);
    }
    return ret;
}

fn fusedSubAdd(self: *Accumulator, c: types.Color) void {
    const sub_m = self.sub_q.constSlice()[0];
    const add_m = self.add_q.constSlice()[0];

    const sub_i = self.indices(sub_m.square, sub_m.piece).get(c);
    const add_i = self.indices(add_m.square, add_m.piece).get(c);

    const v: *align(64) [arch.hl0_len]arch.Int = @alignCast(self.perspectives.getPtr(c));
    var i: usize = 0;
    while (i < arch.hl0_len) : (i += arch.native_len) {
        const vec: *arch.Native = @alignCast(v[i..][0..arch.native_len]);
        var load = vec.*;
        defer vec.* = load;

        const sub_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[sub_i][i..][0..arch.native_len]);
        const add_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[add_i][i..][0..arch.native_len]);

        load -%= sub_w.*;
        load +%= add_w.*;
    }
}

fn fusedSubAddSub(self: *Accumulator, c: types.Color) void {
    const sub0 = self.sub_q.constSlice()[0];
    const add0 = self.add_q.constSlice()[0];
    const sub1 = self.sub_q.constSlice()[1];

    const sub0_i = self.indices(sub0.square, sub0.piece).get(c);
    const add0_i = self.indices(add0.square, add0.piece).get(c);
    const sub1_i = self.indices(sub1.square, sub1.piece).get(c);

    const v: *align(64) [arch.hl0_len]arch.Int = @alignCast(self.perspectives.getPtr(c));
    var i: usize = 0;
    while (i < arch.hl0_len) : (i += arch.native_len) {
        const vec: *arch.Native = @alignCast(v[i..][0..arch.native_len]);
        var load = vec.*;
        defer vec.* = load;

        const sub0_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[sub0_i][i..][0..arch.native_len]);
        const add0_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[add0_i][i..][0..arch.native_len]);
        const sub1_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[sub1_i][i..][0..arch.native_len]);

        load -%= sub0_w.*;
        load +%= add0_w.*;
        load -%= sub1_w.*;
    }
}

fn fusedSubAddSubAdd(self: *Accumulator, c: types.Color) void {
    const sub0 = self.sub_q.constSlice()[0];
    const add0 = self.add_q.constSlice()[0];
    const sub1 = self.sub_q.constSlice()[1];
    const add1 = self.add_q.constSlice()[1];

    const sub0_i = self.indices(sub0.square, sub0.piece).get(c);
    const add0_i = self.indices(add0.square, add0.piece).get(c);
    const sub1_i = self.indices(sub1.square, sub1.piece).get(c);
    const add1_i = self.indices(add1.square, add1.piece).get(c);

    const v: *align(64) [arch.hl0_len]arch.Int = @alignCast(self.perspectives.getPtr(c));
    var i: usize = 0;
    while (i < arch.hl0_len) : (i += arch.native_len) {
        const vec: *arch.Native = @alignCast(v[i..][0..arch.native_len]);
        var load = vec.*;
        defer vec.* = load;

        const sub0_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[sub0_i][i..][0..arch.native_len]);
        const add0_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[add0_i][i..][0..arch.native_len]);
        const sub1_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[sub1_i][i..][0..arch.native_len]);
        const add1_w: *const arch.Native =
            @alignCast(Network.verbatim.l0w[add1_i][i..][0..arch.native_len]);

        load -%= sub0_w.*;
        load +%= add0_w.*;
        load -%= sub1_w.*;
        load +%= add1_w.*;
    }
}

fn queueAdd(self: *Accumulator, dirty: Dirty) void {
    self.add_q.pushUnchecked(dirty);
}

fn queueSub(self: *Accumulator, dirty: Dirty) void {
    self.sub_q.pushUnchecked(dirty);
}

fn queuePanic() noreturn {
    @branchHint(.cold);
    @panic("invalid queue length");
}

pub fn queueSubAdd(self: *Accumulator, sub_m: Dirty, add_m: Dirty) void {
    self.queueSub(sub_m);
    self.queueAdd(add_m);
}

pub fn queueSubAddSub(self: *Accumulator, sub0: Dirty, add0: Dirty, sub1: Dirty) void {
    self.queueSub(sub0);
    self.queueAdd(add0);
    self.queueSub(sub1);
}

pub fn queueSubAddSubAdd(
    self: *Accumulator,
    sub0: Dirty,
    add0: Dirty,
    sub1: Dirty,
    add1: Dirty,
) void {
    self.queueSub(sub0);
    self.queueAdd(add0);
    self.queueSub(sub1);
    self.queueAdd(add1);
}

pub fn queueMirror(self: *Accumulator, c: types.Color) void {
    self.hm_q = c;
}

pub fn clear(self: *Accumulator) void {
    self.hm_q = null;
    self.add_q.resize(0) catch unreachable;
    self.sub_q.resize(0) catch unreachable;
}

pub fn mark(self: *Accumulator) void {
    self.dirty = true;
}

pub fn unmark(self: *Accumulator) void {
    self.dirty = false;
}

pub fn update(
    self: *Accumulator,
    last: *const Accumulator,
    pos: *const engine.Board.Position,
) void {
    defer self.clear();
    defer self.unmark();

    self.perspectives = last.perspectives;
    self.mirrored = last.mirrored;

    const add_n = self.add_q.constSlice().len;
    const sub_n = self.sub_q.constSlice().len;

    const Fused = *const fn (*Accumulator, types.Color) void;
    const fused: Fused = sw: switch (add_n) {
        0 => return,
        1 => switch (sub_n) {
            1 => fusedSubAdd,
            2 => fusedSubAddSub,
            else => continue :sw 0,
        },
        2 => switch (sub_n) {
            2 => fusedSubAddSubAdd,
            else => continue :sw 0,
        },
        else => continue :sw 0,
    };

    if (self.hm_q) |c| {
        self.mirror(c, pos);
        fused(self, c.flip());
    } else {
        fused(self, .white);
        fused(self, .black);
    }
}

pub fn add(self: *Accumulator, c: types.Color, dirty: Dirty) void {
    const i = self.indices(dirty.square, dirty.piece).get(c);
    const w: *align(64) const [arch.hl0_len]arch.Int = Network.verbatim.l0w[i][0..];
    const v: *align(64) [arch.hl0_len]arch.Int = @alignCast(self.perspectives.getPtr(c));

    var k: usize = 0;
    while (k < arch.hl0_len) : (k += arch.native_len) {
        const vec: *arch.Native = @alignCast(v[k..][0..arch.native_len]);
        const wgt: *const arch.Native = @alignCast(w[k..][0..arch.native_len]);
        vec.* +%= wgt.*;
    }
}

pub fn sub(self: *Accumulator, c: types.Color, dirty: Dirty) void {
    const i = self.indices(dirty.square, dirty.piece).get(c);
    const w: *align(64) const [arch.hl0_len]arch.Int = Network.verbatim.l0w[i][0..];
    const v: *align(64) [arch.hl0_len]arch.Int = @alignCast(self.perspectives.getPtr(c));

    var k: usize = 0;
    while (k < arch.hl0_len) : (k += arch.native_len) {
        const vec: *arch.Native = @alignCast(v[k..][0..arch.native_len]);
        const wgt: *const arch.Native = @alignCast(w[k..][0..arch.native_len]);
        vec.* -%= wgt.*;
    }
}

pub fn mirror(self: *Accumulator, c: types.Color, pos: *const engine.Board.Position) void {
    const mirrored = self.mirrored.getPtr(c);
    mirrored.* = !mirrored.*;

    self.perspectives.set(c, Network.verbatim.l0b);
    for (types.Piece.w_pieces ++ types.Piece.b_pieces) |p| {
        var pieces = pos.pieceOcc(p);
        while (pieces.lowSquare()) |s| : (pieces.popLow()) {
            self.add(c, .{ .piece = p, .square = s });
        }
    }
}
