const std = @import("std");
const pf = @import("core.zig");
const Vec3 = @import("vec3.zig").Vec3;

pub const Ray = struct {
    origin: Vec3,
    dir: Vec3,
};

pub const Hit = struct {
    dist: pf.Field,
    hit: pf.Mask,
    normal: Vec3,
    material_id: pf.Field, // Simple ID for now
};

pub const Sphere = struct {
    center: Vec3,
    radius: pf.Field,

    pub fn intersect(self: Sphere, ray: Ray) Hit {
        // Geometric solution
        // L = C - O
        const L = self.center.sub(ray.origin);
        // tca = dot(L, D)
        const tca = L.dot(ray.dir);
        // d2 = dot(L, L) - tca * tca
        const d2 = L.dot(L) - tca * tca;
        const radius2 = self.radius * self.radius;
        
        // if d2 > radius2, no intersection
        const miss_mask = d2 > radius2;
        
        // thc = sqrt(radius2 - d2)
        const thc = pf.Core.sqrt(radius2 - d2);
        
        // t0 = tca - thc
        // t1 = tca + thc
        const t0 = tca - thc;
        const t1 = tca + thc;
        
        // Check if t0 or t1 are positive
        const t0_valid = t0 > pf.Core.constant(0.001);
        const t1_valid = t1 > pf.Core.constant(0.001);
        
        // Select nearest valid t
        var dist = t0;
        var hit_mask = t0_valid;
        
        // If t0 < 0 but t1 > 0, we are inside
        dist = pf.Core.select(hit_mask, dist, t1);
        hit_mask = hit_mask | t1_valid;
        
        // Final miss check from d2
        hit_mask = hit_mask & !miss_mask;
        
        // Calculate normal at hit point: N = normalize(P - C)
        const P = ray.origin.add(ray.dir.mul(dist));
        const normal = P.sub(self.center).normalize();
        
        return Hit{
            .dist = dist,
            .hit = hit_mask,
            .normal = normal,
            .material_id = pf.Core.constant(1.0), // Sphere ID
        };
    }
};

pub const Plane = struct {
    height: pf.Field, // Y coordinate of plane
    
    pub fn intersect(self: Plane, ray: Ray) Hit {
        // Plane Y = h
        // O.y + t * D.y = h
        // t = (h - O.y) / D.y
        
        const num = self.height - ray.origin.y;
        const denom = ray.dir.y;
        
        // Avoid division by zero
        const safe_denom = pf.Core.select(@abs(denom) > pf.Core.constant(0.0001), denom, pf.Core.constant(0.0001));
        
        const t = num / safe_denom;
        
        // Check if hit is forward (t > 0)
        const hit_mask = t > pf.Core.constant(0.001);
        
        // Normal is always (0, 1, 0) for floor, or (0, -1, 0) if looking from below?
        // Assume floor is Y = -1, looking down
        
        return Hit{
            .dist = t,
            .hit = hit_mask,
            .normal = Vec3.init(pf.Core.constant(0.0), pf.Core.constant(1.0), pf.Core.constant(0.0)),
            .material_id = pf.Core.constant(2.0), // Floor ID
        };
    }
};

pub fn render_scene(ray: Ray, sphere: Sphere, plane: Plane) struct { r: pf.Field, g: pf.Field, b: pf.Field } {
    _ = sphere;
    _ = plane;
    
    // Default Sky (if no hit)
    // Gradient based on Ray.y
    const ray_sky_t = ray.dir.y * pf.Core.constant(0.5) + pf.Core.constant(0.5);
    const bg_r = pf.Core.mix(pf.Core.constant(0.1), pf.Core.constant(0.4), ray_sky_t);
    const bg_g = pf.Core.mix(pf.Core.constant(0.1), pf.Core.constant(0.6), ray_sky_t);
    const bg_b = pf.Core.mix(pf.Core.constant(0.4), pf.Core.constant(0.9), ray_sky_t);
    
    return .{ .r = bg_r, .g = bg_g, .b = bg_b };
}
