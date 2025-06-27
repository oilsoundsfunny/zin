const misc = @import("misc");
const std = @import("std");

psq:	std.EnumArray(misc.types.Square, std.EnumArray(misc.types.Piece, Int)),
cas:	std.EnumArray(misc.types.Castle, Int),
enp:	std.EnumArray(misc.types.File, Int),
stm:	Int,

pub const Int = misc.types.BitBoard.Int;
