const std = @import("std");

const Pool = @This();

step: std.Build.Step,
mutex: std.Thread.Mutex,
queue: std.TailQueue(*Step),
size: usize = 5,

pub fn create(owner: *std.Build, name: []const u8) !*Pool {
    const self = try owner.allocator.create(Pool);
    self.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = owner.dupe(name),
            .owner = owner,
            .makeFn = dispatch,
        }),
        .mutex = .{},
        .queue = .{},
    };
    return self;
}

fn dispatch(step: *std.Build.Step, node: *std.Progress.Node) !void {
    _ = node;
    const b = step.owner;
    const self = @fieldParentPtr(Pool, "step", step);
    for (0..self.size) |i| {
        const s = try b.allocator.create(Step);
        try s.initAllocated(b, b.fmt("Phantom {d}", .{i}));
        s.pool = self;
        try step.dependants.append(b.allocator, &s.start_step);
    }
}

pub fn get(self: *Pool, allocator: std.mem.Allocator) ?*Step {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.queue.popFirst()) |node| {
        defer allocator.destroy(node);
        return node.data;
    } else {
        return null;
    }
}

pub fn add(self: *Pool, step: *Step) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    const node = try self.step.owner.allocator.create(@TypeOf(self.queue).Node);
    node.* = .{ .data = step };
    step.pool = self;
    self.queue.append(node);
}

pub const Step = struct {
    pub const MakeFn = *const fn (step: *Step, node: *std.Progress.Node) anyerror!void;

    step: std.Build.Step,
    start_step: std.Build.Step,
    pool: ?*Pool = null,
    result: ?anyerror!void = null,
    startFn: MakeFn = makeNoOp,
    checkFn: MakeFn = makeNoOp,
    count: usize = 0,

    fn makeNoOp(step: *Step, node: *std.Progress.Node) !void {
        _ = step;
        _ = node;
    }

    pub fn initAllocated(self: *Step, owner: *std.Build, name: []const u8) !void {
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = owner.fmt("[CHECK] {s}", .{name}),
                .owner = owner,
                .makeFn = check,
            }),
            .start_step = std.Build.Step.init(.{
                .id = .custom,
                .name = owner.fmt("[START] {s}", .{name}),
                .owner = owner,
                .makeFn = start,
            }),
        };

        self.step.dependOn(&self.start_step);
        try self.start_step.dependants.append(owner.allocator, &self.step);
        self.step.state = .precheck_done;
        self.start_step.state = .precheck_done;
    }

    pub fn addChildStep(self: *Step, child: *Step) !void {
        self.step.dependOn(&child.step);
        try child.step.dependants.append(self.step.owner.allocator, &self.step);
        self.count = self.count + 1;
        try self.pool.?.add(child);
    }

    fn check(step: *std.Build.Step, node: *std.Progress.Node) !void {
        const self = @fieldParentPtr(Step, "step", step);
        try self.result.?;
        try self.checkFn(self, node);
    }

    fn start(step: *std.Build.Step, node: *std.Progress.Node) !void {
        const b = step.owner;
        const self = @fieldParentPtr(Step, "start_step", step);
        self.result = self.startFn(self, node);

        step.dependants.clearRetainingCapacity();
        if (self.count == 0)
            try step.dependants.append(b.allocator, &self.step);

        if (self.pool.?.get(b.allocator)) |dep|
            try step.dependants.append(b.allocator, &dep.start_step);
    }
};
