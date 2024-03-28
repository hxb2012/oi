const std = @import("std");
const Step = @import("Pool.zig").Step;
const FetchTestCases = @This();

pub const CreateFn = *const fn (owner: *std.Build, path: []const u8, temp_path: []const u8) anyerror!*Step;

const base_id: Step.Id = .custom;

step: Step,
tests: []const u8,
path: []const u8,
temp_path: ?[]const u8,
createFn: CreateFn,

pub fn create(owner: *std.Build, tests: []const u8, path: []const u8, createFn: CreateFn) !*FetchTestCases {
    const self = try owner.allocator.create(FetchTestCases);
    try self.step.initAllocated(owner, owner.fmt("Fetch Testcases of {s}", .{path}));
    self.step.startFn = start;
    self.step.checkFn = check;
    self.tests = owner.dupe(tests);
    self.path = owner.dupe(path);
    self.temp_path = null;
    self.createFn = createFn;
    return self;
}

fn check(step: *Step, node: *std.Progress.Node) !void {
    _ = node;
    const self = @fieldParentPtr(FetchTestCases, "step", step);
    var tests = try std.fs.cwd().makeOpenPath(self.tests, .{});
    defer tests.close();
    const dirname = std.fs.path.dirname(self.path).?;
    var dir = try tests.makeOpenPath(dirname, .{});
    defer dir.close();
    try dir.rename(self.temp_path.?, std.fs.path.basename(self.path));
}

fn start(step: *Step, node: *std.Progress.Node) !void {
    _ = node;
    const self = @fieldParentPtr(FetchTestCases, "step", step);
    const b = step.step.owner;
    const temp_path = b.makeTempPath();
    self.temp_path = temp_path;

    const child = try self.createFn(b, self.path, temp_path);
    try step.addChildStep(child);
}
