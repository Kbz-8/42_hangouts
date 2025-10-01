const std = @import("std");
const builtin = @import("builtin");
const android = @import("android");
const zm = @import("zmath");
const android_binds = @import("android_binds.zig");
const EGLContext = @import("EGLContext.zig").EGLContext;
const mini_gui = @import("mini_gui.zig");

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

    screen_width: i32 = undefined,
    screen_height: i32 = undefined,

    egl_lock: std.Thread.Mutex = .{},
    egl: ?EGLContext = null,
    egl_init: bool = true,

    running: bool = true,

    pub fn init(allocator: std.mem.Allocator, activity: *android_binds.ANativeActivity, _: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .activity = activity,
        };
    }

    pub fn start(self: *Self) !void {
        std.log.debug("Started ft_hangouts", .{});
        self.thread = try std.Thread.spawn(.{}, localThread, .{self});
    }

    pub fn onNativeWindowCreated(self: *Self, window: *android_binds.ANativeWindow) void {
        self.egl_lock.lock();
        defer self.egl_lock.unlock();
        if (self.egl) |*old| {
            old.deinit();
        }

        self.screen_width = android_binds.ANativeWindow_getWidth(window);
        self.screen_height = android_binds.ANativeWindow_getHeight(window);

        self.egl = EGLContext.init(window, .gles2) catch |err| blk: {
            std.log.err("Failed to initialize EGL for window: {}\n", .{err});
            break :blk null;
        };
        self.egl_init = true;
    }

    pub fn onNativeWindowResized(self: *Self, window: *android_binds.ANativeWindow) void {
        self.screen_width = android_binds.ANativeWindow_getWidth(window);
        self.screen_height = android_binds.ANativeWindow_getHeight(window);
    }

    pub fn onNativeWindowDestroyed(self: *Self, _: *android_binds.ANativeWindow) void {
        self.egl_lock.lock();
        defer self.egl_lock.unlock();

        if (self.egl) |*old| {
            old.deinit();
        }
        self.egl = null;
    }

    fn localThread(self: *Self) void {
        mainLoop(self) catch |err| {
            std.log.err("\nError catched in main loop: {}\n", .{err});
            return;
        };
    }

    fn mainLoop(self: *Self) !void {
        var gui: mini_gui.Gui = undefined;
        //defer gui.deinit();

        while (@atomicLoad(bool, &self.running, .seq_cst)) {
            self.egl_lock.lock();
            defer self.egl_lock.unlock();

            if (self.egl) |egl| {
                try egl.makeCurrent();

                if (self.egl_init) {
                    gui = try mini_gui.Gui.init(std.heap.c_allocator);
                    self.egl_init = false;
                }

                c.glViewport(0, 0, self.screen_width, self.screen_height);
                c.glClearColor(0.2, 0.3, 0.3, 1.0);
                c.glClear(c.GL_COLOR_BUFFER_BIT);

                try egl.swapBuffers();
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
