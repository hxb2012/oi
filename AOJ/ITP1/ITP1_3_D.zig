const oi = @import("oi");

pub fn main() !void {
    var a: u64 = undefined;
    var b: u64 = undefined;
    var c: u64 = undefined;

    _ = oi.scanf("{d} {d} {d}", .{ &a, &b, &c });

    var n: u64 = 0;
    for (a..b + 1) |i| {
        if (c % i == 0)
            n = n + 1;
    }

    _ = oi.printf("{d}\n", .{n});
}
