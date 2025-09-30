const std = @import("std");
const builtin = @import("builtin");
const android = @import("android");
const android_binds = @import("android_binds.zig");
const AndroidApp = @import("AndroidApp.zig").AndroidApp;

pub const MainActivity = struct {
    const Self = @This();

    app: *AndroidApp,
    allocator: std.mem.Allocator,

    pub fn init(activity: *android_binds.ANativeActivity, savedState: []const u8, allocator: std.mem.Allocator) !Self {
        const app = try allocator.create(AndroidApp);
        errdefer allocator.destroy(app);

        activity.callbacks.* = setupNativeActivityMatress(AndroidApp);
        app.* = try AndroidApp.init(allocator, activity, savedState);

        try app.start();
        activity.instance = app;

        return .{
            .app = app,
            .allocator = allocator,
        };
    }

    /// Setups at comptime all native activity functions with safe try and fail system for non implemented ones
    fn setupNativeActivityMatress(comptime App: type) android_binds.ANativeActivityCallbacks {
        const T = struct {
            fn invoke(activity: *android_binds.ANativeActivity, comptime func: []const u8, args: anytype) void {
                if (!@hasDecl(App, func)) {
                    std.log.debug("ANativeActivity callback {s} not available on {s}", .{ func, @typeName(App) });
                    return;
                }
                const instance = activity.instance orelse return;
                const result = @call(.auto, @field(App, func), .{@as(*App, @ptrCast(@alignCast(instance)))} ++ args);
                switch (@typeInfo(@TypeOf(result))) {
                    .error_union => result catch |err| std.log.err("{s} returned error {s}", .{ func, @errorName(err) }),
                    .void => {},
                    .error_set => std.log.err("{s} returned error {s}", .{ func, @errorName(result) }),
                    else => @compileError("callback must return void"),
                }
            }

            fn onSaveInstanceState(activity: *android_binds.ANativeActivity, outSize: *usize) callconv(.c) ?[*]u8 {
                outSize.* = 0;
                if (!@hasDecl(App, "onSaveInstanceState")) {
                    std.log.debug("ANativeActivity callback onSaveInstanceState not available on {s}", .{@typeName(App)});
                    return null;
                }
                const instance = activity.instance orelse return null;
                const optional_slice = @as(*App, @ptrCast(instance)).onSaveInstanceState(std.heap.c_allocator);
                if (optional_slice) |slice| {
                    outSize.* = slice.len;
                    return slice.ptr;
                }
                return null;
            }

            fn onDestroy(activity: *android_binds.ANativeActivity) callconv(.c) void {
                const instance = activity.instance orelse return;
                const app: *App = @ptrCast(@alignCast(instance));
                app.deinit();
                std.heap.c_allocator.destroy(app);
            }
            fn onStart(activity: *android_binds.ANativeActivity) callconv(.c) void {
                invoke(activity, "onStart", .{});
            }
            fn onResume(activity: *android_binds.ANativeActivity) callconv(.c) void {
                invoke(activity, "onResume", .{});
            }
            fn onPause(activity: *android_binds.ANativeActivity) callconv(.c) void {
                invoke(activity, "onPause", .{});
            }
            fn onStop(activity: *android_binds.ANativeActivity) callconv(.c) void {
                invoke(activity, "onStop", .{});
            }
            fn onConfigurationChanged(activity: *android_binds.ANativeActivity) callconv(.c) void {
                invoke(activity, "onConfigurationChanged", .{});
            }
            fn onLowMemory(activity: *android_binds.ANativeActivity) callconv(.c) void {
                invoke(activity, "onLowMemory", .{});
            }
            fn onWindowFocusChanged(activity: *android_binds.ANativeActivity, hasFocus: c_int) callconv(.c) void {
                invoke(activity, "onWindowFocusChanged", .{(hasFocus != 0)});
            }
            fn onNativeWindowCreated(activity: *android_binds.ANativeActivity, window: *android_binds.ANativeWindow) callconv(.c) void {
                invoke(activity, "onNativeWindowCreated", .{window});
            }
            fn onNativeWindowResized(activity: *android_binds.ANativeActivity, window: *android_binds.ANativeWindow) callconv(.c) void {
                invoke(activity, "onNativeWindowResized", .{window});
            }
            fn onNativeWindowRedrawNeeded(activity: *android_binds.ANativeActivity, window: *android_binds.ANativeWindow) callconv(.c) void {
                invoke(activity, "onNativeWindowRedrawNeeded", .{window});
            }
            fn onNativeWindowDestroyed(activity: *android_binds.ANativeActivity, window: *android_binds.ANativeWindow) callconv(.c) void {
                invoke(activity, "onNativeWindowDestroyed", .{window});
            }
            fn onInputQueueCreated(activity: *android_binds.ANativeActivity, input_queue: *android_binds.AInputQueue) callconv(.c) void {
                invoke(activity, "onInputQueueCreated", .{input_queue});
            }
            fn onInputQueueDestroyed(activity: *android_binds.ANativeActivity, input_queue: *android_binds.AInputQueue) callconv(.c) void {
                invoke(activity, "onInputQueueDestroyed", .{input_queue});
            }
            fn onContentRectChanged(activity: *android_binds.ANativeActivity, rect: *const android_binds.ARect) callconv(.c) void {
                invoke(activity, "onContentRectChanged", .{rect});
            }
        };
        return android_binds.ANativeActivityCallbacks{
            .onStart = T.onStart,
            .onResume = T.onResume,
            .onSaveInstanceState = T.onSaveInstanceState,
            .onPause = T.onPause,
            .onStop = T.onStop,
            .onDestroy = T.onDestroy,
            .onWindowFocusChanged = T.onWindowFocusChanged,
            .onNativeWindowCreated = T.onNativeWindowCreated,
            .onNativeWindowResized = T.onNativeWindowResized,
            .onNativeWindowRedrawNeeded = T.onNativeWindowRedrawNeeded,
            .onNativeWindowDestroyed = T.onNativeWindowDestroyed,
            .onInputQueueCreated = T.onInputQueueCreated,
            .onInputQueueDestroyed = T.onInputQueueDestroyed,
            .onContentRectChanged = T.onContentRectChanged,
            .onConfigurationChanged = T.onConfigurationChanged,
            .onLowMemory = T.onLowMemory,
        };
    }
};
