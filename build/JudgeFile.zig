const std = @import("std");
const Step = std.Build.Step;
const JudgeFile = @This();

const base_id: Step.Id = .custom;

step: Step,
add_step: Step,
tests: []const u8,
path: []const u8,
bin_path: std.Build.LazyPath,
kcov: ?[]const u8,

pub fn create(owner: *std.Build, path: []const u8, bin_path: std.Build.LazyPath, tests: []const u8, kcov: ?[]const u8, fetch: *Step) !*JudgeFile {
    const self = try owner.allocator.create(JudgeFile);
    self.* = JudgeFile{
        .step = Step.init(.{ .id = base_id, .name = owner.fmt("Judge {s}", .{path}), .owner = owner }),
        .add_step = Step.init(.{ .id = base_id, .name = "Add cases", .owner = owner, .makeFn = make }),
        .path = owner.dupePath(path),
        .bin_path = bin_path.dupe(owner),
        .tests = owner.dupe(tests),
        .kcov = if (kcov) |k| owner.dupe(k) else null,
    };

    bin_path.addStepDependencies(&self.add_step);
    self.step.dependOn(&self.add_step);
    self.add_step.dependOn(fetch);
    return self;
}

fn addJudgeCase(b: *std.Build, self: *JudgeFile, name: []const u8, path: []const u8) !void {
    const judge = b.addSystemCommand(&.{ "python3", "oi.py" });
    if (self.kcov) |coverage| {
        judge.addArg("--kcov");
        judge.addArg(coverage);
    }
    judge.addArg(b.fmt("--bin={s}", .{self.bin_path.getPath(b)}));
    judge.addArg(try std.fs.path.join(b.allocator, &.{ self.tests, path }));
    judge.step.name = b.fmt("Case {s}", .{name});
    judge.step.state = .precheck_done;

    self.step.dependOn(&judge.step);
    try judge.step.dependants.append(b.allocator, &self.step);
    try self.add_step.dependants.append(b.allocator, &judge.step);
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    const b = step.owner;
    const self = @fieldParentPtr(JudgeFile, "add_step", step);

    const sub_dir = std.fs.path.dirname(self.path).?;
    const basename = std.fs.path.stem(self.path);

    var tests = try std.fs.cwd().openDir(self.tests, .{});
    defer tests.close();

    var subdir = try tests.openDir(sub_dir, .{});
    defer subdir.close();

    var dir = try subdir.openIterableDir(basename, .{});
    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const path = try std.fs.path.join(b.allocator, &.{ sub_dir, basename, entry.name });
                try addJudgeCase(b, self, entry.name, path);
            },
            else => {},
        }
    }
}
