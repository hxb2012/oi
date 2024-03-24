pub const io = @import("io.zig");

pub const printf = io.printf;

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
