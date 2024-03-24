const oi = @import("oi");

pub fn main() !void {
    var t: u64 = undefined;
    _ = oi.scanf("{}", .{&t});
    const s = t % 60;
    var m = t / 60;
    const h = m / 60;
    m = m % 60;
    _ = oi.printf("{}:{}:{}\n", .{ h, m, s });
}
