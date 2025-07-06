const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    // Import dependency.
    const upstream = b.dependency("crashpad", .{});
    const minichromium_upstream = b.dependency("minichromium", .{});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlib_dep = b.dependency("zlib", .{
        .target = target,
        .optimize = optimize,
    });

    const minichromium = b.addLibrary(.{
        .name = "crashpad_client",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    const upstream_root = upstream.path("");

    // Minichromium base config
    {
        minichromium.linkLibC();
        minichromium.linkLibCpp();

        const minichromium_root = minichromium_upstream.path("");
        addSources(minichromium_root, b, target, minichromium, minichromimum_src);

        minichromium.addCSourceFile(.{
            .file = upstream.path("third_party/mini_chromium/utf_string_conversion_utils.mingw.cc"),
            .language = .cpp,
            .flags = &.{},
        });

        minichromium.installHeadersDirectory(minichromium_root, "", .{
            .include_extensions = &.{".h"},
        });
        minichromium.installHeader(minichromium_root.path(b, "build/build_config.h"), "build/build_config.h");
        minichromium.installHeader(upstream.path("third_party/mini_chromium/build/chromeos_buildflags.h"), "build/chromeos_buildflags.h");
    }

    // Crashpad handler lib
    const crashpad_handler_lib = b.addLibrary(.{
        .name = "crashpad_handler_lib",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    {
        crashpad_handler_lib.linkLibC();
        crashpad_handler_lib.linkLibCpp();

        addSources(upstream_root, b, target, crashpad_handler_lib, crashpad_handler_lib_src);
        crashpad_handler_lib.linkLibrary(minichromium);
    }

    const crashpad_client = b.addLibrary(.{
        .name = "crashpad_client",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    // Crashpad client base config
    {
        crashpad_client.linkLibrary(minichromium);

        crashpad_client.linkLibC();
        crashpad_client.linkLibCpp();

        crashpad_client.installHeadersDirectory(upstream.path("client"), "client", .{ .include_extensions = &.{".h"} });
        crashpad_client.installHeadersDirectory(upstream.path("util"), "util", .{ .include_extensions = &.{".h"} });
        crashpad_client.installHeadersDirectory(minichromium_upstream.path("base"), "base", .{ .include_extensions = &.{".h"} });
        crashpad_client.installHeader(minichromium_upstream.path("build/build_config.h"), "build/build_config.h");
        crashpad_client.installHeader(minichromium_upstream.path("build/buildflag.h"), "build/buildflag.h");
        crashpad_client.installHeader(upstream.path("third_party/mini_chromium/build/chromeos_buildflags.h"), "build/chromeos_buildflags.h");

        addSources(upstream_root, b, target, crashpad_client, crashpad_client_src);
    }

    // Crashpad minidump lib
    const crashpad_minidump_lib = b.addLibrary(.{
        .name = "crashpad_minidump_lib",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    {
        crashpad_minidump_lib.linkLibC();
        crashpad_minidump_lib.linkLibCpp();
        crashpad_minidump_lib.linkLibrary(minichromium);

        addSources(upstream_root, b, target, crashpad_minidump_lib, crashpad_minidump_src);
        crashpad_minidump_lib.linkLibrary(minichromium);
    }

    // Crashpad util lib
    const crashpad_util_lib = b.addLibrary(.{
        .name = "crashpad_util",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    {
        crashpad_util_lib.linkLibC();
        crashpad_util_lib.linkLibCpp();

        crashpad_util_lib.linkLibrary(minichromium);
        crashpad_util_lib.linkLibrary(zlib_dep.artifact("z"));

        addSources(upstream_root, b, target, crashpad_util_lib, crashpad_util_src);
        crashpad_util_lib.linkLibrary(minichromium);

        if (target.result.os.tag == .windows) {
            crashpad_handler_lib.linkSystemLibrary("version");
            crashpad_handler_lib.linkSystemLibrary("gdi32");
            crashpad_handler_lib.linkSystemLibrary("winhttp");

            try addMasmFiles(crashpad_util_lib, .{
                .target = target,
                .files = &.{
                    "util/misc/capture_context_win.asm",
                    "util/win/safe_terminate_process.asm",
                },
                .root = upstream.path(""),
            });
        }
    }

    // Crashpad snapshot lib
    const crashpad_snapshot_lib = b.addLibrary(.{
        .name = "crashpad_snapshot_lib",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    {
        crashpad_snapshot_lib.linkLibC();
        crashpad_snapshot_lib.linkLibCpp();

        addSources(upstream_root, b, target, crashpad_snapshot_lib, crashpad_snapshot_src);
        crashpad_snapshot_lib.linkLibrary(minichromium);

        if (target.result.os.tag == .windows) {
            crashpad_snapshot_lib.linkSystemLibrary("dbghelp");
            crashpad_snapshot_lib.linkSystemLibrary("powrprof");
        }
    }

    // Crashpad tool lib
    const crashpad_tool_lib = b.addLibrary(.{
        .name = "crashpad_tool_lib",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    {
        crashpad_tool_lib.linkLibC();
        crashpad_tool_lib.linkLibCpp();

        crashpad_tool_lib.linkLibrary(minichromium);

        addSources(upstream_root, b, target, crashpad_tool_lib, crashpad_tool_src);
        crashpad_tool_lib.linkLibrary(minichromium);
    }

    // Crashpad base config
    const crashpad_handler = b.addExecutable(.{
        .name = "crashpad_handler",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    {
        crashpad_handler.linkLibCpp();

        crashpad_handler.linkLibrary(crashpad_minidump_lib);
        crashpad_handler.linkLibrary(crashpad_handler_lib);
        crashpad_handler.linkLibrary(crashpad_client);
        crashpad_handler.linkLibrary(crashpad_snapshot_lib);
        crashpad_handler.linkLibrary(crashpad_util_lib);
        crashpad_handler.linkLibrary(minichromium);
        crashpad_handler.linkLibrary(crashpad_tool_lib);

        crashpad_handler.addIncludePath(upstream.path("."));

        // Cringe
        crashpad_handler.mingw_unicode_entry_point = true;

        addSources(upstream_root, b, target, crashpad_handler, crashpad_handler_src);

        crashpad_handler.subsystem = .Windows;
    }

    b.installArtifact(crashpad_client);
    b.installArtifact(crashpad_handler);
}

const AddMasmFilesOptions = struct {
    target: std.Build.ResolvedTarget,
    root: ?std.Build.LazyPath,
    files: []const []const u8,
    flags: []const []const u8 = &.{},
};

fn addMasmFiles(compile: *std.Build.Step.Compile, options: AddMasmFilesOptions) !void {
    const b = compile.step.owner;
    const root = options.root orelse b.path("");

    if (options.target.result.os.tag != .windows) {
        return error.MasmIsWindowsOnly;
    }

    // builtin.target;

    const jwasm = b.dependency("jwasm", .{});

    for (options.files) |file| {
        std.debug.assert(!std.fs.path.isAbsolute(file));
        const src_file = root.path(b, file);

        const file_stem = std.fs.path.stem(file);

        const jwasm_binary = jwasm.artifact("jwasm");

        const run_jwasm = b.addRunArtifact(jwasm_binary);

        run_jwasm.addArg("-nologo");
        run_jwasm.addArg("-c");
        run_jwasm.addArg("-win64");

        if (options.target.result.abi != .msvc) {
            run_jwasm.addArg("-D__MINGW32__");
        }

        const obj = run_jwasm.addPrefixedOutputFileArg("-Fo", b.fmt("{s}.obj", .{file_stem}));
        run_jwasm.addFileArg(src_file);
        for (options.flags) |flag| run_jwasm.addArg(flag);

        compile.addObjectFile(obj);
    }

    // const cmd = switch (builtin.os.tag) {
    //     .windows => blk: {
    //         // var env_var: []const u8 = undefined;
    //         // const ml = ml_blk: switch (options.target.cpu.arch) {
    //         //     .x86 => {
    //         //         env_var = "ML_PATH";
    //         //         break :ml_blk "ml.exe";
    //         //     },
    //         //     else => {
    //         //         env_var = "ML_64_PATH";
    //         //         break :ml_blk "ml64.exe";
    //         //     },
    //         // };

    //         // // Find ml executable
    //         // const ml_exe = ml_blk: {
    //         //     const ml_env_path = b.graph.env_map.get(env_var);
    //         //     if (ml_env_path) |env| {
    //         //         break :ml_blk env;
    //         //     }

    //         //     break :ml_blk b.findProgram(&.{ml}, &.{}) catch {
    //         //         std.log.err("failed to find {s} executable. Please provide it in %PATH%, %ML_PATH% or %ML_64_PATH%", .{ml});
    //         //         return error.MLNotFound;
    //         //     };
    //         // };

    //         // const step = b.addSystemCommand(&.{ml_exe});
    //         // step.addArg("/nologo");
    //         // step.addArg("/c");

    //         // if (options.target.abi != .msvc) {
    //         //     step.addArg("/D__MINGW32__");
    //         // }

    //         // const obj = step.addPrefixedOutputFileArg("/Fo", b.fmt("{s}.obj", .{file_stem}));
    //         // step.addFileArg(src_file);
    //         // for (options.flags) |flag| step.addArg(flag);
    //         // break :blk .{ step, obj };
    //     },
    //     else => blk: {
    //         const step = b.addSystemCommand(&.{"uasm"});
    //         step.addArg("-nologo");
    //         step.addArg("-c");
    //         step.addArg("-win64"); // or "-win32" for 32-bit
    //         const obj = step.addPrefixedOutputFileArg("-Fo", b.fmt("{s}.obj", .{file_stem}));
    //         step.addFileArg(src_file);
    //         for (options.flags) |flag| step.addArg(flag);

    //         break :blk .{ step, obj };
    //     },
    // };

}

pub fn addSources(root: std.Build.LazyPath, b: *std.Build, target: std.Build.ResolvedTarget, compile: *std.Build.Step.Compile, definition: CompileDefinition) void {
    for (definition.general) |file| {
        compile.addCSourceFile(.{
            .file = root.path(b, file),
            .language = definition.language,
            .flags = definition.flags,
        });
    }

    // Platform specific configs
    switch (target.result.os.tag) {
        .linux, .macos => {
            for (definition.unix) |file| {
                compile.addCSourceFile(.{
                    .file = root.path(b, file),
                    .language = definition.language,
                    .flags = definition.flags,
                });
            }
        },
        .windows => {
            for (definition.win) |file| {
                compile.addCSourceFile(.{
                    .file = root.path(b, file),
                    .language = definition.language,
                    .flags = definition.flags,
                });
            }
        },
        else => {},
    }

    for (definition.include_directories) |include| {
        compile.addIncludePath(root.path(b, include));
    }
}

const CompileDefinition = struct {
    general: []const []const u8,
    win: []const []const u8,
    unix: []const []const u8,
    flags: []const []const u8,
    include_directories: []const []const u8,
    language: std.Build.Module.CSourceLanguage = .cpp,
};

const crashpad_client_src = CompileDefinition{
    .general = &.{
        "client/annotation.cc",
        "client/annotation_list.cc",
        "client/crash_report_database.cc",
        "client/crashpad_info.cc",
        "client/prune_crash_reports.cc",
        "client/settings.cc",
    },
    .unix = &.{
        "client/crashpad_client_linux.cc",
        "client/client_argv_handling.cc",
        "client/crash_report_database_generic.cc",
        "client/crashpad_info_note.S",
    },
    .win = &.{
        "client/crash_report_database_win.cc",
        "client/crashpad_client_win.cc",
    },
    .flags = &.{
        "-municode",
        "-std=c++17",
        "-DCRASHPAD_FLOCK_ALWAYS_SUPPORTED=1",
    },
    .include_directories = &.{
        ".",
    },
};

const minichromimum_src = CompileDefinition{
    .general = &.{
        "base/debug/alias.cc",
        "base/files/file_path.cc",
        "base/files/scoped_file.cc",
        "base/logging.cc",
        "base/process/memory.cc",
        "base/rand_util.cc",
        "base/strings/pattern.cc",
        "base/strings/strcat.cc",
        "base/strings/string_number_conversions.cc",
        "base/strings/stringprintf.cc",
        "base/strings/utf_string_conversions.cc",
        "base/synchronization/lock.cc",
        "base/third_party/icu/icu_utf.cc",
        "base/threading/thread_local_storage.cc",
    },
    .unix = &.{
        "base/files/file_util_posix.cc",
        "base/memory/page_size_posix.cc",

        "base/posix/safe_strerror.cc",

        "base/synchronization/condition_variable_posix.cc",
        "base/synchronization/lock_impl_posix.cc",
        "base/threading/thread_local_storage_posix.cc",
    },
    .win = &.{
        "base/memory/page_size_win.cc",
        "base/scoped_clear_last_error_win.cc",
        "base/strings/string_util_win.cc",

        "base/synchronization/lock_impl_win.cc",
        "base/threading/thread_local_storage_win.cc",
    },
    .flags = &.{
        "-DNOMINMAX",
        "-DUNICODE",
        "-DWIN32_LEAN_AND_MEAN",
        "-D_CRT_SECURE_NO_WARNINGS",
        "-D_HAS_EXCEPTIONS=0",
        "-D_UNICODE",
        "-std=c++20",
        "-municode",
        "-Wno-format",
        "-Wno-unknown-pragmas",
    },
    .include_directories = &.{
        "",
    },
};

const crashpad_handler_lib_src = CompileDefinition{
    .general = &.{
        "handler/crash_report_upload_thread.cc",
        "handler/handler_main.cc",
        "handler/minidump_to_upload_parameters.cc",
        "handler/prune_crash_reports_thread.cc",
        "handler/user_stream_data_source.cc",
    },
    .win = &.{
        "handler/win/crash_report_exception_handler.cc",
    },
    .unix = &.{
        "handler/linux/capture_snapshot.cc",
        "handler/linux/crash_report_exception_handler.cc",
        "handler/linux/exception_handler_server.cc",
        "handler/linux/crash_report_exception_handler.cc",
    },
    .flags = &.{},
    .include_directories = &.{
        ".",
    },
};

const crashpad_handler_src = CompileDefinition{
    .general = &.{
        "handler/main.cc",
    },
    .win = &.{},
    .unix = &.{
        "client/pthread_create_linux.cc",
    },
    .language = .cpp,
    .flags = &.{
        "-municode",
    },
    .include_directories = &.{},
};

const crashpad_minidump_src = CompileDefinition{
    .general = &.{
        "minidump/minidump_annotation_writer.cc",
        "minidump/minidump_byte_array_writer.cc",
        "minidump/minidump_context_writer.cc",
        "minidump/minidump_crashpad_info_writer.cc",
        "minidump/minidump_exception_writer.cc",
        "minidump/minidump_extensions.cc",
        "minidump/minidump_file_writer.cc",
        "minidump/minidump_handle_writer.cc",
        "minidump/minidump_memory_info_writer.cc",
        "minidump/minidump_memory_writer.cc",
        "minidump/minidump_misc_info_writer.cc",
        "minidump/minidump_module_crashpad_info_writer.cc",
        "minidump/minidump_module_writer.cc",
        "minidump/minidump_rva_list_writer.cc",
        "minidump/minidump_simple_string_dictionary_writer.cc",
        "minidump/minidump_stream_writer.cc",
        "minidump/minidump_string_writer.cc",
        "minidump/minidump_system_info_writer.cc",
        "minidump/minidump_thread_id_map.cc",
        "minidump/minidump_thread_name_list_writer.cc",
        "minidump/minidump_thread_writer.cc",
        "minidump/minidump_unloaded_module_writer.cc",
        "minidump/minidump_user_extension_stream_data_source.cc",
        "minidump/minidump_user_stream_writer.cc",
        "minidump/minidump_writable.cc",
        "minidump/minidump_writer_util.cc",
    },
    .win = &.{},
    .unix = &.{},
    .flags = &.{},
    .language = .cpp,
    .include_directories = &.{ ".", "compat/mingw/" },
};

const crashpad_snapshot_src = CompileDefinition{
    .general = &.{
        "snapshot/annotation_snapshot.cc",
        "snapshot/capture_memory.cc",
        "snapshot/cpu_context.cc",
        "snapshot/crashpad_info_client_options.cc",
        "snapshot/handle_snapshot.cc",
        "snapshot/memory_snapshot.cc",
        "snapshot/minidump/exception_snapshot_minidump.cc",
        "snapshot/minidump/memory_snapshot_minidump.cc",
        "snapshot/minidump/minidump_annotation_reader.cc",
        "snapshot/minidump/minidump_context_converter.cc",
        "snapshot/minidump/minidump_simple_string_dictionary_reader.cc",
        "snapshot/minidump/minidump_string_list_reader.cc",
        "snapshot/minidump/minidump_string_reader.cc",
        "snapshot/minidump/module_snapshot_minidump.cc",
        "snapshot/minidump/process_snapshot_minidump.cc",
        "snapshot/minidump/system_snapshot_minidump.cc",
        "snapshot/minidump/thread_snapshot_minidump.cc",
        "snapshot/unloaded_module_snapshot.cc",
        "snapshot/crashpad_types/crashpad_info_reader.cc",

        "snapshot/x86/cpuid_reader.cc",
    },
    .win = &.{
        "snapshot/win/capture_memory_delegate_win.cc",
        "snapshot/win/cpu_context_win.cc",
        "snapshot/win/exception_snapshot_win.cc",
        "snapshot/win/memory_map_region_snapshot_win.cc",
        "snapshot/win/module_snapshot_win.cc",
        "snapshot/win/pe_image_annotations_reader.cc",
        "snapshot/win/pe_image_reader.cc",
        "snapshot/win/pe_image_resource_reader.cc",
        "snapshot/win/process_reader_win.cc",
        "snapshot/win/process_snapshot_win.cc",
        "snapshot/win/process_subrange_reader.cc",
        "snapshot/win/system_snapshot_win.cc",
        "snapshot/win/thread_snapshot_win.cc",
    },
    .unix = &.{
        "snapshot/posix/timezone.cc",
        "snapshot/linux/capture_memory_delegate_linux.cc",
        "snapshot/linux/cpu_context_linux.cc",
        "snapshot/linux/debug_rendezvous.cc",
        "snapshot/linux/exception_snapshot_linux.cc",
        "snapshot/linux/process_reader_linux.cc",
        "snapshot/linux/process_snapshot_linux.cc",
        "snapshot/linux/system_snapshot_linux.cc",
        "snapshot/linux/thread_snapshot_linux.cc",
        "snapshot/sanitized/memory_snapshot_sanitized.cc",
        "snapshot/sanitized/module_snapshot_sanitized.cc",
        "snapshot/sanitized/process_snapshot_sanitized.cc",
        "snapshot/sanitized/sanitization_information.cc",
        "snapshot/sanitized/thread_snapshot_sanitized.cc",
        "snapshot/crashpad_types/image_annotation_reader.cc",
        "snapshot/elf/elf_dynamic_array_reader.cc",
        "snapshot/elf/elf_image_reader.cc",
        "snapshot/elf/elf_symbol_table_reader.cc",
        "snapshot/elf/module_snapshot_elf.cc",
    },
    .flags = &.{
        "-municode",
    },
    .include_directories = &.{ ".", "compat/mingw/" },
};

const crashpad_tool_src = CompileDefinition{
    .general = &.{
        "tools/tool_support.cc",
    },
    .win = &.{},
    .unix = &.{},
    .flags = &.{
        "-municode",
        "-std=c++17",
    },
    .include_directories = &.{"."},
    .language = .cpp,
};

const crashpad_util_src = CompileDefinition{
    .general = &.{
        "util/file/delimited_file_reader.cc",
        "util/file/file_helper.cc",
        "util/file/file_io.cc",
        "util/file/file_reader.cc",
        "util/file/file_seeker.cc",
        "util/file/file_writer.cc",
        "util/file/output_stream_file_writer.cc",
        "util/file/scoped_remove_file.cc",
        "util/file/string_file.cc",
        "util/misc/initialization_state_dcheck.cc",
        "util/misc/lexing.cc",
        "util/misc/metrics.cc",
        "util/misc/pdb_structures.cc",
        "util/misc/random_string.cc",
        "util/misc/range_set.cc",
        "util/misc/reinterpret_bytes.cc",
        "util/misc/scoped_forbid_return.cc",
        "util/misc/time.cc",
        "util/misc/uuid.cc",
        "util/misc/zlib.cc",
        "util/net/http_body.cc",
        "util/net/http_body_gzip.cc",
        "util/net/http_multipart_builder.cc",
        "util/net/http_transport.cc",
        "util/net/url.cc",
        "util/numeric/checked_address_range.cc",
        "util/process/process_memory.cc",
        "util/process/process_memory_range.cc",
        "util/stdlib/aligned_allocator.cc",
        "util/stdlib/string_number_conversion.cc",
        "util/stdlib/strlcpy.cc",
        "util/stdlib/strnlen.cc",
        "util/stream/base94_output_stream.cc",
        "util/stream/file_encoder.cc",
        "util/stream/file_output_stream.cc",
        "util/stream/log_output_stream.cc",
        "util/stream/zlib_output_stream.cc",
        "util/string/split_string.cc",
        "util/thread/thread.cc",
        "util/thread/thread_log_messages.cc",
        "util/thread/worker_thread.cc",
    },
    .win = &.{
        "util/file/directory_reader_win.cc",
        "util/file/file_io_win.cc",
        "util/file/filesystem_win.cc",
        "util/misc/clock_win.cc",
        "util/misc/paths_win.cc",
        "util/misc/time_win.cc",
        "util/net/http_transport_win.cc",
        "util/process/process_memory_win.cc",
        "util/synchronization/semaphore_win.cc",
        "util/thread/thread_win.cc",
        "util/win/command_line.cc",
        "util/win/critical_section_with_debug_info.cc",
        "util/win/exception_handler_server.cc",
        "util/win/get_function.cc",
        "util/win/get_module_information.cc",
        "util/win/handle.cc",
        "util/win/initial_client_data.cc",
        "util/win/loader_lock.cc",
        "util/win/module_version.cc",
        "util/win/nt_internals.cc",
        "util/win/ntstatus_logging.cc",
        "util/win/process_info.cc",
        "util/win/registration_protocol_win.cc",
        "util/win/scoped_handle.cc",
        "util/win/scoped_local_alloc.cc",
        "util/win/scoped_process_suspend.cc",
        "util/win/scoped_set_event.cc",
        "util/win/screenshot.cc",
        "util/win/session_end_watcher.cc",
    },
    .unix = &.{
        "util/net/http_transport_libcurl.cc",
        "util/file/directory_reader_posix.cc",
        "util/file/file_io_posix.cc",
        "util/file/filesystem_posix.cc",
        "util/misc/clock_posix.cc",
        "util/posix/close_stdio.cc",
        "util/posix/scoped_dir.cc",
        "util/posix/scoped_mmap.cc",
        "util/posix/signals.cc",
        "util/synchronization/semaphore_posix.cc",
        "util/thread/thread_posix.cc",
        "util/posix/close_multiple.cc",
        "util/posix/drop_privileges.cc",
        "util/posix/spawn_subprocess.cc",
        "util/posix/symbolic_constants_posix.cc",

        "util/linux/auxiliary_vector.cc",
        "util/linux/direct_ptrace_connection.cc",
        "util/linux/exception_handler_client.cc",
        "util/linux/exception_handler_protocol.cc",
        "util/linux/memory_map.cc",
        "util/linux/pac_helper.cc",
        "util/linux/proc_stat_reader.cc",
        "util/linux/proc_task_reader.cc",
        "util/linux/ptrace_broker.cc",
        "util/linux/ptrace_client.cc",
        "util/linux/ptracer.cc",
        "util/linux/scoped_pr_set_dumpable.cc",
        "util/linux/scoped_pr_set_ptracer.cc",
        "util/linux/scoped_ptrace_attach.cc",
        "util/linux/socket.cc",
        "util/linux/thread_info.cc",
        "util/misc/capture_context_linux.S",
        "util/misc/paths_linux.cc",
        "util/misc/time_linux.cc",
        "util/posix/process_info_linux.cc",
        "util/process/process_memory_linux.cc",
        "util/process/process_memory_sanitized.cc",
    },
    .flags = &.{
        "-municode",
        "-std=c++17",
        "-DCRASHPAD_ZLIB_SOURCE_EXTERNAL=1",
        "-DZLIB_CONST",
    },
    .include_directories = &.{"."},
    .language = .cpp,
};
