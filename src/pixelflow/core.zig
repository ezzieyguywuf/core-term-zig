const std = @import("std");
const math = std.math;

/// The width of our SIMD vectors.
/// Zig's @Vector handles the mapping to AVX/NEON/SSE automatically.
pub const LANES: usize = 8; // 8x f32 = 256 bits (AVX2-friendly)

pub const Field = @Vector(LANES, f32);
pub const Mask = @Vector(LANES, bool);
pub const Discrete = @Vector(LANES, u32);

pub const X = Axis.X;
pub const Y = Axis.Y;
pub const Z = Axis.Z;
pub const W = Axis.W;

pub const Axis = enum { X, Y, Z, W };

/// Core functionality for creating and manipulating Fields
pub const Core = struct {
    /// Create a sequential vector [start, start+1, ...]
    pub fn sequential(start: f32) Field {
        var buf: [LANES]f32 = undefined;
        for (0..LANES) |i| {
            buf[i] = start + @as(f32, @floatFromInt(i));
        }
        return buf;
    }

    /// Constant value across all lanes
    pub fn constant(val: f32) Field {
        return @splat(val);
    }

    /// Square root
    pub fn sqrt(f: Field) Field {
        return @sqrt(f);
    }

    /// Select based on mask: mask ? if_true : if_false
    pub fn select(mask: Mask, if_true: Field, if_false: Field) Field {
        return @select(f32, mask, if_true, if_false);
    }

    /// Linear interpolation: x * (1-a) + y * a
    /// a is 0.0-1.0
    pub fn mix(x: Field, y: Field, a: Field) Field {
        // x + (y - x) * a
        return x + (y - x) * a;
    }

    /// Less than
    pub fn lt(a: Field, b: Field) Mask {
        return a < b;
    }

    /// Greater than
    pub fn gt(a: Field, b: Field) Mask {
        return a > b;
    }

        /// Pack 4 float channels (0.0-1.0) into RGBA u32 (actually BGRA for xrgb8888)
        pub fn pack_rgba(r: Field, g: Field, b: Field, a: Field) Discrete {
            // Clamp to 0-1
            const zero: Field = @splat(0.0);
            const one: Field = @splat(1.0);
            
            const r_c = @max(zero, @min(one, r));
            const g_c = @max(zero, @min(one, g));
            const b_c = @max(zero, @min(one, b));
            const a_c = @max(zero, @min(one, a));
    
            // Scale to 0-255 and cast to u32
            const scale: Field = @splat(255.0);
            const r_i: Discrete = @intFromFloat(r_c * scale);
            const g_i: Discrete = @intFromFloat(g_c * scale);
            const b_i: Discrete = @intFromFloat(b_c * scale);
            const a_i: Discrete = @intFromFloat(a_c * scale);
    
            // Pack: B | G<<8 | R<<16 | A<<24 (Little Endian for BGRA/xrgb8888)
            return b_i | (g_i << @splat(8)) | (r_i << @splat(16)) | (a_i << @splat(24));
        }};

/// Manifold Interface equivalent
/// In Zig, we can use comptime generics instead of Traits
pub fn evaluate(comptime func: anytype, ctx: anytype, x: f32, y: f32, out: []u32) void {
    var x_start = x;

    // Process output in chunks of LANES
    var i: usize = 0;
    while (i < out.len) {
        // Prepare X and Y coordinates
        // xs = [x, x+1, x+2, ...]
        const xs = Core.sequential(x_start + @as(f32, @floatFromInt(i)));
        const ys = @as(Field, @splat(y_start));

        const rgba = func(ctx, xs, ys);
        const packed_pixels = Core.pack_rgba(rgba.r, rgba.g, rgba.b, rgba.a);
        
        if (i + LANES <= out.len) {
            // Full vector store
            const slice: *[LANES]u32 = @ptrCast(out[i..i+LANES]);
            slice.* = packed_pixels;
            i += LANES;
        } else {
            // Tail handling
            const remaining = out.len - i;
            var temp_buf: [LANES]u32 = packed_pixels;
            // Copy remaining
            for (0..remaining) |j| {
                out[i + j] = temp_buf[j];
            }
            break;
        }
    }
}
