const std = @import("std");

const c = @cImport({
    @cInclude("GLES2/gl2.h");
});

fn glEnumShaderName(e: c.GLenum) []const u8 {
    return switch (e) {
        c.GL_VERTEX_SHADER => "vertex",
        c.GL_FRAGMENT_SHADER => "fragment",
        else => "unknown",
    };
}

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
        std.log.err("\nFailed to compile {s} shader: {s}\n", .{ glEnumShaderName(ty), buffer[0..@as(usize, @intCast(size))] });
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

pub fn typeToGLenum(comptime T: type) c.GLenum {
    return switch (@typeInfo(T)) {
        .vector => |v| typeToGLenum(v.child),
        .array => |a| typeToGLenum(a.child),
        .float => |f| switch (f.bits) {
            32 => c.GL_FLOAT,
            64 => @compileError("f64 isn't representable in GLES2 core (no GL_DOUBLE)."),
            else => @compileError("Unsupported float width for GLES2."),
        },
        .int => |i| switch (i.bits) {
            8 => if (i.signedness == .signed) c.GL_BYTE else c.GL_UNSIGNED_BYTE,
            16 => if (i.signedness == .signed) c.GL_SHORT else c.GL_UNSIGNED_SHORT,
            32 => if (i.signedness == .signed) c.GL_INT else c.GL_UNSIGNED_INT, // Note: valid enum; not valid for glVertexAttribPointer
            else => @compileError("Unsupported signed int width for GLES2."),
        },
        .bool => c.GL_BOOL, // Exists in GLES2; useful for uniforms
        .comptime_int => @compileError("Use a concrete int type (e.g. i32/u32)."),
        .comptime_float => @compileError("Use a concrete float type (e.g. f32)."),
        else => @compileError("Unhandled type for GLES2 mapping."),
    };
}
