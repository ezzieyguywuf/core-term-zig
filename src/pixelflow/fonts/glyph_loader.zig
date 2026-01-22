const std = @import("std");
const ttf = @import("ttf_parser.zig");
const curves = @import("curves.zig");
const AnalyticalLine = curves.AnalyticalLine;
const AnalyticalQuad = curves.AnalyticalQuad;

pub const GlyphGeometry = struct {
    lines: std.ArrayList(AnalyticalLine),
    quads: std.ArrayList(AnalyticalQuad),
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,

    pub fn deinit(self: *GlyphGeometry, allocator: std.mem.Allocator) void {
        self.lines.deinit(allocator);
        self.quads.deinit(allocator);
    }
};

const Point = struct {
    x: i16,
    y: i16,
    on_curve: bool,
};

pub const GlyphLoader = struct {
    font: ttf.Font,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, font: ttf.Font) GlyphLoader {
        return .{ .allocator = allocator, .font = font };
    }

    pub fn load(self: *GlyphLoader, glyph_index: u16) !GlyphGeometry {
        const offset = try self.font.getGlyphOffset(glyph_index);
        const len = try self.font.getGlyphLen(glyph_index);
        
        const LineList = std.ArrayList(AnalyticalLine);
        const QuadList = std.ArrayList(AnalyticalQuad);

        if (len == 0) {
            return GlyphGeometry{
                .lines = try LineList.initCapacity(self.allocator, 0),
                .quads = try QuadList.initCapacity(self.allocator, 0),
                .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0,
            };
        }

        var r = ttf.Reader.init(self.font.data);
        r.seek(self.font.glyf_offset + offset);

        const num_contours = try r.readI16();
        const x_min = try r.readI16();
        const y_min = try r.readI16();
        const x_max = try r.readI16();
        const y_max = try r.readI16();

        var geom = GlyphGeometry{
            .lines = try LineList.initCapacity(self.allocator, 0),
            .quads = try QuadList.initCapacity(self.allocator, 0),
            .x_min = x_min, .y_min = y_min, .x_max = x_max, .y_max = y_max,
        };

        if (num_contours >= 0) {
            try self.loadSimpleGlyph(&r, num_contours, &geom);
        } else {
            // TODO: Compound glyphs
        }

        return geom;
    }

    fn loadSimpleGlyph(self: *GlyphLoader, r: *ttf.Reader, num_contours: i16, geom: *GlyphGeometry) !void {
        var end_pts = try self.allocator.alloc(u16, @intCast(num_contours));
        defer self.allocator.free(end_pts);

        for (0..@intCast(num_contours)) |i| {
            end_pts[i] = try r.readU16();
        }

        const num_points = end_pts[end_pts.len - 1] + 1;
        const instruction_len = try r.readU16();
        try r.skip(instruction_len);

        var flags = try self.allocator.alloc(u8, num_points);
        defer self.allocator.free(flags);

        var i: usize = 0;
        while (i < num_points) {
            const flag = try r.readU8();
            flags[i] = flag;
            i += 1;

            if ((flag & 8) != 0) {
                const repeat_count = try r.readU8();
                for (0..repeat_count) |_| {
                    flags[i] = flag;
                    i += 1;
                }
            }
        }

        var x_coords = try self.allocator.alloc(i16, num_points);
        defer self.allocator.free(x_coords);
        var y_coords = try self.allocator.alloc(i16, num_points);
        defer self.allocator.free(y_coords);

        // Read X
        var current_x: i16 = 0;
        for (0..num_points) |j| {
            const flag = flags[j];
            if ((flag & 2) != 0) {
                const dx = try r.readU8();
                if ((flag & 16) != 0) {
                    current_x += @as(i16, dx);
                } else {
                    current_x -= @as(i16, dx);
                }
            } else if ((flag & 16) == 0) {
                const dx = try r.readI16();
                current_x += dx;
            }
            x_coords[j] = current_x;
        }

        // Read Y
        var current_y: i16 = 0;
        for (0..num_points) |j| {
            const flag = flags[j];
            if ((flag & 4) != 0) {
                const dy = try r.readU8();
                if ((flag & 32) != 0) {
                    current_y += @as(i16, dy);
                } else {
                    current_y -= @as(i16, dy);
                }
            } else if ((flag & 32) == 0) {
                const dy = try r.readI16();
                current_y += dy;
            }
            y_coords[j] = current_y;
        }

        // Process contours
        var start_idx: usize = 0;
        for (0..@intCast(num_contours)) |k| {
            const end_idx = end_pts[k];
            const contour_len = end_idx - start_idx + 1;
            
            // Build points list for this contour
            var points = try self.allocator.alloc(Point, contour_len);
            defer self.allocator.free(points);

            for (0..contour_len) |j| {
                const idx = start_idx + j;
                points[j] = Point{
                    .x = x_coords[idx],
                    .y = y_coords[idx],
                    .on_curve = (flags[idx] & 1) != 0,
                };
            }

            try self.processContour(points, geom, self.allocator);
            start_idx = end_idx + 1;
        }
    }

    fn processContour(self: *GlyphLoader, points: []Point, geom: *GlyphGeometry, allocator: std.mem.Allocator) !void {
        _ = self;
        if (points.len == 0) return;

        var temp_points = try std.ArrayList(Point).initCapacity(allocator, points.len);
        defer temp_points.deinit(allocator);

        // Find index of first on-curve point
        var start_idx: usize = 0;
        var has_on_curve = false;
        for (points, 0..) |p, i| {
            if (p.on_curve) {
                start_idx = i;
                has_on_curve = true;
                break;
            }
        }

        if (!has_on_curve) return; // TODO: Handle all off-curve case

        // Reorder points to start with on-curve
        for (0..points.len) |i| {
            const idx = (start_idx + i) % points.len;
            const curr = points[idx];
            const next = points[(idx + 1) % points.len];

            try temp_points.append(allocator, curr);

            // If both this and next are off-curve, add implicit on-curve point at midpoint
            if (!curr.on_curve and !next.on_curve) {
                const mid_x = (curr.x + next.x) >> 1;
                const mid_y = (curr.y + next.y) >> 1;
                try temp_points.append(allocator, Point{ .x = mid_x, .y = mid_y, .on_curve = true });
            }
        }
        
        // Append the start point at the end to close the loop
        try temp_points.append(allocator, temp_points.items[0]);

        // Generate geometry
        var i: usize = 0;
        while (i < temp_points.items.len - 1) {
            const p0 = temp_points.items[i];
            const p1 = temp_points.items[i+1];

            if (p1.on_curve) {
                // Line: On -> On
                if (AnalyticalLine.new(
                    .{ @floatFromInt(p0.x), @floatFromInt(p0.y) }, 
                    .{ @floatFromInt(p1.x), @floatFromInt(p1.y) }
                )) |line| {
                    try geom.lines.append(allocator, line);
                }
                i += 1;
            } else {
                // Quad: On -> Off -> On
                // We know p1 is off-curve. Because we inserted implicit points, p2 MUST be on-curve.
                if (i + 2 >= temp_points.items.len) break; // Should not happen with closed loop
                const p2 = temp_points.items[i+2];
                
                const quad = AnalyticalQuad.new(
                    .{ @floatFromInt(p0.x), @floatFromInt(p0.y) },
                    .{ @floatFromInt(p1.x), @floatFromInt(p1.y) },
                    .{ @floatFromInt(p2.x), @floatFromInt(p2.y) }
                );
                try geom.quads.append(allocator, quad);
                i += 2;
            }
        }
    }
};
