const std = @import("std");
const builtin = @import("builtin");
const android = @import("android");
const android_binds = @import("android_binds.zig");
const EGLContext = @import("EGLContext.zig").EGLContext;

const c = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("GLES2/gl2.h");
    @cInclude("GLES2/gl2ext.h");
});

pub const AndroidApp = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    activity: *android_binds.ANativeActivity,
    thread: ?std.Thread = null,

    egl_lock: std.Thread.Mutex = .{},
    egl: ?EGLContext = null,

    running: bool = true,

    pub fn init(allocator: std.mem.Allocator, activity: *android_binds.ANativeActivity, _: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .activity = activity,
        };
    }

    pub fn start(self: *Self) !void {
        std.log.debug("Started ft_hangouts", .{});
        self.thread = try std.Thread.spawn(.{}, mainLoop, .{self});
    }

    pub fn onNativeWindowCreated(self: *Self, window: *android_binds.ANativeWindow) void {
        self.egl_lock.lock();
        defer self.egl_lock.unlock();

        if (self.egl) |*old| {
            old.deinit();
        }
        self.egl = EGLContext.init(window, .gles2) catch |err| blk: {
            std.log.err("Failed to initialize EGL for window: {}\n", .{err});
            break :blk null;
        };
    }

    pub fn onNativeWindowDestroyed(self: *Self, _: *android_binds.ANativeWindow) void {
        self.egl_lock.lock();
        defer self.egl_lock.unlock();

        if (self.egl) |*old| {
            old.deinit();
        }
        self.egl = null;
    }

    fn mainLoop(self: *Self) !void {
        while (@atomicLoad(bool, &self.running, .seq_cst)) {
            self.egl_lock.lock();
            defer self.egl_lock.unlock();
            if (self.egl) |egl| {
                try egl.makeCurrent();
                std.log.info("test", .{});
            }
        }
    }

    pub fn deinit(self: *Self) void {
        @atomicStore(bool, &self.running, false, .seq_cst);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        self.* = undefined;
        std.log.debug("Exited ft_hangouts", .{});
    }
};
