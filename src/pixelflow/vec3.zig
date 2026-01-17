const std = @import("std");
const core = @import("core.zig");
const Field = core.Field;
const Core = core.Core;

pub const Vec3 = struct {
    x: Field,
    y: Field,
    z: Field,

    pub fn init(x: Field, y: Field, z: Field) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn splat(val: f32) Vec3 {
        return .{
            .x = Core.constant(val),
            .y = Core.constant(val),
            .z = Core.constant(val),
        };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn mul(self: Vec3, scalar: Field) Vec3 {
        return .{
            .x = self.x * scalar,
            .y = self.y * scalar,
            .z = self.z * scalar,
        };
    }

    pub fn dot(self: Vec3, other: Vec3) Field {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn length_sq(self: Vec3) Field {
        return self.dot(self);
    }

    pub fn length(self: Vec3) Field {
        return Core.sqrt(self.length_sq());
    }

    pub fn normalize(self: Vec3) Vec3 {
        const len = self.length();
        // Avoid division by zero
        const safe_len = Core.select(len > Core.constant(0.0001), len, Core.constant(1.0));
        return self.mul(Core.constant(1.0) / safe_len);
    }
    
    pub fn reflect(self: Vec3, normal: Vec3) Vec3 {
        // r = v - 2 * dot(v, n) * n
        const d = self.dot(normal);
        return self.sub(normal.mul(d * Core.constant(2.0)));
    }
};
