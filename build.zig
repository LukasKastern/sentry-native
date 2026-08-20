const std = @import("std");

// The version of the `sentry-native` SDK.
const version: std.SemanticVersion = .{ .major = 0, .minor = 8, .patch = 1 };

const Backend = enum {
    none,
    in_proc,
    crashpad,
};

// Helper function to run the system command and return the stdout with trimmed whitespaces and new lines.
fn run_cmd(opts: struct {
    b: *std.Build,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    cwd: ?[]const u8 = null,
}) ![]const u8 {
    std.log.info("{s}", .{try std.mem.join(opts.allocator, " ", opts.argv)});

    const cmd = try std.process.run(opts.allocator, opts.b.graph.io, .{
        .argv = opts.argv,
        .cwd = if (opts.cwd) |cwd| .{ .path = cwd } else .inherit,
    });

    if (cmd.term.exited != 0) {
        std.log.err("Faild with error: {s}", .{cmd.stderr});
        return error.NonZeroExit;
    }

    return std.mem.trim(u8, cmd.stdout, &.{ ' ', '\n', '\r' });
}

pub fn build(b: *std.Build) void {
    // Import dependency.
    const upstream = b.dependency("sentry-native", .{});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add options which could be provided by the uses of this library.
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Link mode of the sentry_native library (default: static)") orelse .static;
    const backend = b.option(Backend, "backend", "Backend to use (default: Crashpad)") orelse .crashpad;
    const with_zlib = b.option(bool, "zlib", "Enable transport compression (default: false)") orelse false;

    var cflags_list: std.ArrayList([]const u8) = .empty;
    cflags_list.appendSlice(b.allocator, &.{
        "-Wall", "-pedantic", "-O2", "-fpic", "-MTd", "-pthread",
    }) catch @panic("OOM");

    if (target.result.os.tag == .macos) {
        // Get the SDK path.
        const sdk_path = run_cmd(.{
            .b = b,
            .allocator = b.allocator,
            .argv = &.{ "xcrun", "--show-sdk-path" },
        }) catch @panic("Unable to run command to get the MacOS sdk path.");

        cflags_list.appendSlice(b.allocator, &.{ "-isysroot", sdk_path }) catch @panic("OOM");
    }

    // Prepare the build of the static library.
    const sentry_native = b.addLibrary(.{
        .name = "sentry",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .version = version,
        .linkage = linkage,
    });

    if (linkage == .static) {
        // Since the library build as static, we should define the macro for the compiler.
        sentry_native.root_module.addCMacro("SENTRY_BUILD_STATIC", "1");
    }

    // Compiler flags.
    const cflags = cflags_list.items;

    // Enable transport compression.
    if (with_zlib) {
        // Link the zlib.
        sentry_native.root_module.linkSystemLibrary("z", .{});
        sentry_native.root_module.addCMacro("SENTRY_TRANSPORT_COMPRESSION", "1");
    }

    b.installArtifact(sentry_native);
    // Setup the library's inputs and outputs.
    sentry_native.root_module.addIncludePath(upstream.path("include"));
    sentry_native.root_module.addIncludePath(upstream.path("src"));
    sentry_native.root_module.addIncludePath(upstream.path("vendor"));
    sentry_native.installHeadersDirectory(upstream.path("include"), "", .{});
    sentry_native.root_module.addCSourceFiles(.{ .files = sentry_src, .root = upstream.path(""), .flags = cflags });

    switch (backend) {
        .none => {
            sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/backends/sentry_backend_none.c"), .flags = cflags });
        },
        .in_proc => {
            sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/backends/sentry_backend_inproc.c"), .flags = cflags });
        },
        .crashpad => {
            if (b.lazyDependency("crashpad", .{
                .target = target,
                .optimize = optimize,
            })) |crashpad| {
                sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/backends/sentry_backend_crashpad.cpp"), .flags = cflags });
                sentry_native.is_linking_libcpp = true;

                sentry_native.root_module.linkLibrary(crashpad.artifact("crashpad_client"));

                // Install crashpad_handler
                const crashpad_handler = crashpad.artifact("crashpad_handler");
                b.installArtifact(crashpad_handler);

                if (target.result.os.tag == .windows) {
                    const wer_module = crashpad.artifact("crashpad_wer");
                    b.installArtifact(wer_module);
                }
            }
        },
    }

    switch (target.result.os.tag) {
        .linux, .macos => {
            // Add option to enable curl and link libcurl.
            const with_curl = b.option(bool, "curl", "Enable curl support (Unix-like only) for backend transport (default: false)") orelse false;
            // Link libcurl only for unix-like systems.
            if (with_curl) {
                const curl_dependency = b.dependency("curl", .{
                    .target = target,
                    .optimize = optimize,
                    .libpsl = false,
                    .libssh2 = false,
                    .libidn2 = false,
                    .nghttp2 = false,
                    .@"disable-ldap" = true,
                    .@"use-boringssl" = true,
                });

                const lib_curl = @import("curl").artifact(curl_dependency, .lib);
                sentry_native.root_module.linkLibrary(lib_curl);

                sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/transports/sentry_transport_curl.c"), .flags = cflags });
            } else {
                sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/transports/sentry_transport_none.c"), .flags = cflags });
            }

            sentry_native.root_module.linkSystemLibrary("pthread", .{});

            sentry_native.root_module.addCSourceFiles(.{ .files = sentry_unix_src, .root = upstream.path(""), .flags = cflags });

            // Linux specific.
            if (target.result.os.tag == .linux) {
                std.debug.print("Starting Linux Build.\n", .{});
                // Link libc when on linux.
                sentry_native.root_module.link_libc = true;
                sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/modulefinder/sentry_modulefinder_linux.c"), .flags = cflags });
            }

            // Macos specific
            if (target.result.os.tag == .macos) {
                std.debug.print("Starting MacOs Build.\n", .{});
                sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/modulefinder/sentry_modulefinder_apple.c"), .flags = cflags });
            }
        },
        .windows => {
            std.debug.print("Starting Windows Build.\n", .{});
            sentry_native.root_module.link_libc = true;
            sentry_native.root_module.linkSystemLibrary("version", .{});
            sentry_native.root_module.linkSystemLibrary("dbghelp", .{});

            // Add option to enable winhttp support.
            const with_winhttp = b.option(bool, "winhttp", "Enable winhttp support (Windows only) for backend transport (default: false)") orelse false;
            // Enable winhttp support if option provided otherwise there will be no transport.
            if (with_winhttp) {
                sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/transports/sentry_transport_winhttp.c"), .flags = cflags });
                sentry_native.root_module.linkSystemLibrary("winhttp", .{});
            } else {
                sentry_native.root_module.addCSourceFile(.{ .file = upstream.path("src/transports/sentry_transport_none.c"), .flags = cflags });
            }
            sentry_native.root_module.addCSourceFiles(.{ .files = sentry_win_src, .root = upstream.path(""), .flags = cflags });
        },
        else => @panic("Unsupported build target."),
    }

    // Translate C header file to zig-like module file.
    const sentry_headers = b.addTranslateC(.{
        .root_source_file = upstream.path("include/sentry.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    if (linkage == .static) {
        // Since we are building a static library, we should set SENTRY_BUILD_STATIC=1.
        sentry_headers.defineCMacro("SENTRY_BUILD_STATIC", "1");
    }

    // Create an importable module for this library.
    _ = b.addModule("sentry", .{ .root_source_file = sentry_headers.createModule().root_source_file });
}

// The Windows specific source files.
pub const sentry_win_src: []const []const u8 = &.{
    "src/modulefinder/sentry_modulefinder_windows.c",
    "src/path/sentry_path_windows.c",
    "src/symbolizer/sentry_symbolizer_windows.c",
    "src/sentry_windows_dbghelp.c",
    "src/unwinder/sentry_unwinder_libbacktrace.c",
    "src/unwinder/sentry_unwinder_dbghelp.c",
};

// The unix specific source files, used for Linux and MacOS.
pub const sentry_unix_src: []const []const u8 = &.{
    "src/sentry_unix_pageallocator.c",
    "src/path/sentry_path_unix.c",
    "src/symbolizer/sentry_symbolizer_unix.c",
};

// The common source files used to build the `sentry-native` library.
pub const sentry_src: []const []const u8 = &.{
    "src/sentry_uuid.c",
    "src/sentry_sync.c",
    "src/sentry_options.c",
    "src/sentry_utils.c",
    "src/sentry_backend.c",
    "src/sentry_core.c",
    "src/sentry_slice.c",
    "src/path/sentry_path.c",
    "src/transports/sentry_function_transport.c",
    "src/transports/sentry_disk_transport.c",
    "src/sentry_value.c",
    "src/sentry_ratelimiter.c",
    "src/sentry_transport.c",
    "src/sentry_tracing.c",
    "src/sentry_database.c",
    "src/sentry_json.c",
    "src/sentry_os.c",
    "src/sentry_string.c",
    "src/sentry_random.c",
    "src/sentry_logger.c",
    "src/sentry_info.c",
    "src/sentry_session.c",
    "src/sentry_alloc.c",
    "src/unwinder/sentry_unwinder.c",
    "src/sentry_scope.c",
    "src/sentry_envelope.c",
    "vendor/stb_sprintf.c",
    "vendor/mpack.c",
};

// Install crashpad
// Makes the given step a dependency of the installation
pub fn installCrashpad(
    target_build: *std.Build,
    step: *std.Build.Step,
    sentry: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    if (sentry.builder.lazyDependency("crashpad", .{
        .target = target,
        .optimize = optimize,
    }) != null) {
        const install_crashpad = target_build.addInstallArtifact(sentry.artifact("crashpad_handler"), .{});
        step.dependOn(&install_crashpad.step);

        if (target.result.os.tag == .windows) {
            const install_wer = target_build.addInstallArtifact(sentry.artifact("crashpad_wer"), .{});
            step.dependOn(&install_wer.step);
        }
    }
}
