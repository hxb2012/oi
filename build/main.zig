const std = @import("std");

fn findLibDir(allocator: std.mem.Allocator, zig_exe: []const u8) !std.fs.Dir {
    const argv = [_][]const u8{ zig_exe, "env" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = std.ArrayList(u8).init(allocator);
    defer stdout.deinit();
    var stderr = std.ArrayList(u8).init(allocator);
    defer stderr.deinit();

    try child.spawn();
    try child.collectOutput(&stdout, &stderr, 1024);
    const term = try child.wait();

    try std.testing.expectEqual(term.Exited, 0);
    const Env = struct {
        lib_dir: []const u8,
    };
    const env = try std.json.parseFromSlice(Env, allocator, stdout.items, .{ .ignore_unknown_fields = true });
    defer env.deinit();

    return std.fs.openDirAbsolute(env.value.lib_dir, .{});
}

fn patchBuildRunner(allocator: std.mem.Allocator) !void {
    const argv = [_][]const u8{ "patch", "-t", "build_runner.zig.orig", "build_runner.diff" };
    var child = std.process.Child.init(&argv, allocator);
    const term = try child.spawnAndWait();
    try std.testing.expectEqual(term.Exited, 0);
}

fn fileExists(dir: std.fs.Dir, path: []const u8) !bool {
    const file = dir.openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    file.close();
    return true;
}

fn ensureZigBuildRunner(allocator: std.mem.Allocator, zig_exe: []const u8) !void {
    const cwd = std.fs.cwd();
    if (try fileExists(cwd, "build_runner.zig"))
        return;
    std.log.debug("build_runner.zig not found", .{});
    std.log.debug("run zig env to find lib_dir", .{});
    var lib_dir = try findLibDir(allocator, zig_exe);
    defer lib_dir.close();
    std.log.debug("copy build_runner.zig.orig from lib_dir", .{});
    try lib_dir.copyFile("build_runner.zig", cwd, "build_runner.zig.orig", .{});
    std.log.debug("patch build_runner.zig.orig", .{});
    try patchBuildRunner(allocator);
    std.log.debug("rename build_runner.zig.orig to build_runner.zig", .{});
    try cwd.rename("build_runner.zig.orig", "build_runner.zig");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const zig_exe = std.os.getenv("ZIG_EXE").?;
    try ensureZigBuildRunner(allocator, zig_exe);

    const command = [_][]const u8{ zig_exe, "build" };
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.appendSlice(&command);
    try argv.appendSlice(args[1..]);

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    try env.put("ZIG_BUILD_RUNNER", "build_runner.zig");

    var child = std.process.Child.init(argv.items, allocator);
    child.env_map = &env;
    const term = try child.spawnAndWait();
    try std.testing.expectEqual(term.Exited, 0);
}
