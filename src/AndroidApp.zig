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

const TouchState = enum { idle, pressed, released };

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

    input_lock: std.Thread.Mutex = .{},
    input: ?*android_binds.AInputQueue = null,

    touch_x: ?f32 = null,
    touch_y: ?f32 = null,
    touch_state: TouchState = .idle,

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

    pub fn onInputQueueCreated(self: *Self, input: *android_binds.AInputQueue) void {
        self.input_lock.lock();
        defer self.input_lock.unlock();

        self.input = input;
    }

    pub fn onInputQueueDestroyed(self: *Self, _: *android_binds.AInputQueue) void {
        self.input_lock.lock();
        defer self.input_lock.unlock();

        self.input = null;
    }

    fn processMotionEvent(self: *Self, event: *android_binds.AInputEvent) !bool {
        const event_type: android_binds.AMotionEventActionType = @enumFromInt(android_binds.AMotionEvent_getAction(event));
        const cnt = android_binds.AMotionEvent_getPointerCount(event);
        if (cnt >= 1) {
            self.touch_x = android_binds.AMotionEvent_getX(event, 0);
            self.touch_y = android_binds.AMotionEvent_getY(event, 0);
            if (event_type == .AMOTION_EVENT_ACTION_DOWN) {
                self.touch_state = .pressed;
            } else if (event_type == .AMOTION_EVENT_ACTION_UP) {
                self.touch_state = .released;
            } else {
                self.touch_state = .idle;
            }
        }
        return false;
    }

    fn localThread(self: *Self) void {
        mainLoop(self) catch |err| {
            std.log.err("\nError catched in main loop: {}\n", .{err});
            return;
        };
    }

    fn mainLoop(self: *Self) !void {
        var gui_context: ?mini_gui.Gui = null;
        defer {
            if (gui_context) |*gui|
                gui.deinit();
        }

        while (@atomicLoad(bool, &self.running, .seq_cst)) {
            // Inputs processing
            {
                self.input_lock.lock();
                defer self.input_lock.unlock();

                if (self.input) |input| {
                    var event: ?*android_binds.AInputEvent = undefined;
                    while (android_binds.AInputQueue_getEvent(input, &event) >= 0) {
                        std.debug.assert(event != null);
                        if (android_binds.AInputQueue_preDispatchEvent(input, event) != 0) {
                            continue;
                        }

                        const event_type: android_binds.AInputEventType = @enumFromInt(android_binds.AInputEvent_getType(event));
                        const handled = switch (event_type) {
                            .AINPUT_EVENT_TYPE_KEY => true,
                            .AINPUT_EVENT_TYPE_MOTION => try self.processMotionEvent(event.?),

                            else => blk: {
                                std.log.debug("Unhandled input event type ({})\n", .{event_type});
                                break :blk false;
                            },
                        };

                        android_binds.AInputQueue_finishEvent(input, event, if (handled) @as(c_int, 1) else @as(c_int, 0));
                    }
                }
            }

            // Rendering
            {
                self.egl_lock.lock();
                defer self.egl_lock.unlock();

                if (self.egl) |egl| {
                    try egl.makeCurrent();

                    if (self.egl_init) {
                        gui_context = try mini_gui.Gui.init(self.allocator);
                        self.egl_init = false;
                    }

                    c.glViewport(0, 0, self.screen_width, self.screen_height);
                    c.glClearColor(0.2, 0.3, 0.3, 1.0);
                    c.glClear(c.GL_COLOR_BUFFER_BIT);

                    if (gui_context) |*gui| {
                        gui.beginFrame(@floatFromInt(self.screen_width), @floatFromInt(self.screen_height), .{
                            .mouse_pos = .{ .x = self.touch_x orelse 0, .y = self.touch_y orelse 0 },
                            .mouse_down = self.touch_state == .pressed,
                            .mouse_released = self.touch_state == .released,
                        });

                        if (gui.beginWindow(mini_gui.Gui.hashId("main"), .{ .x = 100, .y = 100, .w = 720, .h = 400 })) {
                            if (gui.button(mini_gui.Gui.hashId("Play"), .{ .x = 320, .y = 28 })) {}
                            gui.sameLine(null);
                            if (gui.button(mini_gui.Gui.hashId("Stop"), .{ .x = 320, .y = 28 })) {}

                            gui.separator();

                            if (gui.buttonWidth(mini_gui.Gui.hashId("WideButton"), 260)) {}

                            gui.endWindow();
                        }
                        gui.endFrame();
                    }

                    try egl.swapBuffers();
                }
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
