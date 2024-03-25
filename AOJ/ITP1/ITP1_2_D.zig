const oi = @import("oi");

pub fn main() !void {
    var w: i64 = undefined;
    var h: i64 = undefined;
    var x: i64 = undefined;
    var y: i64 = undefined;
    var r: i64 = undefined;
    _ = oi.scanf("{} {} {} {} {}", .{ &w, &h, &x, &y, &r });
    _ = oi.printf("{s}\n", .{if ((r <= x) and (x <= (w - r)) and (r <= y) and (y <= (h - r))) "Yes" else "No"});
}
