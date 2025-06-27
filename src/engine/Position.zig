const misc = @import("misc");
const std = @import("std");

mailbox:	std.EnumArray(misc.types.Square, misc.types.Piece),
piece_occ:	std.EnumArray(misc.types.Piece,  misc.types.BitBoard),
