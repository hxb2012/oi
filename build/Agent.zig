const std = @import("std");
const Step = std.Build.Step;
const Pool = @import("Pool.zig");
const JudgeFile = @import("JudgeFile.zig");
const FetchTestCases = @import("FetchTestCases.zig");
pub const CreateFn = FetchTestCases.CreateFn;

const Agent = @This();

const base_id: Step.Id = .custom;

step: Step,
launch_step: Step,
pool: *Pool,
createFn: CreateFn,

pub fn create(owner: *std.Build, pool: *Pool, name: []const u8, createFn: CreateFn) !*Agent {
    const self = try owner.allocator.create(Agent);
    self.* = Agent{
        .step = Step.init(.{
            .id = base_id,
            .name = owner.fmt("Fetch {s} Testcases", .{name}),
            .owner = owner,
        }),
        .launch_step = Step.init(.{
            .id = base_id,
            .name = owner.fmt("Start Fetch {s} Testcases", .{name}),
            .owner = owner,
            .makeFn = launch,
        }),
        .pool = pool,
        .createFn = createFn,
    };

    self.step.dependOn(&pool.step);
    pool.step.dependOn(&self.launch_step);

    return self;
}

fn dirExists(path: []const u8) !bool {
    var tests = std.fs.cwd().openDir("tests", .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer tests.close();

    var case = tests.openDir(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer case.close();
    return true;
}

fn launch(step: *Step, prog_node: *std.Progress.Node) !void {
    _ = prog_node;

    const b = step.owner;
    const self = @fieldParentPtr(Agent, "launch_step", step);

    var map: std.StringHashMapUnmanaged(?*FetchTestCases) = .{};

    for (self.step.dependants.items) |dep| {
        const s = @fieldParentPtr(JudgeFile, "add_step", dep);
        const sub_dir = std.fs.path.dirname(s.path).?;
        const basename = std.fs.path.stem(s.path);
        const basepath = try std.fs.path.join(b.allocator, &.{ sub_dir, basename });

        if (map.get(basepath)) |option| {
            if (option) |fetch| {
                dep.dependOn(&fetch.step.step);
                try fetch.step.step.dependants.append(b.allocator, dep);
            }
        } else {
            const option = if (try dirExists(basepath))
                null
            else
                try FetchTestCases.create(b, basepath, self.createFn);
            try map.put(b.allocator, basepath, option);
            if (option) |fetch| {
                dep.dependOn(&fetch.step.step);
                try fetch.step.step.dependants.append(b.allocator, dep);
            }
        }
    }

    var iter = map.valueIterator();

    while (iter.next()) |option| {
        if (option.*) |fetch| {
            try self.pool.add(&fetch.step);
        }
    }
}
