const oi = @import("oi");

pub fn main() !void {
    var i: u64 = 0;

    while (true) {
        var x: u64 = undefined;
        _ = oi.scanf("{d}", .{&x});
        if (x == 0)
            break;
        i = i + 1;
        _ = oi.printf("Case {d}: {d}\n", .{ i, x });
    }
}
