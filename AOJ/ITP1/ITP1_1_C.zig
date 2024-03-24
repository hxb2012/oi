const oi = @import("oi");

pub fn main() !void {
    var a: u64 = undefined;
    var b: u64 = undefined;
    _ = oi.scanf("{} {}", .{ &a, &b });
    const area = a * b;
    const perimeter = (a + b) * 2;
    _ = oi.printf("{} {}\n", .{ area, perimeter });
}
