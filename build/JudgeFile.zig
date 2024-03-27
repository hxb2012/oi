const std = @import("std");
const Step = std.Build.Step;
const JudgeFile = @This();

const base_id: Step.Id = .custom;

step: Step,
add_step: Step,
path: []const u8,
bin_path: std.Build.LazyPath,
kcov: ?[]const u8,

pub fn create(owner: *std.Build, path: []const u8, bin_path: std.Build.LazyPath, kcov: ?[]const u8, fetch: *Step) !*JudgeFile {
    const self = try owner.allocator.create(JudgeFile);
    self.* = JudgeFile{
        .step = Step.init(.{ .id = base_id, .name = owner.fmt("Judge {s}", .{path}), .owner = owner }),
        .add_step = Step.init(.{ .id = base_id, .name = "Add cases", .owner = owner, .makeFn = make }),
        .path = owner.dupePath(path),
        .bin_path = bin_path.dupe(owner),
        .kcov = kcov,
    };

    bin_path.addStepDependencies(&self.add_step);
    self.step.dependOn(&self.add_step);
    self.add_step.dependOn(fetch);
    return self;
}

fn addJudgeCase(b: *std.Build, self: *JudgeFile, name: []const u8) !void {
    const judge = b.addSystemCommand(&.{ "python3", "oi.py", "judge" });
    if (self.kcov) |coverage| {
        judge.addArg("--kcov");
        judge.addArg(coverage);
    }
    judge.addArg(b.fmt("--bin={s}", .{self.bin_path.getPath(b)}));
    judge.addArg(self.path);
    judge.addArg(name);
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

    var tests = try std.fs.cwd().openDir("tests", .{});
    defer tests.close();

    var subdir = try tests.openDir(std.fs.path.dirname(self.path).?, .{});
    defer subdir.close();

    var dir = try subdir.openIterableDir(std.fs.path.stem(self.path), .{});
    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                try addJudgeCase(b, self, entry.name);
            },
            else => {},
        }
    }
}
