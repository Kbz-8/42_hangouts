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

fn loadShader(kind: c.GLenum, code: []const u8) !c.GLuint {
    var compiled: c.GLuint = undefined;

    const shader: c.GLuint = c.glCreateShader(kind);
    if (shader == 0)
        return error.GLFailedToCreateShader;
    c.glShaderSource(shader, 1, @as([*c]const [*c]const u8, @ptrCast(&code)), null);
    c.glCompileShader(shader);
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, @ptrCast(&compiled));
    if (compiled == 0) {
        var buffer: [4096]u8 = undefined;
        var size: c.GLsizei = undefined;
        c.glGetShaderInfoLog(shader, 4096, &size, &buffer);
        std.log.err("\nFailed to compile shader: {s}\n", .{buffer[0..@as(usize, @intCast(size))]});
        return error.GLFailedToCompileShader;
    }
    return shader;
}

pub const AndroidApp = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    activity: *android_binds.ANativeActivity,
    thread: ?std.Thread = null,

    screen_width: i32 = undefined,
    screen_height: i32 = undefined,

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
        var shader_init = false;
        var program: c.GLuint = undefined;

        while (@atomicLoad(bool, &self.running, .seq_cst)) {
            self.egl_lock.lock();
            defer self.egl_lock.unlock();

            if (self.egl) |egl| {
                try egl.makeCurrent();
                std.log.debug("test1", .{});

                if (!shader_init) {
                    const vertex_shader_code =
                        \\ #version 100
                        \\
                        \\ attribute vec3 aPos;
                        \\
                        \\ void main()
                        \\ {
                        \\     gl_Position = vec4(aPos, 1.0);
                        \\ }
                    ;
                    const fragment_shader_code =
                        \\ #version 100
                        \\ precision mediump float;
                        \\
                        \\ void main()
                        \\ {
                        \\     gl_FragColor = vec4(1.0, 0.5, 0.2, 1.0);
                        \\ }
                    ;

                    const vertex_shader = try loadShader(c.GL_VERTEX_SHADER, vertex_shader_code);
                    const fragment_shader = try loadShader(c.GL_FRAGMENT_SHADER, fragment_shader_code);

                    program = c.glCreateProgram();
                    if (program == 0)
                        return error.GLFailedToCreateProgram;

                    c.glAttachShader(program, vertex_shader);
                    c.glAttachShader(program, fragment_shader);
                    c.glBindAttribLocation(program, 0, "aPos");
                    c.glLinkProgram(program);

                    var linked: c.GLuint = undefined;
                    c.glGetShaderiv(program, c.GL_LINK_STATUS, @ptrCast(&linked));
                    if (linked == 0) {
                        var buffer: [4096]u8 = undefined;
                        var size: c.GLsizei = undefined;
                        c.glGetProgramInfoLog(program, 4096, &size, &buffer);
                        std.log.err("\nFailed to link program: {s}\n", .{buffer[0..@as(usize, @intCast(size))]});
                        return error.GLFailedToLinkProgram;
                    }
                    shader_init = true;
                    std.log.debug("test2", .{});
                }

                const vertices = [_]c.GLfloat{ 0.0, 0.5, 0.0, -0.5, -0.5, 0.0, 0.5, -0.5, 0.0 };

                std.log.debug("test3", .{});
                c.glViewport(0, 0, self.screen_width, self.screen_height);
                std.log.debug("test4", .{});
                c.glClearColor(0.2, 0.3, 0.3, 1.0);
                std.log.debug("test5", .{});
                c.glClear(c.GL_COLOR_BUFFER_BIT);
                std.log.debug("test6", .{});
                c.glUseProgram(program);
                std.log.debug("test7", .{});
                c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 0, @ptrCast(&vertices));
                std.log.debug("test8", .{});
                c.glEnableVertexAttribArray(0);
                std.log.debug("test9", .{});
                c.glDrawArrays(c.GL_TRIANGLES, 0, 3);
                std.log.debug("test0", .{});

                try egl.swapBuffers();
                std.log.debug("test10", .{});
            }
        }
        std.log.debug("test11", .{});
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
