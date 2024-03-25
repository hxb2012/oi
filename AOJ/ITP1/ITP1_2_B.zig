const oi = @import("oi");

pub fn main() !void {
    var a: u64 = undefined;
    var b: u64 = undefined;
    var c: u64 = undefined;
    _ = oi.scanf("{} {} {}", .{ &a, &b, &c });
    _ = oi.printf("{s}\n", .{if ((a < b) and (b < c)) "Yes" else "No"});
}
