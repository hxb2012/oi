pub const oi = @import("src/main.zig");

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
