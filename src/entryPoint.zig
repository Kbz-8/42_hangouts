const std = @import("std");
const android = @import("android");
const builtin = @import("builtin");
const android_binds = @import("android_binds.zig");
const MainActivity = @import("MainActivity.zig");

comptime {
    if (builtin.abi.isAndroid()) {
        @export(&nativeActivityOnCreate, .{ .name = "ANativeActivity_onCreate" });
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
fn nativeActivityOnCreate(activity: *android_binds.ANativeActivity, rawSavedState: ?[*]u8, rawSavedStateSize: usize) callconv(.c) void {
    const savedState: []const u8 = if (rawSavedState) |s|
        s[0..rawSavedStateSize]
    else
        &[0]u8{};

    _ = MainActivity.init(activity, savedState) catch |err| {
        std.log.err("ANativeActivity_onCreate: error within nativeActivityOnCreate: {s}", .{@errorName(err)});
        return;
    };
}
