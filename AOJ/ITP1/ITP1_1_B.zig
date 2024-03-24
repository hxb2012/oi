const oi = @import("oi");

pub fn main() !void {
    var x: u64 = undefined;
    _ = oi.scanf("{}", .{&x});
    const cube = x * x * x;
    _ = oi.printf("{}\n", .{cube});
}
