const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sentry = b.dependency("sentry_native", .{
        .target = target,
        .optimize = optimize,
        .backend = .crashpad,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "simple",
        .root_module = exe_mod,
    });

    // Ensure a build id is set so the debug symbols can be mapped to the binary
    exe.build_id = .fast;

    exe.root_module.linkLibrary(sentry.artifact("sentry"));
    exe.root_module.addImport("sentry", sentry.module("sentry"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Install crashpad binaries
    @import("sentry_native").installCrashpad(b, &exe.step, sentry, target);
}
