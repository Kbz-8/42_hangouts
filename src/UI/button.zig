const std = @import("std");
const Vec2 = @import("Vec2.zig").Vec2;

const c = @cImport({
    @cInclude("GLES2/gl2.h");
    @cInclude("GLES2/gl2ext.h");
});

pub fn button(_: []const u8, size: Vec2) bool {
    
}
