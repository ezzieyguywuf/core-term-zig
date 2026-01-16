const std = @import("std");
const pf = @import("core.zig");

/// A Rectangle SDF (Signed Distance Field)
/// d = max(|x| - w, |y| - h)
/// Negative inside, positive outside.
pub const Rectangle = struct {
    width: f32,
    height: f32,
    center_x: f32,
    center_y: f32,

    pub fn eval(self: Rectangle, x: pf.Field, y: pf.Field) pf.Field {
        // Translate coordinates to local space
        const lx = x - pf.Core.constant(self.center_x);
        const ly = y - pf.Core.constant(self.center_y);
        
        // abs(p) - b
        const dx = @abs(lx) - pf.Core.constant(self.width / 2.0);
        const dy = @abs(ly) - pf.Core.constant(self.height / 2.0);
        
        // length(max(d, 0.0)) + min(max(d.x, d.y), 0.0)
        const zero: pf.Field = @splat(0.0);
        const max_d_x = @max(dx, zero);
        const max_d_y = @max(dy, zero);
        
        // Approximate length for outside
        // d = sqrt(max_d_x^2 + max_d_y^2)
        const len = pf.Core.sqrt(max_d_x * max_d_x + max_d_y * max_d_y);
        
        // Inside distance (negative)
        const inside = @min(@max(dx, dy), zero);
        
        return len + inside;
    }
    
    /// Stencil: 1.0 inside/border, 0.0 outside
    pub fn stencil(self: Rectangle, x: pf.Field, y: pf.Field) pf.Field {
        const d = self.eval(x, y);
        // Antialiasing: smoothstep around 0
        // We want 1.0 when d <= 0, 0.0 when d > 1 (pixel width)
        // For simple binary: d <= 0
        const mask = d <= @as(pf.Field, @splat(0.0));
        return pf.Core.select(mask, @splat(1.0), @splat(0.0));
    }
};

/// Circle SDF
pub const Circle = struct {
    radius: f32,
    center_x: f32,
    center_y: f32,
    
    pub fn eval(self: Circle, x: pf.Field, y: pf.Field) pf.Field {
        const lx = x - pf.Core.constant(self.center_x);
        const ly = y - pf.Core.constant(self.center_y);
        
        const len = pf.Core.sqrt(lx * lx + ly * ly);
        return len - pf.Core.constant(self.radius);
    }
};
