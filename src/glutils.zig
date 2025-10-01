const std = @import("std");

const c = @cImport({
    @cInclude("GLES2/gl2.h");
});

pub fn compileShader(ty: c.GLenum, src: []const u8) !c.GLuint {
    const sh = c.glCreateShader(ty);
    errdefer c.glDeleteShader(sh);
    c.glShaderSource(sh, 1, @as([*c]const [*c]const u8, @ptrCast(&src)), null);
    c.glCompileShader(sh);
    var status: c.GLint = 0;
    c.glGetShaderiv(sh, c.GL_COMPILE_STATUS, &status);
    if (status == 0) {
        var buffer: [4096]u8 = undefined;
        var size: c.GLsizei = undefined;
        c.glGetShaderInfoLog(sh, 4096, &size, &buffer);
        std.log.err("\nFailed to compile shader: {s}\n", .{buffer[0..@as(usize, @intCast(size))]});
        return error.GLFailedToCompileShader;
    }
    return sh;
}

pub fn linkProgram(vs: c.GLuint, fs: c.GLuint) !c.GLuint {
    const p = c.glCreateProgram();
    errdefer c.glDeleteProgram(p);
    c.glAttachShader(p, vs);
    c.glAttachShader(p, fs);
    c.glLinkProgram(p);
    var status: c.GLint = 0;
    c.glGetProgramiv(p, c.GL_LINK_STATUS, &status);
    if (status == 0) {
        var buffer: [4096]u8 = undefined;
        var size: c.GLsizei = undefined;
        c.glGetProgramInfoLog(p, 4096, &size, &buffer);
        std.log.err("\nFailed to link program: {s}\n", .{buffer[0..@as(usize, @intCast(size))]});
        return error.GLFailedToLinkProgram;
    }
    return p;
}

pub fn compileProgram(vertex_source: []const u8, fragment_source: []const u8) !c.GLuint {
    const vertex_shader = try compileShader(c.GL_VERTEX_SHADER, vertex_source);
    defer c.glDeleteShader(vertex_shader);

    const fragment_shader = try compileShader(c.GL_FRAGMENT_SHADER, fragment_source);
    defer c.glDeleteShader(fragment_shader);

    return try linkProgram(vertex_shader, fragment_shader);
}
