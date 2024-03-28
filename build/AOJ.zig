const std = @import("std");
const curl = @import("curl.zig").curl;
const Step = @import("Pool.zig").Step;
const AOJ = @This();

const base_id: Step.Id = .custom;

step: Step,
path: []const u8,
temp_path: []const u8,

pub fn create(b: *std.Build, path: []const u8, temp_path: []const u8) !*Step {
    const self = try b.allocator.create(AOJ);
    const basename = std.fs.path.stem(path);
    try self.step.initAllocated(b, b.fmt("Fetch AOJ {s} Testcases", .{basename}));
    self.step.startFn = fetchList;
    self.path = b.dupe(path);
    self.temp_path = b.dupe(temp_path);
    return &self.step;
}

const Header = struct {
    serial: u64,
    name: []u8,
};

const Response = struct {
    headers: []Header,
};

const Case = struct {
    in: []const u8,
    out: []const u8,
};

const FetchCase = struct {
    step: Step,
    uri: []const u8,
    path: []const u8,

    pub fn create(b: *std.Build, path: []const u8, temp_path: []const u8, serial: u64, name: []const u8) !*Step {
        const self = try b.allocator.create(FetchCase);
        const basename = std.fs.path.stem(path);
        try self.step.initAllocated(b, b.fmt("Fetch AOJ {s} Testcase {s}", .{ basename, name }));
        self.uri = b.fmt("https://judgedat.u-aizu.ac.jp/testcases/{s}/{d}", .{ basename, serial });
        self.path = try std.fs.path.join(b.allocator, &[_][]const u8{ temp_path, name });
        self.step.startFn = fetch;
        return &self.step;
    }

    fn terminated(data: []const u8) bool {
        const marker = "..... (terminated because of the limitation)\n";
        if (data.len >= marker.len) {
            const tail = data[data.len - marker.len .. data.len];
            return std.mem.eql(u8, marker, tail);
        }
        return false;
    }

    fn fetch(step: *Step, node: *std.Progress.Node) !void {
        _ = node;
        const b = step.step.owner;
        const self = @fieldParentPtr(FetchCase, "step", step);

        const body = try curl(b.allocator, self.uri, 1048576);
        defer b.allocator.free(body);

        const case = try std.json.parseFromSlice(Case, b.allocator, body, .{ .ignore_unknown_fields = true });
        defer case.deinit();

        if (terminated(case.value.in))
            return;

        if (terminated(case.value.out))
            return;

        var dir = try std.fs.cwd().makeOpenPath(self.path, .{});
        defer dir.close();

        var infile = try dir.createFile("in", .{});
        defer infile.close();
        try infile.writeAll(case.value.in);

        var outfile = try dir.createFile("out", .{});
        defer outfile.close();
        try outfile.writeAll(case.value.out);
    }
};

fn fetchList(step: *Step, node: *std.Progress.Node) !void {
    _ = node;
    const b = step.step.owner;
    const self = @fieldParentPtr(AOJ, "step", step);
    const basename = std.fs.path.stem(self.path);
    const uri = b.fmt("https://judgedat.u-aizu.ac.jp/testcases/{s}/header", .{basename});
    const body = try curl(b.allocator, uri, 1048576);
    defer b.allocator.free(body);

    const response = try std.json.parseFromSlice(Response, b.allocator, body, .{ .ignore_unknown_fields = true });
    defer response.deinit();

    for (response.value.headers) |header| {
        const child = try FetchCase.create(b, self.path, self.temp_path, header.serial, header.name);
        try step.addChildStep(child);
    }
}
