const std = @import("std");
const RemoveFile = @import("build/RemoveFile.zig");
const MakePath = @import("build/MakePath.zig");
const JudgeFile = @import("build/JudgeFile.zig");
const Pool = @import("build/Pool.zig");
const Agent = @import("build/Agent.zig");
const AOJ = @import("build/AOJ.zig");

const Options = struct {
    no_judge: bool,
    translate: bool,
    kcov: ?[]const u8,
    module: *std.Build.Module,
    fmt: *std.Build.Step,
};

const Config = struct {
    name: []const u8,
    target: std.zig.CrossTarget,
    createFn: Agent.CreateFn,
    pool: ?*Pool = null,
};

const OnlineJudge = struct {
    target: std.zig.CrossTarget,
    agent: *std.Build.Step,
};

fn addTranslate(b: *std.Build, path: []const u8, target: std.zig.CrossTarget, module: *std.Build.Module) !*std.Build.Step.Compile {
    const basename = std.fs.path.stem(path);
    const translate = b.addStaticLibrary(.{
        .name = basename,
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = .ReleaseSmall,
        .link_libc = true,
        .single_threaded = true,
    });

    const mod = b.createModule(.{ .source_file = .{ .path = path }, .dependencies = &[_]std.Build.ModuleDependency{.{ .name = "oi", .module = module }} });
    translate.addModule("answer", mod);
    translate.step.name = b.fmt("Translate {s}", .{path});
    return translate;
}

fn addCmin(b: *std.Build, cross_target: std.zig.CrossTarget) !*std.Build.Step.Run {
    const target = cross_target.toTarget();
    const cmin = b.addSystemCommand(&.{ "python3", "cmin.py" });
    cmin.addArg(b.fmt("{},{},{},{},{},{}", .{ target.c_type_bit_size(.char), target.c_type_bit_size(.short), target.c_type_bit_size(.int), target.c_type_bit_size(.long), target.c_type_bit_size(.longlong), target.ptrBitWidth() }));
    return cmin;
}

fn addJudge(b: *std.Build, path: []const u8, config: *const OnlineJudge, options: *const Options) !*std.Build.Step {
    const sub_dir = std.fs.path.dirname(path).?;
    const basename = std.fs.path.stem(path);

    const zig_compile = b.addExecutable(.{
        .name = basename,
        .root_source_file = .{ .path = path },
        .link_libc = true,
        .single_threaded = true,
    });
    zig_compile.addModule("oi", options.module);
    zig_compile.step.name = b.fmt("Compile {s}", .{path});

    const native_translate = try addTranslate(b, path, .{ .ofmt = .c }, options.module);
    const c_path = try std.fs.path.join(b.allocator, &.{ sub_dir, native_translate.out_filename });
    const native_cmin = try addCmin(b, .{ .ofmt = .c });
    native_cmin.addFileArg(native_translate.getEmittedBin());
    native_cmin.addArg(c_path);
    native_cmin.step.name = b.fmt("Minify {s}", .{c_path});

    b.getInstallStep().dependOn(&native_cmin.step);
    const remove_c = try RemoveFile.create(b, c_path);
    b.getUninstallStep().dependOn(&remove_c.step);

    const cross_translate = try addTranslate(b, path, config.target, options.module);
    const cross_cmin = try addCmin(b, config.target);
    cross_cmin.addFileArg(cross_translate.getEmittedBin());

    const c_compile = b.addExecutable(.{
        .name = basename,
        .link_libc = true,
        .single_threaded = true,
    });
    c_compile.step.dependOn(&native_cmin.step);
    c_compile.addCSourceFile(.{ .file = .{ .path = c_path }, .flags = &[_][]const u8{ "-Wall", "-Wextra" } });
    c_compile.step.name = b.fmt("Compile {s}", .{c_path});

    const zig_judge = try JudgeFile.create(b, path, zig_compile.getEmittedBin(), options.kcov, config.agent);
    const c_judge = try JudgeFile.create(b, c_path, c_compile.getEmittedBin(), null, config.agent);

    if (options.translate) {
        const zig_step = b.step(path, "Translate file");
        zig_step.dependOn(&cross_cmin.step);
    } else if (options.no_judge) {
        const run = b.addRunArtifact(zig_compile);
        const zig_step = b.step(path, "Run file");
        zig_step.dependOn(&run.step);
    } else {
        const zig_step = b.step(path, "Judge file");
        zig_step.dependOn(&zig_judge.step);
    }

    if (options.no_judge) {
        const run = b.addRunArtifact(c_compile);
        const c_step = b.step(c_path, "Run file");
        c_step.dependOn(&run.step);
    } else {
        const c_step = b.step(c_path, "Judge file");
        c_step.dependOn(&c_judge.step);
    }

    const basepath = try std.fs.path.join(b.allocator, &.{ sub_dir, basename });
    const judge_step = try b.allocator.create(std.Build.Step);
    judge_step.* = std.Build.Step.init(.{ .id = .custom, .name = basepath, .owner = b });
    judge_step.dependOn(&zig_judge.step);
    judge_step.dependOn(&c_judge.step);

    return judge_step;
}

fn addFmt(b: *std.Build, path: []const u8, options: *const Options) !void {
    const paths = try b.allocator.create([1][]const u8);
    paths.* = [_][]const u8{b.pathFromRoot(path)};
    const fmt = b.addFmt(.{ .check = true, .paths = paths });
    fmt.step.name = b.fmt("fmt {s}", .{path});
    options.fmt.dependOn(&fmt.step);
}

fn addFmtDir(b: *std.Build, path: []const u8, options: *const Options) !void {
    var dir = try std.fs.cwd().openIterableDir(path, .{});
    defer dir.close();

    var walker = try dir.walk(b.allocator);
    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (std.mem.eql(u8, std.fs.path.extension(entry.basename), ".zig")) {
                    const sub_path = try std.fs.path.join(b.allocator, &.{ path, entry.path });
                    try addFmt(b, sub_path, options);
                }
            },
            else => {},
        }
    }
}

fn addSubdir(b: *std.Build, path: []const u8, config: *const OnlineJudge, options: *const Options) !*std.Build.Step {
    var dir = try std.fs.cwd().openIterableDir(path, .{});
    defer dir.close();

    var it = dir.iterate();
    const step = b.step(path, "Judge subdirectory");
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const sub_path = try std.fs.path.join(b.allocator, &.{ path, entry.name });
                const subdir_step = try addSubdir(b, sub_path, config, options);
                step.dependOn(subdir_step);
            },
            .file => {
                if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".zig")) {
                    const sub_path = try std.fs.path.join(b.allocator, &.{ path, entry.name });
                    const file_step = try addJudge(b, sub_path, config, options);
                    try addFmt(b, sub_path, options);
                    step.dependOn(file_step);
                }
            },
            else => {},
        }
    }

    return step;
}

fn addConfig(b: *std.Build, config: *const Config, options: *const Options) !*std.Build.Step {
    const pool = if (config.pool) |p| p else try Pool.create(b, b.fmt("{s} fetch pool", .{config.name}));
    const agent = try Agent.create(b, pool, b.fmt("{s} agent", .{config.name}), config.createFn);
    var online_judge: OnlineJudge = .{
        .target = config.target,
        .agent = &agent.step,
    };
    online_judge.target.ofmt = .c;
    return try addSubdir(b, config.name, &online_judge, options);
}

pub fn build(b: *std.Build) !void {
    const translate = b.option(bool, "translate", "Translate to C") orelse false;
    const no_judge = b.option(bool, "no-judge", "Disable judge") orelse false;
    const kcov = b.option(bool, "kcov", "run Kcov") orelse false;
    const module = b.addModule("oi", .{ .source_file = .{ .path = "src/main.zig" } });
    const fmt_step = b.step("fmt", "Format");

    const coverage: []const u8 = "coverage";

    const options: Options = .{
        .translate = translate,
        .no_judge = no_judge,
        .kcov = if (kcov) coverage else null,
        .module = module,
        .fmt = fmt_step,
    };

    const src_files = [_][]const u8{ "build.zig", "main.zig", "tests.zig" };
    for (src_files) |file|
        try addFmt(b, file, &options);
    const src_dirs = [_][]const u8{ "src", "build" };
    for (src_dirs) |file|
        try addFmtDir(b, file, &options);

    const judge_step = b.step("judge", "Judge all");

    const configs = [_]Config{.{
        .name = "AOJ",
        .target = .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .createFn = AOJ.create,
    }};

    for (configs) |config|
        judge_step.dependOn(try addConfig(b, &config, &options));

    const run_test = b.addTest(.{
        .root_source_file = .{ .path = "tests.zig" },
        .link_libc = true,
        .single_threaded = true,
    });

    const makecoverage = try MakePath.create(b, coverage);
    const run_test_kcov = b.addSystemCommand(&.{ "kcov", "--exclude-path=/opt,/usr", coverage });
    run_test_kcov.addFileArg(run_test.getEmittedBin());
    run_test_kcov.step.dependOn(&makecoverage.step);

    const test_step = b.step("test", "Test");
    if (kcov) {
        test_step.dependOn(&run_test_kcov.step);
    } else {
        test_step.dependOn(&run_test.step);
    }

    test_step.dependOn(judge_step);

    const regression_step = b.step("regression", "Regression");
    regression_step.dependOn(fmt_step);
    regression_step.dependOn(test_step);
}

pub const main = @import("build/main.zig").main;
