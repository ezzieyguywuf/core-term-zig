const std = @import("std");
const pf = @import("../core.zig");
const Field = pf.Field;
const Core = pf.Core;

pub const AnalyticalLine = struct {
    a: f32,
    b: f32,
    c: f32,
    dir: f32,
    y_min: f32,
    y_max: f32,

    pub fn new(p0: [2]f32, p1: [2]f32) ?AnalyticalLine {
        const dx = p1[0] - p0[0];
        const dy = p1[1] - p0[1];
        const len = @sqrt(dx * dx + dy * dy);

        if (len < 1e-6) return null;

        var a = dy / len;
        var b = -dx / len;
        var c = -(a * p0[0] + b * p0[1]);
        
        // Normalize so 'a' is positive (Right side covered logic)
        // If a < 0, f decreases with x. f > 0 for small x. Cov = 0.5 - f < 0. Left Covered.
        // We want Right Covered (x < x_line -> Cov=1).
        // So we need f < 0 for small x.
        // So a must be positive.
        if (a < 0) {
            a = -a;
            b = -b;
            c = -c;
        }

        // Winding direction: Up=+1, Down=-1. Horizontal=0.
        // Note: Ray marching winding usually sums intersections to the right.
        // Up line (dy>0) crossing: +1.
        // Down line (dy<0) crossing: -1.
        const dir: f32 = if (dy > 1e-6) 1.0 else if (dy < -1e-6) -1.0 else 0.0;

        return AnalyticalLine{
            .a = a,
            .b = b,
            .c = c,
            .dir = dir,
            .y_min = @min(p0[1], p1[1]),
            .y_max = @max(p0[1], p1[1]),
        };
    }

    pub fn eval(self: AnalyticalLine, x: Field, y: Field) Field {
        // Early rejection
        const y_min = Core.constant(self.y_min);
        const y_max = Core.constant(self.y_max);
        
        // mask = (y >= y_min) & (y < y_max)
        const mask = (y >= y_min) & (y < y_max);
        
        // f = a*x + b*y + c
        const a = Core.constant(self.a);
        const b = Core.constant(self.b);
        const c = Core.constant(self.c);
        
        const f = x * a + y * b + c;
        
        // coverage = clamp(0.5 - f, 0, 1)
        const zero = Core.constant(0.0);
        const one = Core.constant(1.0);
        const half = Core.constant(0.5);
        const coverage = @min(one, @max(zero, half - f));
        
        const dir = Core.constant(self.dir);
        const winding = dir * coverage;
        
        return Core.select(mask, winding, zero);
    }
};

pub const AnalyticalQuad = struct {
    u_x: f32, u_y: f32, u_c: f32,
    v_x: f32, v_y: f32, v_c: f32,
    w_x: f32, w_y: f32, w_c: f32,
    is_linear: bool,
    orientation: f32,

    pub fn new(p0: [2]f32, p1: [2]f32, p2: [2]f32) AnalyticalQuad {
        const dx01 = p1[0] - p0[0];
        const dy01 = p1[1] - p0[1];
        const dx12 = p2[0] - p1[0];
        const dy12 = p2[1] - p1[1];
        const cross = dx01 * dy12 - dy01 * dx12;

        if (@abs(cross) < 1e-6) {
            // Degenerate (linear)
            return AnalyticalQuad{
                .u_x = 0, .u_y = 0, .u_c = 0,
                .v_x = 0, .v_y = 0, .v_c = 0,
                .w_x = 0, .w_y = 0, .w_c = 0,
                .is_linear = true,
                .orientation = 0,
            };
        }

        const x0 = p0[0]; const y0 = p0[1];
        const x1 = p1[0]; const y1 = p1[1];
        const x2 = p2[0]; const y2 = p2[1];

        const det = x0 * (y1 - y2) - y0 * (x1 - x2) + (x1 * y2 - x2 * y1);
        const inv_det = 1.0 / det;

        const u_x = inv_det * ((0.5 - 0.0) * (y2 - y0) + (1.0 - 0.5) * (y0 - y1));
        const u_y = inv_det * ((0.0 - 0.5) * (x2 - x0) + (0.5 - 1.0) * (x0 - x1));
        const u_c = 0.0 - u_x * x0 - u_y * y0;

        const v_x = inv_det * ((0.0 - 1.0) * (y2 - y0));
        const v_y = inv_det * ((1.0 - 0.0) * (x2 - x0));
        const v_c = 1.0 - v_x * x0 - v_y * y0;

        const w_x = inv_det * ((0.0 - 0.0) * (y2 - y0) + (1.0 - 0.0) * (y0 - y1));
        const w_y = inv_det * ((0.0 - 0.0) * (x2 - x0) + (0.0 - 1.0) * (x0 - x1));
        const w_c = 0.0 - w_x * x0 - w_y * y0;

        const orientation: f32 = if (cross > 0.0) -1.0 else 1.0;

        return AnalyticalQuad{
            .u_x = u_x, .u_y = u_y, .u_c = u_c,
            .v_x = v_x, .v_y = v_y, .v_c = v_c,
            .w_x = w_x, .w_y = w_y, .w_c = w_c,
            .is_linear = false,
            .orientation = orientation,
        };
    }

    pub fn eval(self: AnalyticalQuad, x: Field, y: Field) Field {
        _ = self; _ = x; _ = y;
        return Core.constant(0.0);
        /*
        if (self.is_linear) return Core.constant(0.0);
        ...
        */
    }
};
