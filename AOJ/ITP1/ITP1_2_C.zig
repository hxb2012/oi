const oi = @import("oi");

pub fn main() !void {
    var a: u64 = undefined;
    var b: u64 = undefined;
    var c: u64 = undefined;
    _ = oi.scanf("{} {} {}", .{ &a, &b, &c });
    _ = oi.printf("{} {} {}\n", .{ @min(@min(a, b), c), @max(@max(@min(a, b), @min(b, c)), @min(a, c)), @max(@max(a, b), c) });
}
