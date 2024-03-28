const oi = @import("oi");

pub fn main() !void {
    while (true) {
        var x: u64 = undefined;
        var y: u64 = undefined;
        _ = oi.scanf("{} {}", .{ &x, &y });
        if ((x == 0) and (y == 0))
            break;
        _ = oi.printf("{} {}\n", .{ @min(x, y), @max(x, y) });
    }
}
