const std = @import("std");
const builtin = @import("builtin");
const android_binds = @import("android_binds.zig");

const c = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("GLES2/gl2.h");
    @cInclude("GLES2/gl2ext.h");
});

pub const Version = enum {
    gles2,
    gles3,
};

const Self = @This();

display: c.EGLDisplay,
surface: c.EGLSurface,
context: c.EGLContext,

pub fn init(window: *android_binds.ANativeWindow, version: Version) !Self {
    const EGLint = c.EGLint;

    std.log.debug("Creating EGLContext", .{});

    const egl_display = c.eglGetDisplay(null);
    if (egl_display == null) {
        std.log.err("Error: No display found!\n", .{});
        return error.FailedToInitializeEGL;
    }

    var egl_major: EGLint = undefined;
    var egl_minor: EGLint = undefined;
    if (c.eglInitialize(egl_display, &egl_major, &egl_minor) == 0) {
        std.log.err("Error: eglInitialise failed!\n", .{});
        return error.FailedToInitializeEGL;
    }

    std.log.info(
        \\EGL Version:    {s}
        \\EGL Vendor:     {s}
        \\EGL Extensions: {s}
        \\
    , .{
        std.mem.span(c.eglQueryString(egl_display, c.EGL_VERSION)),
        std.mem.span(c.eglQueryString(egl_display, c.EGL_VENDOR)),
        std.mem.span(c.eglQueryString(egl_display, c.EGL_EXTENSIONS)),
    });

    const config_attribute_list = [_]EGLint{
        c.EGL_RED_SIZE,
        8,
        c.EGL_GREEN_SIZE,
        8,
        c.EGL_BLUE_SIZE,
        8,
        c.EGL_ALPHA_SIZE,
        8,
        c.EGL_BUFFER_SIZE,
        32,
        c.EGL_STENCIL_SIZE,
        0,
        c.EGL_DEPTH_SIZE,
        16,
        // c.EGL_SAMPLES, 1,
        c.EGL_RENDERABLE_TYPE,
        switch (version) {
            .gles3 => c.EGL_OPENGL_ES3_BIT,
            .gles2 => c.EGL_OPENGL_ES2_BIT,
        },
        c.EGL_NONE,
    };

    var config: c.EGLConfig = undefined;
    var num_config: c.EGLint = undefined;
    if (c.eglChooseConfig(egl_display, &config_attribute_list, &config, 1, &num_config) == c.EGL_FALSE) {
        std.log.err("Error: eglChooseConfig failed: 0x{X:0>4}\n", .{c.eglGetError()});
        return error.FailedToInitializeEGL;
    }

    const context_attribute_list = [_]EGLint{ c.EGL_CONTEXT_CLIENT_VERSION, 2, c.EGL_NONE };

    const context = c.eglCreateContext(egl_display, config, null, &context_attribute_list) orelse {
        std.log.err("Error: eglCreateContext failed: 0x{X:0>4}\n", .{c.eglGetError()});
        return error.FailedToInitializeEGL;
    };
    errdefer _ = c.eglDestroyContext(egl_display, context);

    std.log.info("Context created: {?}\n", .{context});

    const native_window: c.EGLNativeWindowType = @ptrCast(window); // This is safe, just a C import problem

    const window_attribute_list = [_]EGLint{c.EGL_NONE};
    const egl_surface = c.eglCreateWindowSurface(egl_display, config, native_window, &window_attribute_list) orelse {
        std.log.err("Error: eglCreateWindowSurface failed: 0x{X:0>4}\n", .{c.eglGetError()});
        return error.FailedToInitializeEGL;
    };
    errdefer _ = c.eglDestroySurface(egl_display, context);

    std.log.info("Got Surface: {}\n", .{egl_surface});
    std.log.debug("Created EGLContext", .{});

    return Self{
        .display = egl_display,
        .surface = egl_surface,
        .context = context,
    };
}

pub fn deinit(self: *Self) void {
    _ = c.eglDestroySurface(self.display, self.surface);
    _ = c.eglDestroyContext(self.display, self.context);
    self.* = undefined;
}

pub fn swapBuffers(self: *const Self) !void {
    if (c.eglSwapBuffers(self.display, self.surface) == c.EGL_FALSE) {
        std.log.err("Error: eglMakeCurrent failed: 0x{X:0>4}\n", .{c.eglGetError()});
        return error.EglFailure;
    }
}

pub fn makeCurrent(self: *const Self) !void {
    if (c.eglMakeCurrent(self.display, self.surface, self.surface, self.context) == c.EGL_FALSE) {
        std.log.err("Error: eglMakeCurrent failed: 0x{X:0>4}\n", .{c.eglGetError()});
        return error.EglFailure;
    }
}

pub fn release(self: *const Self) void {
    if (c.eglMakeCurrent(self.display, self.surface, self.surface, null) == c.EGL_FALSE) {
        std.log.err("Error: eglMakeCurrent failed: 0x{X:0>4}\n", .{c.eglGetError()});
    }
}
