const std = @import("std");
const Step = std.Build.Step;
const JudgeCase = @This();

const base_id: Step.Id = .custom;

step: Step,
path: []const u8,
bin_path: []const u8,
tests: []const u8,
kcov: ?[]const u8,

pub fn create(owner: *std.Build, path: []const u8, bin_path: []const u8, tests: []const u8, kcov: ?[]const u8) !*JudgeCase {
    const self = try owner.allocator.create(JudgeCase);
    self.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = "JudgeCase",
            .owner = owner,
            .makeFn = make,
        }),
        .path = owner.dupe(path),
        .bin_path = owner.dupe(bin_path),
        .tests = owner.dupe(tests),
        .kcov = if (kcov) |k| owner.dupe(k) else null,
    };
    return self;
}

fn openFile(self: *JudgeCase, allocator: std.mem.Allocator, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ self.tests, self.path, name });
    defer allocator.free(path);
    return try std.fs.cwd().openFile(path, .{});
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;
    var timer = try std.time.Timer.start();
    defer step.result_duration_ns = timer.read();

    const b = step.owner;
    const self = @fieldParentPtr(JudgeCase, "step", step);

    var argv: std.ArrayListUnmanaged([]const u8) = .{};
    defer argv.deinit(b.allocator);
    if (self.kcov) |coverage| {
        try argv.append(b.allocator, "kcov");
        try argv.append(b.allocator, "--exclude-path=/opt,/usr");
        const path = try std.fs.path.join(b.allocator, &.{ coverage, self.path });
        try std.fs.cwd().makePath(path);
        try argv.append(b.allocator, path);
    }

    try argv.append(b.allocator, self.bin_path);

    const files = [_]std.fs.File{
        try self.openFile(b.allocator, "in"),
        try self.openFile(b.allocator, "out"),
    };

    defer files[0].close();
    defer files[1].close();

    var child = std.process.Child.init(argv.items, b.allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;

    child.request_resource_usage_statistics = true;
    defer step.result_peak_rss = child.resource_usage_statistics.getMaxRss() orelse 0;

    try child.spawn();
    const POLL = std.os.POLL;

    var poll_fds: [2]std.os.pollfd = .{
        .{
            .fd = child.stdin.?.handle,
            .events = POLL.OUT,
            .revents = undefined,
        },
        .{
            .fd = child.stdout.?.handle,
            .events = POLL.IN,
            .revents = undefined,
        },
    };

    var wrong = false;
    var keep_polling = true;
    const err_mask = POLL.ERR | POLL.NVAL | POLL.HUP;
    var stdin_buf: [4096]u8 = undefined;
    var stdin_pos: usize = stdin_buf.len;
    var stdin_size: usize = stdin_buf.len;

    while (keep_polling) {
        const poll_len = try std.os.poll(&poll_fds, std.math.maxInt(i32));
        if (poll_len == 0) {
            for (poll_fds) |poll_fd| {
                if (poll_fd.fd != -1)
                    continue;
            }
            break;
        }

        keep_polling = false;
        inline for (&poll_fds, &files) |*poll_fd, *file| {
            if ((poll_fd.revents & poll_fd.events) > 0) {
                if (poll_fd.events == POLL.OUT) {
                    if (stdin_pos < stdin_size) {
                        stdin_pos = stdin_pos + try std.os.write(poll_fd.fd, (&stdin_buf)[stdin_pos..]);
                    }

                    while ((stdin_pos >= stdin_size) and (stdin_size >= stdin_buf.len)) {
                        stdin_size = try file.readAll(&stdin_buf);
                        stdin_pos = try std.os.write(poll_fd.fd, &stdin_buf);
                    }

                    if ((stdin_pos >= stdin_size) and (stdin_size < stdin_buf.len)) {
                        poll_fd.fd = -1;
                        child.stdin.?.close();
                        child.stdin = null;
                    }
                } else {
                    while (true) {
                        var buf: [4096]u8 = undefined;
                        const len = try std.os.read(poll_fd.fd, &buf);
                        var exp_buf: [4096]u8 = undefined;
                        const exp_len = try file.readAll((&exp_buf)[0..len]);

                        if (!std.mem.eql(u8, buf[0..len], exp_buf[0..exp_len])) {
                            poll_fd.fd = -1;
                            child.stdout.?.close();
                            child.stdout = null;
                            wrong = true;
                            break;
                        }

                        if (len < buf.len)
                            break;
                    }
                }
            } else if ((poll_fd.revents & err_mask) != 0) {
                poll_fd.fd = -1;
            }

            if (poll_fd.fd != -1) {
                keep_polling = true;
            }
        }
    }

    if (!wrong) {
        var buf: [1]u8 = undefined;
        const len = try files[1].readAll(&buf);
        if (len > 0)
            wrong = true;
    }

    const term = try child.wait();
    try std.testing.expect(!wrong);
    try step.handleChildProcessTerm(term, null, argv.items);
}
