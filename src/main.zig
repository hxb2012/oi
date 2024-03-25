const std = @import("std");
pub const order = std.math.order;

pub const io = @import("io.zig");
pub const printf = io.printf;
pub const scanf = io.scanf;

test {
    std.testing.refAllDecls(@This());
}
