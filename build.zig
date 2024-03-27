const std = @import("std");
const RemoveFile = @import("build/RemoveFile.zig");
const MakeDir = @import("build/MakeDir.zig");
const NoOp = @import("build/NoOp.zig");
const JudgeFile = @import("build/JudgeFile.zig");

const Options = struct {
    no_judge: bool,
    translate: bool,
    kcov: ?[]const u8,
    module: *std.Build.Module,
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

fn addFile(b: *std.Build, path: []const u8, cross_target: std.zig.CrossTarget, options: *const Options) !*std.Build.Step {
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
    const remove_c = RemoveFile.create(b, c_path);
    b.getUninstallStep().dependOn(&remove_c.step);

    const cross_translate = try addTranslate(b, path, cross_target, options.module);
    const cross_cmin = try addCmin(b, cross_target);
    cross_cmin.addFileArg(cross_translate.getEmittedBin());

    const c_compile = b.addExecutable(.{
        .name = basename,
        .link_libc = true,
        .single_threaded = true,
    });
    c_compile.step.dependOn(&native_cmin.step);
    c_compile.addCSourceFile(.{ .file = .{ .path = c_path }, .flags = &[_][]const u8{ "-Wall", "-Wextra" } });
    c_compile.step.name = b.fmt("Compile {s}", .{c_path});

    const fetch = b.addSystemCommand(&.{ "python3", "oi.py", "fetch", path });
    fetch.step.name = "fetch testcase";

    const zig_judge = JudgeFile.create(b, path, zig_compile.getEmittedBin(), options.kcov, &fetch.step);
    const c_judge = JudgeFile.create(b, c_path, c_compile.getEmittedBin(), null, &fetch.step);

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
    const judge_step = NoOp.create(b, basepath);
    judge_step.dependOn(&zig_judge.step);
    judge_step.dependOn(&c_judge.step);

    return judge_step;
}

fn addSubdir(b: *std.Build, path: []const u8, target: std.zig.CrossTarget, options: *const Options) !*std.Build.Step {
    var dir = try std.fs.cwd().openIterableDir(path, .{ .no_follow = true });
    defer dir.close();

    var it = dir.iterate();
    const step = b.step(path, "Judge subdirectory");
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const sub_path = try std.fs.path.join(b.allocator, &.{ path, entry.name });
                const subdir_step = try addSubdir(b, sub_path, target, options);
                step.dependOn(subdir_step);
            },
            .file => {
                if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".zig")) {
                    const sub_path = try std.fs.path.join(b.allocator, &.{ path, entry.name });
                    const file_step = try addFile(b, sub_path, target, options);
                    step.dependOn(file_step);
                }
            },
            else => {},
        }
    }

    return step;
}

fn addDirectory(b: *std.Build, dirname: []const u8, target: std.zig.CrossTarget, options: *const Options) !*std.Build.Step {
    var c_target: std.zig.CrossTarget = target;
    c_target.ofmt = .c;
    return try addSubdir(b, dirname, c_target, options);
}

pub fn build(b: *std.Build) !void {
    const translate = b.option(bool, "translate", "Translate to C") orelse false;
    const no_judge = b.option(bool, "no-judge", "Disable judge") orelse false;
    const kcov = b.option(bool, "kcov", "run Kcov") orelse false;
    const module = b.addModule("oi", .{ .source_file = .{ .path = "src/main.zig" } });

    const coverage: []const u8 = "coverage";

    const options: Options = .{
        .translate = translate,
        .no_judge = no_judge,
        .kcov = if (kcov) coverage else null,
        .module = module,
    };

    const judge_step = b.step("judge", "Judge all");
    judge_step.dependOn(try addDirectory(b, "AOJ", .{ .cpu_arch = .x86_64, .os_tag = .linux }, &options));

    const run_test = b.addTest(.{
        .root_source_file = .{ .path = "tests.zig" },
        .link_libc = true,
        .single_threaded = true,
    });

    const makecoverage = MakeDir.create(b, coverage);
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
}

pub const main = @import("build/main.zig").main;
