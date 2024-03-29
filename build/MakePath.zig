const std = @import("std");
const Step = std.Build.Step;
const MakePath = @This();

const base_id: Step.Id = .custom;

step: Step,
dir_path: []const u8,

pub fn create(owner: *std.Build, dir_path: []const u8) !*MakePath {
    const self = try owner.allocator.create(MakePath);
    self.* = MakePath{
        .step = Step.init(.{
            .id = base_id,
            .name = owner.fmt("MakePath {s}", .{dir_path}),
            .owner = owner,
            .makeFn = make,
        }),
        .dir_path = owner.dupePath(dir_path),
    };
    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    const b = step.owner;
    const self = @fieldParentPtr(MakePath, "step", step);

    try b.build_root.handle.makePath(self.dir_path);
}
