const oi = @import("oi");

pub fn main() !void {
    for (0..1000) |_|
        _ = oi.printf("Hello World\n", .{});
}
