const std = @import("std");
const zm = @import("zmath");
const glutils = @import("glutils.zig");

const c = @cImport({
    @cInclude("GLES2/gl2.h");
});

pub const Vec2 = struct { x: f32, y: f32 };
pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

const Vertex = packed struct {
    pos: @Vector(2, f32),
    col: @Vector(4, u8),
    uv: @Vector(2, f32),
    is_textured: f32, // boolean
};

fn abgr(r: u8, g: u8, b: u8, a: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r);
}

pub const Style = struct {
    window_bg: u32 = abgr(30, 30, 35, 255),
    button_color: u32 = abgr(66, 150, 250, 255),
    button_active: u32 = abgr(6, 80, 200, 255),
    separator_color: u32 = abgr(80, 80, 90, 255),

    window_padding: Vec2 = .{ .x = 8, .y = 8 },
    item_spacing: Vec2 = .{ .x = 6, .y = 6 },
    frame_rounding: f32 = 4.0,
    frame_height: f32 = 28.0,
};

pub const Input = struct {
    mouse_pos: Vec2,
    mouse_down: bool,
    mouse_released: bool,
};

fn componentCount(comptime T: type) comptime_int {
    const ti = @typeInfo(T);
    return switch (ti) {
        .vector => |v| v.len,
        else => 1,
    };
}

const Batch = struct {
    const Self = @This();

    verts: std.ArrayList(Vertex),
    indices: std.ArrayList(u16),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var self: Self = .{
            .allocator = allocator,
            .verts = undefined,
            .indices = undefined,
        };
        self.indices = try std.ArrayList(u16).initCapacity(allocator, 8192);
        errdefer self.indices.deinit(allocator);
        self.verts = try std.ArrayList(Vertex).initCapacity(allocator, 4096);
        errdefer self.verts.deinit(allocator);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.verts.deinit(self.allocator);
        self.indices.deinit(self.allocator);
        self.* = undefined;
    }

    fn pushQuad(self: *Self, v: [4]Vertex) !void {
        const base: u16 = @intCast(self.verts.items.len);
        try self.verts.appendSlice(self.allocator, &v);
        try self.indices.appendSlice(self.allocator, &[_]u16{
            base, base + 1, base + 2,
            base, base + 2, base + 3,
        });
    }

    fn addQuad(self: *Self, r: Rect, color: u32) !void {
        const r8: u8 = @intCast(color & 0xFF);
        const g8: u8 = @intCast((color >> 8) & 0xFF);
        const b8: u8 = @intCast((color >> 16) & 0xFF);
        const a8: u8 = @intCast((color >> 24) & 0xFF);
        // zig fmt: off
        try self.pushQuad(.{
            .{ .pos = .{ r.x,       r.y       }, .col = .{ r8, g8, b8, a8 }, .uv = .{ 0, 0 }, .is_textured = 0 },
            .{ .pos = .{ r.x + r.w, r.y       }, .col = .{ r8, g8, b8, a8 }, .uv = .{ 0, 0 }, .is_textured = 0 },
            .{ .pos = .{ r.x + r.w, r.y + r.h }, .col = .{ r8, g8, b8, a8 }, .uv = .{ 0, 0 }, .is_textured = 0 },
            .{ .pos = .{ r.x,       r.y + r.h }, .col = .{ r8, g8, b8, a8 }, .uv = .{ 0, 0 }, .is_textured = 0 },
        });
        // zig fmt: on
    }

    fn addTexturedQuad(self: *Self, r: Rect, u_0: f32, v_0: f32, u_1: f32, v_1: f32, color: u32) !void {
        const r8: u8 = @intCast(color & 0xFF);
        const g8: u8 = @intCast((color >> 8) & 0xFF);
        const b8: u8 = @intCast((color >> 16) & 0xFF);
        const a8: u8 = @intCast((color >> 24) & 0xFF);
        // zig fmt: off
        try self.pushQuad(.{
            .{ .pos = .{ r.x,       r.y       }, .col = .{ r8, g8, b8, a8 }, .uv = .{ u_0, v_0 }, .is_textured = 1 },
            .{ .pos = .{ r.x + r.w, r.y       }, .col = .{ r8, g8, b8, a8 }, .uv = .{ u_1, v_0 }, .is_textured = 1 },
            .{ .pos = .{ r.x + r.w, r.y + r.h }, .col = .{ r8, g8, b8, a8 }, .uv = .{ u_1, v_1 }, .is_textured = 1 },
            .{ .pos = .{ r.x,       r.y + r.h }, .col = .{ r8, g8, b8, a8 }, .uv = .{ u_0, v_1 }, .is_textured = 1 },
        });
        // zig fmt: on
    }
};

const GuiProgram = struct {
    prog: c.GLuint = 0,
    a: struct {
        pos: c.GLint = -1,
        col: c.GLint = -1,
        uv: c.GLint = -1,
        is_textured: c.GLint = -1,
    } = .{},
    u: struct {
        screen: c.GLint = -1,
        texture: c.GLint = -1,
    } = .{},
};

pub const Gui = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    style: Style = .{},
    program: GuiProgram = .{},
    vbo: c.GLuint = 0,
    ibo: c.GLuint = 0,
    batch: Batch,
    display_size: Vec2 = .{ .x = 0, .y = 0 },
    last_height_size: f32 = 0,

    input: Input = .{ .mouse_pos = .{ .x = 0, .y = 0 }, .mouse_down = false, .mouse_released = false },

    current: ?*Window = null,
    windows: std.ArrayList(Window),

    active_id: u32 = 0,

    pub const Window = struct {
        id: u32,
        rect: Rect,
        cursor: Vec2,
        content_max_x: f32,
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        var self: Self = .{
            .allocator = allocator,
            .style = .{},
            .batch = undefined,
            .windows = undefined,
            .vbo = 0,
            .ibo = 0,
        };

        const vertex_source = @embedFile("shaders/gui.vert");
        const fragment_source = @embedFile("shaders/gui.frag");

        const program = try glutils.compileProgram(vertex_source, fragment_source);
        errdefer c.glDeleteProgram(self.program.prog);

        self.program = .{ .prog = program };
        inline for (std.meta.fields(@TypeOf(self.program.a))) |f| {
            @field(self.program.a, f.name) = c.glGetAttribLocation(self.program.prog, "a_" ++ f.name);
        }
        inline for (std.meta.fields(@TypeOf(self.program.u))) |f| {
            @field(self.program.u, f.name) = c.glGetAttribLocation(self.program.prog, "u_" ++ f.name);
        }

        self.batch = try Batch.init(allocator);
        errdefer self.batch.deinit();
        self.windows = try std.ArrayList(Window).initCapacity(allocator, 8);
        errdefer self.windows.deinit(allocator);
        c.glGenBuffers(1, &self.vbo);
        c.glGenBuffers(1, &self.ibo);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.batch.deinit();
        self.windows.deinit(self.allocator);
        if (self.program.prog != 0)
            c.glDeleteProgram(self.program.prog);
        if (self.vbo != 0)
            c.glDeleteBuffers(1, &self.vbo);
        if (self.ibo != 0)
            c.glDeleteBuffers(1, &self.ibo);
    }

    pub fn beginFrame(self: *Self, display_w: f32, display_h: f32, input: Input) void {
        self.display_size = .{ .x = display_w, .y = display_h };
        self.input = input;
        self.batch.verts.clearRetainingCapacity();
        self.batch.indices.clearRetainingCapacity();
        self.windows.clearRetainingCapacity();
        self.current = null;
        if (!self.input.mouse_down and !self.input.mouse_released)
            self.active_id = 0;
    }

    pub fn endFrame(self: *Self) void {
        c.glUseProgram(self.program.prog);
        c.glUniform2f(self.program.u.screen, self.display_size.x, self.display_size.y);

        c.glDisable(c.GL_CULL_FACE);
        c.glDisable(c.GL_DEPTH_TEST);
        c.glEnable(c.GL_BLEND);
        c.glBlendFuncSeparate(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA, c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);

        c.glBindTexture(c.GL_TEXTURE_2D, 0);

        const vbsize = @as(c.GLsizeiptr, @intCast(self.batch.verts.items.len * @sizeOf(Vertex)));
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, vbsize, self.batch.verts.items.ptr, c.GL_DYNAMIC_DRAW);

        const ibsize = @as(c.GLsizeiptr, @intCast(self.batch.indices.items.len * @sizeOf(u16)));
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, ibsize, self.batch.indices.items.ptr, c.GL_DYNAMIC_DRAW);

        inline for (std.meta.fields(@TypeOf(self.program.a))) |f| {
            const T = @FieldType(Vertex, f.name);
            const size = componentCount(T);
            const gl_type = glutils.typeToGLenum(T);

            c.glEnableVertexAttribArray(@intCast(@field(self.program.a, f.name)));
            const offset = @offsetOf(Vertex, f.name);
            std.log.debug("test {} {} {} {} {s}", .{ @sizeOf(Vertex), @sizeOf(@FieldType(Vertex, f.name)), offset, size, f.name });
            c.glVertexAttribPointer(@intCast(@field(self.program.a, f.name)), size, gl_type, if (gl_type != c.GL_FLOAT) c.GL_TRUE else c.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(offset));
        }

        if (self.batch.indices.items.len > 0) {
            c.glDrawElements(c.GL_TRIANGLES, @intCast(self.batch.indices.items.len), c.GL_UNSIGNED_SHORT, @ptrFromInt(0));
        }

        inline for (std.meta.fields(@TypeOf(self.program.a))) |f| {
            c.glDisableVertexAttribArray(@intCast(@field(self.program.a, f.name)));
        }
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);
        c.glBindTexture(c.GL_TEXTURE_2D, 0);
        c.glUseProgram(0);
        c.glDisable(c.GL_SCISSOR_TEST);
    }

    pub fn beginWindow(self: *Self, id: u32, rect: Rect) bool {
        const w = Window{
            .id = id,
            .rect = rect,
            .cursor = .{ .x = rect.x + self.style.window_padding.x, .y = rect.y + self.style.window_padding.y },
            .content_max_x = rect.x + self.style.window_padding.x,
        };
        // bg
        _ = self.batch.addQuad(rect, self.style.window_bg) catch {
            return false;
        };
        self.windows.append(self.allocator, w) catch {
            return false;
        };
        self.current = &self.windows.items[self.windows.items.len - 1];

        // Clip to window
        c.glEnable(c.GL_SCISSOR_TEST);
        // Convert top-left origin to GL scissor (also top-left in ES? Spec uses lower-left; we convert)
        const y_flipped = self.display_size.y - rect.y - rect.h;
        c.glScissor(@intFromFloat(rect.x), @intFromFloat(y_flipped), @intFromFloat(rect.w), @intFromFloat(rect.h));
        return true;
    }

    pub fn endWindow(self: *Self) void {
        if (self.windows.items.len > 0) {
            _ = self.windows.pop();
            self.current = if (self.windows.items.len > 0) &self.windows.items[self.windows.items.len - 1] else null;
            if (self.current == null) {
                c.glDisable(c.GL_SCISSOR_TEST);
            } else {
                // Restore scissor for parent
                const r = self.current.?.rect;
                const y_flipped = self.display_size.y - r.y - r.h;
                c.glScissor(@intFromFloat(r.x), @intFromFloat(y_flipped), @intFromFloat(r.w), @intFromFloat(r.h));
            }
        }
    }

    pub fn sameLine(self: *Self, spacing: ?f32) void {
        const s = spacing orelse self.style.item_spacing.x;
        if (self.current) |w| {
            w.cursor.x = w.content_max_x + s;
            w.cursor.y -= self.last_height_size + self.style.item_spacing.y;
        }
    }

    fn advanceCursor(self: *Self, size: Vec2) void {
        if (self.current) |w| {
            w.cursor.x = w.rect.x + self.style.window_padding.x;
            w.cursor.y += size.y + self.style.item_spacing.y;
            self.last_height_size = size.y;
        }
    }

    pub fn separator(self: *Self) void {
        if (self.current) |w| {
            const x = w.rect.x + 3 * self.style.window_padding.x;
            const wpx = w.rect.w - 6 * self.style.window_padding.x;
            const y = w.cursor.y + self.style.frame_height * 0.5;
            _ = self.batch.addQuad(.{ .x = x, .y = y, .w = wpx, .h = 2.0 }, self.style.separator_color) catch {};
            self.advanceCursor(.{ .x = wpx, .y = 20.0 });
        }
    }

    pub fn button(self: *Self, id: u32, size: Vec2) bool {
        if (self.current == null)
            return false;
        var w = self.current.?;

        const r: Rect = .{
            .x = w.cursor.x,
            .y = w.cursor.y,
            .w = size.x,
            .h = if (size.y == 0) self.style.frame_height else size.y,
        };
        // Track max X for sameLine
        w.content_max_x = if (w.content_max_x > r.x + r.w) w.content_max_x else r.x + r.w;

        const mouse_over = pointInRect(self.input.mouse_pos, r);

        var col = self.style.button_color;
        if (id == self.active_id) {
            col = self.style.button_active;
        }
        _ = self.batch.addQuad(r, col) catch {};

        var clicked = false;
        if (mouse_over and self.input.mouse_down) {
            self.active_id = id;
        }
        if (self.input.mouse_released) {
            if (self.active_id == id and mouse_over)
                clicked = true;
        }

        self.advanceCursor(size);
        return clicked;
    }

    pub fn hashId(bytes: []const u8) u32 {
        // FNV-1a 32-bit
        var h: u32 = 0xdeadbeef;
        for (bytes) |b| {
            h ^= @as(u32, b);
            h *%= 0xbaadcafe;
        }
        return h;
    }

    fn pointInRect(p: Vec2, r: Rect) bool {
        return p.x >= r.x and p.x <= r.x + r.w and p.y >= r.y and p.y <= r.y + r.h;
    }
};
