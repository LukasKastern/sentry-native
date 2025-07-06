const sentry = @import("sentry");
const std = @import("std");
const builtin = @import("builtin");

pub const std_options: std.Options = .{
    .enable_segfault_handler = false, // disable default zig segfault handler
};

pub fn main() !void {
    // std.debug.maybeEnableSegfaultHandler()

    // Create a new options set.
    const opts = sentry.sentry_options_new();
    // Make sure to set the correct DSN.
    sentry.sentry_options_set_dsn(opts, "https://628cae3e3e6410e31e2597144d1cc7fe@o4509621749350400.ingest.de.sentry.io/4509621750595664");
    // Do not sample errors
    sentry.sentry_options_set_sample_rate(opts, 1);
    // Do not sample transactions.
    sentry.sentry_options_set_traces_sample_rate(opts, 1.0);
    // Enable DEBUG, 0 is to turn off the debug logging.
    sentry.sentry_options_set_debug(opts, 1);

    // sentry.sentry_options_set_on_crash(opts, crash_function, undefined);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const exe = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe);

    const crashpad_path = try std.fs.path.joinZ(allocator, &.{ exe, "crashpad_handler.exe" });
    defer allocator.free(crashpad_path);

    // Set crashpad path
    sentry.sentry_options_set_handler_path(opts, crashpad_path.ptr);

    // Initiate the SDK using options we set up before, and now we can use it to sent the events to Sentry.
    _ = sentry.sentry_init(opts);
    // Make sure we release all the resources before the program exits.
    defer _ = sentry.sentry_close();

    const event = sentry.sentry_value_new_message_event(sentry.SENTRY_LEVEL_INFO, "smth", "Hai");

    _ = sentry.sentry_capture_event(event);
    // std.time.sleep(std.time.ns_per_s * 10);
    @panic("AHJHHH");
    //
    // printHi();

    // ... Here you can use sentry to start transaction and attach spans to it.
    // ... Also you can capture and send errors.

}

// fn crash_function(ctx: [*c]const sentry.sentry_ucontext_t, value: sentry.sentry_value_t, user_data: ?*anyopaque) callconv(.C) sentry.sentry_value_t {
//     _ = user_data;
//     // _ = ctx;
//     const context: *std.debug.ThreadContext = switch (builtin.os.tag) {
//         .windows => @ptrCast(@alignCast(ctx.*.exception_ptrs.ContextRecord)),
//         else => @compileError("Platform not implemented"),
//     };

//     std.debug.dumpStackTraceFromBase(context);

//     return value;
// }

// pub const panic = std.debug.FullPanic(customPanicHandler);

// fn customPanicHandler(msg: []const u8, ra: ?usize) noreturn {
// std.debug.attachSegfaultHandler()
// _ = c.raise(c.SIGABRT);
// }
