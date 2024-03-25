const oi = @import("oi");

pub fn main() !void {
    var a: i64 = undefined;
    var b: i64 = undefined;
    _ = oi.scanf("{} {}", .{ &a, &b });
    _ = oi.printf("a {s} b\n", .{switch (oi.order(a, b)) {
        .lt => "<",
        .eq => "==",
        .gt => ">",
    }});
}
