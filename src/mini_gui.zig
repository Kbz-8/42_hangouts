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
};

pub const Gui = struct {
    allocator: std.mem.Allocator,
    batch: Batch,

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
        return .{
            .allocator = allocator,
            .batch = try Batch.init(allocator),
            .windows = try std.ArrayList(Window).initCapacity(allocator, 8),
        };
    }

    pub fn deinit(self: *Gui) void {
        self.batch.deinit();
        self.windows.deinit(self.allocator);
    }
};
