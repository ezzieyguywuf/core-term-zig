const std = @import("std");
const pf = @import("../core.zig");
const ttf = @import("ttf_parser.zig");
const curves = @import("curves.zig");
const loader = @import("glyph_loader.zig");

pub const GlyphKey = struct {
    codepoint: u32,
    size: u32, // Font size in pixels
};

pub const CachedGlyph = struct {
    bitmap: []u8,
    width: usize,
    height: usize,
    bearing_x: i32,
    bearing_y: i32,
    advance: f32,
};

pub const Atlas = struct {
    allocator: std.mem.Allocator,
    font: ttf.Font,
    loader: loader.GlyphLoader,
    cache: std.AutoHashMap(GlyphKey, CachedGlyph),

    pub fn init(allocator: std.mem.Allocator, font_data: []const u8) !Atlas {
        const f = try ttf.Font.parse(allocator, font_data);
        const l = loader.GlyphLoader.init(allocator, f);
        return .{
            .allocator = allocator,
            .font = f,
            .loader = l,
            .cache = std.AutoHashMap(GlyphKey, CachedGlyph).init(allocator),
        };
    }

    pub fn deinit(self: *Atlas) void {
        var it = self.cache.valueIterator();
        while (it.next()) |g| {
            self.allocator.free(g.bitmap);
        }
        self.cache.deinit();
    }

    pub fn get(self: *Atlas, codepoint: u32, size: u32) !*CachedGlyph {
        const key = GlyphKey{ .codepoint = codepoint, .size = size };
        if (self.cache.getPtr(key)) |g| {
            return g;
        }

        const g = try self.rasterize(codepoint, size);
        try self.cache.put(key, g);
        return self.cache.getPtr(key).?;
    }

    fn rasterize(self: *Atlas, codepoint: u32, size: u32) !CachedGlyph {
        const glyph_index = try self.font.getCmap(codepoint);
        if (glyph_index == 0) return self.makeEmpty();

        var geom = try self.loader.load(glyph_index);
        defer geom.deinit(self.allocator);

        // Calculate scale
        // units_per_em -> size pixels
        const scale = @as(f32, @floatFromInt(size)) / @as(f32, @floatFromInt(self.font.units_per_em));

        const x_min = @as(f32, @floatFromInt(geom.x_min)) * scale;
        const x_max = @as(f32, @floatFromInt(geom.x_max)) * scale;
        const y_min = @as(f32, @floatFromInt(geom.y_min)) * scale;
        const y_max = @as(f32, @floatFromInt(geom.y_max)) * scale;

        const width = @as(usize, @intFromFloat(@ceil(x_max - x_min))) + 2; // Padding
        const height = @as(usize, @intFromFloat(@ceil(y_max - y_min))) + 2;

        var bitmap = try self.allocator.alloc(u8, width * height);
        @memset(bitmap, 0);

        // Rasterizer Loop
        for (0..height) |iy| {
            for (0..width) |ix| {
                // Pixel center in bitmap coords
                const px = @as(f32, @floatFromInt(ix)) + 0.5;
                const py = @as(f32, @floatFromInt(iy)) + 0.5;

                // Map to Font Space
                // x_world = (px + offset_x) / scale
                // y_world = (py + offset_y) / scale
                
                const font_x = @as(f32, @floatFromInt(geom.x_min)) + px / scale;
                const font_y = @as(f32, @floatFromInt(geom.y_max)) - py / scale;
                
                // Broadcast to SIMD
                const vx = pf.Core.constant(font_x);
                const vy = pf.Core.constant(font_y);
                
                var total: pf.Field = @splat(0.0);
                
                for (geom.lines.items) |l| {
                    total += l.eval(vx, vy);
                }
                for (geom.quads.items) |q| {
                    total += q.eval(vx, vy);
                }
                
                // Extract scalar (lane 0)
                const val = total[0];
                const coverage = @min(1.0, @abs(val));
                const alpha = @as(u8, @intFromFloat(coverage * 255.0));
                
                bitmap[iy * width + ix] = alpha;
            }
        }

        // Debug: ASCII Dump for 'e'
        if (codepoint == 101) {
            std.debug.print("Rasterized 'e': width={d} height={d} x_min={d} y_max={d}\n", .{width, height, x_min, y_max});
            for (0..height) |iy| {
                for (0..width) |ix| {
                    const val = bitmap[iy * width + ix];
                    const char: u8 = if (val > 128) '#' else if (val > 0) ':' else '.';
                    std.debug.print("{c}", .{char});
                }
                std.debug.print("\n", .{});
            }
        }

        return CachedGlyph{
            .bitmap = bitmap,
            .width = width,
            .height = height,
            .bearing_x = @intFromFloat(x_min),
            .bearing_y = @intFromFloat(y_max), // Top bearing
            .advance = 0, // TODO: Read HMTX
        };
    }

    pub fn ensureCached(self: *Atlas, codepoint: u32, size: u32) !void {
        const key = GlyphKey{ .codepoint = codepoint, .size = size };
        if (!self.cache.contains(key)) {
            const g = try self.rasterize(codepoint, size);
            try self.cache.put(key, g);
        }
    }

    fn makeEmpty(self: *Atlas) !CachedGlyph {
        const bitmap = try self.allocator.alloc(u8, 1);
        bitmap[0] = 0;
        return CachedGlyph{
            .bitmap = bitmap,
            .width = 1,
            .height = 1,
            .bearing_x = 0,
            .bearing_y = 0,
            .advance = 0,
        };
    }
};
