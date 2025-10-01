const std = @import("std");

const c = @cImport({
    @cInclude("GLES2/gl2.h");
});

pub const Vec2 = struct { x: f32, y: f32 };
pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

const Vertex = extern struct {
    // NOTE: top-left origin pixel coords, converted in vertex shader
    x: f32,
    y: f32,
    // ABGR packed (matches normalized UNSIGNED_BYTE in ES2)
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

fn abgr(r: u8, g: u8, b: u8, a: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r);
}

pub const Style = struct {
    window_bg: u32 = abgr(30, 30, 35, 255),
    button_color: u32 = abgr(66, 150, 250, 255),
    button_hot: u32 = abgr(76, 160, 255, 255),
    button_active: u32 = abgr(56, 140, 240, 255),
    separator_color: u32 = abgr(80, 80, 90, 255),

    window_padding: Vec2 = .{ .x = 8, .y = 8 },
    item_spacing: Vec2 = .{ .x = 6, .y = 6 },
    frame_rounding: f32 = 4.0,
    frame_height: f32 = 28.0,
};

pub const Input = struct {
    mouse_pos: Vec2, // in pixels
    mouse_down: bool, // left
    mouse_pressed: bool,
    mouse_released: bool,
};

const Batch = struct {
    verts: std.ArrayList(Vertex),
    indices: std.ArrayList(u16),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Batch {
        return .{
            .verts = try std.ArrayList(Vertex).initCapacity(allocator, 4096),
            .indices = try std.ArrayList(u16).initCapacity(allocator, 8192),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Batch) void {
        self.verts.deinit(self.allocator);
        self.indices.deinit(self.allocator);
        self.* = undefined;
    }

    fn addQuad(self: *Batch, r: Rect, color: u32) !void {
        // unpack ABGR to bytes
        const r8: u8 = @intCast(color & 0xFF);
        const g8: u8 = @intCast((color >> 8) & 0xFF);
        const b8: u8 = @intCast((color >> 16) & 0xFF);
        const a8: u8 = @intCast((color >> 24) & 0xFF);

        const base: u16 = @intCast(self.verts.items.len);

        try self.verts.appendSlice(self.allocator, &[_]Vertex{
            .{ .x = r.x, .y = r.y, .r = r8, .g = g8, .b = b8, .a = a8 },
            .{ .x = r.x + r.w, .y = r.y, .r = r8, .g = g8, .b = b8, .a = a8 },
            .{ .x = r.x + r.w, .y = r.y + r.h, .r = r8, .g = g8, .b = b8, .a = a8 },
            .{ .x = r.x, .y = r.y + r.h, .r = r8, .g = g8, .b = b8, .a = a8 },
        });

        try self.indices.appendSlice(self.allocator, &[_]u16{
            base, base + 1, base + 2,
            base, base + 2, base + 3,
        });
    }
};

const Program = struct {
    prog: c.GLuint = 0,
    a_pos: c.GLint = -1,
    a_col: c.GLint = -1,
    u_screen: c.GLint = -1,
};

fn compileShader(ty: c.GLenum, src: []const u8) !c.GLuint {
    const sh = c.glCreateShader(ty);
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

fn linkProgram(vs: c.GLuint, fs: c.GLuint) !c.GLuint {
    const p = c.glCreateProgram();
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

fn makeProgram() !Program {
    const vs_src = @embedFile("shaders/gui.vert");
    const fs_src = @embedFile("shaders/gui.frag");
    const vs = try compileShader(c.GL_VERTEX_SHADER, vs_src);
    const fs = try compileShader(c.GL_FRAGMENT_SHADER, fs_src);
    const prog = try linkProgram(vs, fs);
    c.glDeleteShader(vs);
    c.glDeleteShader(fs);

    const a_pos = c.glGetAttribLocation(prog, "a_pos");
    const a_col = c.glGetAttribLocation(prog, "a_col");
    const u_screen = c.glGetUniformLocation(prog, "u_screen");

    return .{
        .prog = prog,
        .a_pos = a_pos,
        .a_col = a_col,
        .u_screen = u_screen,
    };
}

pub const Gui = struct {
    allocator: std.mem.Allocator,
    style: Style = .{},
    program: Program = .{},
    vbo: c.GLuint = 0,
    ibo: c.GLuint = 0,
    vao_like_bound: bool = false, // ES2 doesn't have VAOs
    batch: Batch,
    display_size: Vec2 = .{ .x = 0, .y = 0 },

    input: Input = .{ .mouse_pos = .{ .x = 0, .y = 0 }, .mouse_down = false, .mouse_pressed = false, .mouse_released = false },

    current: ?*Window = null,
    windows: std.ArrayList(Window),

    hot_id: u32 = 0,
    active_id: u32 = 0,

    pub const Window = struct {
        id: u32,
        rect: Rect,
        cursor: Vec2,
        content_max_x: f32,
    };

    pub fn init(allocator: std.mem.Allocator) !Gui {
        var g = Gui{
            .allocator = allocator,
            .style = .{},
            .program = try makeProgram(),
            .vbo = 0,
            .ibo = 0,
            .batch = try Batch.init(allocator),
            .windows = try std.ArrayList(Window).initCapacity(allocator, 8),
        };
        c.glGenBuffers(1, &g.vbo);
        c.glGenBuffers(1, &g.ibo);
        return g;
    }

    pub fn deinit(self: *Gui) void {
        self.batch.deinit();
        self.windows.deinit(self.allocator);
        if (self.program.prog != 0) c.glDeleteProgram(self.program.prog);
        if (self.vbo != 0) c.glDeleteBuffers(1, &self.vbo);
        if (self.ibo != 0) c.glDeleteBuffers(1, &self.ibo);
    }

    pub fn beginFrame(self: *Gui, display_w: f32, display_h: f32, input: Input) void {
        self.display_size = .{ .x = display_w, .y = display_h };
        self.input = input;
        self.batch.verts.clearRetainingCapacity();
        self.batch.indices.clearRetainingCapacity();
        self.windows.clearRetainingCapacity();
        self.current = null;
        self.hot_id = 0;
        if (!self.input.mouse_down) self.active_id = 0;
    }

    pub fn endFrame(self: *Gui) void {
        c.glUseProgram(self.program.prog);
        c.glUniform2f(self.program.u_screen, self.display_size.x, self.display_size.y);

        // No textures, just colored triangles
        c.glDisable(c.GL_CULL_FACE);
        c.glDisable(c.GL_DEPTH_TEST);
        c.glEnable(c.GL_BLEND);
        c.glBlendFuncSeparate(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA, c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);

        const vbsize = @as(c.GLsizeiptr, @intCast(self.batch.verts.items.len * @sizeOf(Vertex)));
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, vbsize, self.batch.verts.items.ptr, c.GL_DYNAMIC_DRAW);

        const ibsize = @as(c.GLsizeiptr, @intCast(self.batch.indices.items.len * @sizeOf(u16)));
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, ibsize, self.batch.indices.items.ptr, c.GL_DYNAMIC_DRAW);

        c.glEnableVertexAttribArray(@intCast(self.program.a_pos));
        c.glEnableVertexAttribArray(@intCast(self.program.a_col));
        c.glVertexAttribPointer(@intCast(self.program.a_pos), 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "x")));
        c.glVertexAttribPointer(@intCast(self.program.a_col), 4, c.GL_UNSIGNED_BYTE, c.GL_TRUE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "r")));

        if (self.batch.indices.items.len > 0) {
            c.glDrawElements(c.GL_TRIANGLES, @intCast(self.batch.indices.items.len), c.GL_UNSIGNED_SHORT, @ptrFromInt(0));
        }

        c.glDisableVertexAttribArray(@intCast(self.program.a_pos));
        c.glDisableVertexAttribArray(@intCast(self.program.a_col));
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);
        c.glUseProgram(0);
        c.glDisable(c.GL_SCISSOR_TEST);
    }

    pub fn beginWindow(self: *Gui, id: u32, rect: Rect) void {
        const w = Window{
            .id = id,
            .rect = rect,
            .cursor = .{ .x = rect.x + self.style.window_padding.x, .y = rect.y + self.style.window_padding.y },
            .content_max_x = rect.x + self.style.window_padding.x,
        };
        _ = self.batch.addQuad(rect, self.style.window_bg) catch {};
        self.windows.append(self.allocator, w) catch {};
        self.current = &self.windows.items[self.windows.items.len - 1];

        c.glEnable(c.GL_SCISSOR_TEST);
        const y_flipped = self.display_size.y - rect.y - rect.h;
        c.glScissor(@intFromFloat(rect.x), @intFromFloat(y_flipped), @intFromFloat(rect.w), @intFromFloat(rect.h));
    }

    pub fn endWindow(self: *Gui) void {
        if (self.windows.items.len > 0) {
            _ = self.windows.pop();
            self.current = if (self.windows.items.len > 0) &self.windows.items[self.windows.items.len - 1] else null;
            if (self.current == null) {
                c.glDisable(c.GL_SCISSOR_TEST);
            } else {
                const r = self.current.?.rect;
                const y_flipped = self.display_size.y - r.y - r.h;
                c.glScissor(@intFromFloat(r.x), @intFromFloat(y_flipped), @intFromFloat(r.w), @intFromFloat(r.h));
            }
        }
    }
};
