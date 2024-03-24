const std = @import("std");

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
    return translate;
}

fn addCmin(b: *std.Build, cross_target: std.zig.CrossTarget) !*std.Build.Step.Run {
    const target = cross_target.toTarget();
    const cmin = b.addSystemCommand(&.{ "python3", "cmin.py" });
    cmin.addArg(try std.fmt.allocPrint(b.allocator, "{},{},{},{},{},{}", .{ target.c_type_bit_size(.char), target.c_type_bit_size(.short), target.c_type_bit_size(.int), target.c_type_bit_size(.long), target.c_type_bit_size(.longlong), target.ptrBitWidth() }));
    return cmin;
}

fn addFile(b: *std.Build, path: []const u8, cross_target: std.zig.CrossTarget, no_judge: bool, translate: bool, module: *std.Build.Module) !*std.Build.Step {
    const sub_dir = std.fs.path.dirname(path).?;
    const basename = std.fs.path.stem(path);

    const zig_compile = b.addExecutable(.{
        .name = basename,
        .root_source_file = .{ .path = path },
        .link_libc = true,
        .single_threaded = true,
    });
    zig_compile.addModule("oi", module);

    const native_translate = try addTranslate(b, path, .{ .ofmt = .c }, module);
    const c_path = try std.fs.path.join(b.allocator, &.{ sub_dir, native_translate.out_filename });
    const native_cmin = try addCmin(b, .{ .ofmt = .c });
    native_cmin.addFileArg(native_translate.getEmittedBin());
    native_cmin.addArg(c_path);
    b.getInstallStep().dependOn(&native_cmin.step);

    const cross_translate = try addTranslate(b, path, cross_target, module);
    const cross_cmin = try addCmin(b, cross_target);
    cross_cmin.addFileArg(cross_translate.getEmittedBin());

    const c_compile = b.addExecutable(.{
        .name = basename,
        .link_libc = true,
        .single_threaded = true,
    });
    c_compile.step.dependOn(&native_cmin.step);
    c_compile.addCSourceFile(.{ .file = .{ .path = c_path }, .flags = &[_][]const u8{ "-Wall", "-Wextra" } });

    const zig_judge = b.addSystemCommand(&.{ "python3", "oi.py", "judge" });
    zig_judge.addPrefixedFileArg("--bin=", zig_compile.getEmittedBin());
    zig_judge.addArg(path);

    const c_judge = b.addSystemCommand(&.{ "python3", "oi.py", "judge" });
    c_judge.addPrefixedFileArg("--bin=", c_compile.getEmittedBin());
    c_judge.addArg(path);

    if (translate) {
        const zig_step = b.step(path, "Translate file");
        zig_step.dependOn(&cross_cmin.step);
    } else if (no_judge) {
        const run = b.addRunArtifact(zig_compile);
        const zig_step = b.step(path, "Run file");
        zig_step.dependOn(&run.step);
    } else {
        const zig_step = b.step(path, "Judge file");
        zig_step.dependOn(&zig_judge.step);
    }

    if (no_judge) {
        const run = b.addRunArtifact(c_compile);
        const c_step = b.step(c_path, "Run file");
        c_step.dependOn(&run.step);
    } else {
        const c_step = b.step(c_path, "Judge file");
        c_step.dependOn(&c_judge.step);
    }

    const basepath = try std.fs.path.join(b.allocator, &.{ sub_dir, basename });
    const judge_step = b.step(basepath, "Judge answer");
    judge_step.dependOn(&zig_judge.step);
    judge_step.dependOn(&c_judge.step);

    return judge_step;
}

fn addSubdir(b: *std.Build, path: []const u8, target: std.zig.CrossTarget, no_judge: bool, translate: bool, module: *std.Build.Module) !*std.Build.Step {
    var dir = try std.fs.cwd().openIterableDir(path, .{ .no_follow = true });
    defer dir.close();

    var it = dir.iterate();
    const step = b.step(path, "Judge subdirectory");
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const sub_path = try std.fs.path.join(b.allocator, &.{ path, entry.name });
                const subdir_step = try addSubdir(b, sub_path, target, no_judge, translate, module);
                step.dependOn(subdir_step);
            },
            .file => {
                if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".zig")) {
                    const sub_path = try std.fs.path.join(b.allocator, &.{ path, entry.name });
                    const file_step = try addFile(b, sub_path, target, no_judge, translate, module);
                    step.dependOn(file_step);
                }
            },
            else => {},
        }
    }

    return step;
}

fn addDirectory(b: *std.Build, dirname: []const u8, target: std.zig.CrossTarget, no_judge: bool, translate: bool, module: *std.Build.Module) !*std.Build.Step {
    var c_target: std.zig.CrossTarget = target;
    c_target.ofmt = .c;
    return try addSubdir(b, dirname, c_target, no_judge, translate, module);
}

pub fn build(b: *std.Build) !void {
    const translate = b.option(bool, "translate", "Translate to C") orelse false;
    const no_judge = b.option(bool, "no-judge", "Disable judge") orelse false;

    const module = b.addModule("oi", .{ .source_file = .{ .path = "src/main.zig" } });

    const step = b.step("judge", "Judge all");
    step.dependOn(try addDirectory(b, "AOJ", .{ .cpu_arch = .x86_64, .os_tag = .linux }, no_judge, translate, module));
}
