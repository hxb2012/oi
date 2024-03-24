pub const io = @import("io.zig");

pub const printf = io.printf;
pub const scanf = io.scanf;

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
