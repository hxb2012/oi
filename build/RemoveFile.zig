const std = @import("std");
const Step = std.Build.Step;
const RemoveFile = @This();

const base_id: Step.Id = .custom;

step: Step,
file_path: []const u8,

pub fn create(owner: *std.Build, file_path: []const u8) *RemoveFile {
    const self = owner.allocator.create(RemoveFile) catch @panic("OOM");
    self.* = RemoveFile{
        .step = Step.init(.{
            .id = base_id,
            .name = owner.fmt("RemoveFile {s}", .{file_path}),
            .owner = owner,
            .makeFn = make,
        }),
        .file_path = owner.dupePath(file_path),
    };
    return self;
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    const b = step.owner;
    const self = @fieldParentPtr(RemoveFile, "step", step);

    b.build_root.handle.deleteFile(self.file_path) catch |err| switch (err) {
        std.os.UnlinkError.FileNotFound => {},
        else => |e| return e,
    };
}
