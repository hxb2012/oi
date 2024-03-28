const std = @import("std");

pub fn curl(allocator: std.mem.Allocator, url: []const u8, max_output_bytes: usize) ![]const u8 {
    const argv = [_][]const u8{ "curl", "-f", url };
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = std.ArrayList(u8).init(allocator);
    defer stdout.deinit();
    var stderr = std.ArrayList(u8).init(allocator);
    defer stderr.deinit();
    try child.spawn();
    try child.collectOutput(&stdout, &stderr, max_output_bytes);
    const term = try child.wait();
    try std.testing.expectEqual(term.Exited, 0);
    return stdout.toOwnedSlice();
}
