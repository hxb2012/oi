const std = @import("std");
const Step = std.Build.Step;

const base_id: Step.Id = .custom;

pub fn init(owner: *std.Build, name: []const u8) Step {
    return Step.init(.{
        .id = base_id,
        .name = name,
        .owner = owner,
        .makeFn = make,
    });
}

pub fn create(owner: *std.Build, name: []const u8) *Step {
    const self = owner.allocator.create(Step) catch @panic("OOM");
    self.* = init(owner, name);
    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = step;
    _ = prog_node;
}
