const std = @import("std");
const android = @import("android");
const builtin = @import("builtin");
const android_binds = @import("android_binds.zig");
const MainActivity = @import("MainActivity.zig").MainActivity;

comptime {
    if (builtin.abi.isAndroid()) {
        @export(&NativeActivity_onCreate, .{ .name = "ANativeActivity_onCreate" });
    } else {
        @compileError("This program can only run on Android");
    }
}

/// Custom standard options for Android
pub const std_options: std.Options = if (builtin.abi.isAndroid())
    .{ .logFn = android.logFn }
else
    .{};

/// Custom panic handler for Android
pub const panic = if (builtin.abi.isAndroid())
    android.panic
else
    std.debug.FullPanic(std.debug.defaultPanic);

/// Android entry point
fn NativeActivity_onCreate(activity: *android_binds.ANativeActivity, rawSavedState: ?[*]u8, rawSavedStateSize: usize) callconv(.c) void {
    const savedState: []const u8 = if (rawSavedState) |s|
        s[0..rawSavedStateSize]
    else
        &[0]u8{};

    const allocator = std.heap.c_allocator;
    var main_activity = MainActivity.init(activity, savedState, allocator) catch |err| {
        std.log.err("ANativeActivity_onCreate: error within nativeActivityOnCreate: {s}", .{@errorName(err)});
        return;
    };
    defer main_activity.deinit();
}
