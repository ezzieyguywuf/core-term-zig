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
        
        const t = num / denom;
        
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
    // Intersect both
    const hit_sphere = sphere.intersect(ray);
    const hit_plane = plane.intersect(ray);
    
    // Determine closest hit
    // If both hit, check dists
    const sphere_closer = hit_sphere.dist < hit_plane.dist;
    // But check validity (hit mask)
    // If only sphere hit: sphere
    // If only plane hit: plane
    // If both: closer
    // If neither: sky
    
    const use_sphere = hit_sphere.hit & (!hit_plane.hit | sphere_closer);
    const use_plane = hit_plane.hit & (!hit_sphere.hit | !sphere_closer);
    
    // --- Lighting ---
    const light_dir = Vec3.init(pf.Core.constant(0.577), pf.Core.constant(0.577), pf.Core.constant(0.577)); // Normalized (1,1,1)
    
    // Normal selection
    const normal_x = pf.Core.select(use_sphere, hit_sphere.normal.x, hit_plane.normal.x);
    const normal_y = pf.Core.select(use_sphere, hit_sphere.normal.y, hit_plane.normal.y);
    const normal_z = pf.Core.select(use_sphere, hit_sphere.normal.z, hit_plane.normal.z);
    const normal = Vec3.init(normal_x, normal_y, normal_z);
    
    // Diffuse
    const diff = @max(pf.Core.constant(0.0), normal.dot(light_dir));
    
    // --- Materials ---
    
    // Sphere Material: Chrome/Reflective
    // R = reflect(D, N)
    // Sky color based on R.y
    const view_dir = ray.dir;
    const reflect_dir = view_dir.reflect(normal);
    
    // Sky gradient (simple)
    // mix(blue, white, reflect_dir.y)
    const sky_t = reflect_dir.y * pf.Core.constant(0.5) + pf.Core.constant(0.5);
    const chrome_r = pf.Core.mix(pf.Core.constant(0.3), pf.Core.constant(0.8), sky_t);
    const chrome_g = pf.Core.mix(pf.Core.constant(0.3), pf.Core.constant(0.8), sky_t);
    const chrome_b = pf.Core.mix(pf.Core.constant(0.8), pf.Core.constant(1.0), sky_t);
    
    // Floor Material: Checkerboard
    const hit_pos_plane = ray.origin.add(ray.dir.mul(hit_plane.dist));
    // Checker: (floor(x) + floor(z)) % 2
    const check_x = @floor(hit_pos_plane.x);
    const check_z = @floor(hit_pos_plane.z);
    // xor parity
    // Simulate xor/mod with floats
    // (a + b) % 2.0
    // Actually simpler: sin(x)*sin(z) > 0
    const check_val = @sin(hit_pos_plane.x * pf.Core.constant(3.0)) * @sin(hit_pos_plane.z * pf.Core.constant(3.0));
    const is_white = check_val > pf.Core.constant(0.0);
    
    const floor_r = pf.Core.select(is_white, pf.Core.constant(0.6), pf.Core.constant(0.3)) * diff;
    const floor_g = pf.Core.select(is_white, pf.Core.constant(0.6), pf.Core.constant(0.3)) * diff;
    const floor_b = pf.Core.select(is_white, pf.Core.constant(0.6), pf.Core.constant(0.3)) * diff;
    
    // --- Final Composition ---
    
    // Default Sky (if no hit)
    // Gradient based on Ray.y
    const ray_sky_t = ray.dir.y * pf.Core.constant(0.5) + pf.Core.constant(0.5);
    const bg_r = pf.Core.mix(pf.Core.constant(0.1), pf.Core.constant(0.4), ray_sky_t);
    const bg_g = pf.Core.mix(pf.Core.constant(0.1), pf.Core.constant(0.6), ray_sky_t);
    const bg_b = pf.Core.mix(pf.Core.constant(0.4), pf.Core.constant(0.9), ray_sky_t);
    
    var final_r = bg_r;
    var final_g = bg_g;
    var final_b = bg_b;
    
    // Apply Sphere
    final_r = pf.Core.select(use_sphere, chrome_r, final_r);
    final_g = pf.Core.select(use_sphere, chrome_g, final_g);
    final_b = pf.Core.select(use_sphere, chrome_b, final_b);
    
    // Apply Plane
    final_r = pf.Core.select(use_plane, floor_r, final_r);
    final_g = pf.Core.select(use_plane, floor_g, final_g);
    final_b = pf.Core.select(use_plane, floor_b, final_b);
    
    return .{ .r = final_r, .g = final_g, .b = final_b };
}
