const std = @import("std");
const pf = @import("pixelflow/core.zig");
const shapes = @import("pixelflow/shapes.zig");
const grid = @import("terminal/grid.zig");
const font = @import("font.zig");
const vec3 = @import("pixelflow/vec3.zig");
const scene3d = @import("pixelflow/scene3d.zig");
const atlas_mod = @import("pixelflow/fonts/atlas.zig");

pub const SCALE: f32 = 2.0;
// We target roughly 16x32 pixels
pub const FONT_SIZE: u32 = 32;
pub const CHAR_WIDTH: f32 = 20.0;
pub const CHAR_HEIGHT: f32 = 32.0;

pub const TITLE_BAR_HEIGHT: usize = 30;
pub const CLOSE_BUTTON_SIZE: usize = 30;

const TerminalContext = struct {
    width_px: i32,
    height_px: i32,
    terminal_grid: *grid.Grid,
    cursor_x: usize,
    cursor_y: usize,
    atlas: *atlas_mod.Atlas,
    
    // Background info
    overall_bg_ctx: struct {
        r: pf.Field,
        g: pf.Field,
        b: pf.Field,
    },
};

const TerminalEvaluator = struct {
    pub fn fill_eval(c: TerminalContext, x_field: pf.Field, y_field: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
        _ = x_field;
        _ = y_field;
        return .{ .r = c.overall_bg_ctx.r, .g = c.overall_bg_ctx.g, .b = c.overall_bg_ctx.b, .a = @splat(1.0) };
    }
};

const CellRenderContext = struct {
    fg_r: f32,
    fg_g: f32,
    fg_b: f32,
    bg_r: f32,
    bg_g: f32,
    bg_b: f32,
    is_bold: bool,
    is_inverse: bool,
    glyph_bitmap: []const u8,
    glyph_width: usize,
    glyph_height: usize,
    scaled_x_min: f32,
    scaled_y_max: f32,
    scaled_ascent: f32,
    scaled_descent: f32,
    draw_x_start: f32,
    draw_y_start: f32,
};

const CellEvaluator = struct {
    pub fn eval(c: CellRenderContext, x_p: pf.Field, y_p: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
        const bg_r_field = pf.Core.constant(c.bg_r);
        const bg_g_field = pf.Core.constant(c.bg_g);
        const bg_b_field = pf.Core.constant(c.bg_b);

        const bg_r_arr: [pf.LANES]f32 = @as([pf.LANES]f32, bg_r_field);
        const bg_g_arr: [pf.LANES]f32 = @as([pf.LANES]f32, bg_g_field);
        const bg_b_arr: [pf.LANES]f32 = @as([pf.LANES]f32, bg_b_field);

        const fg_r_field = pf.Core.constant(c.fg_r);
        const fg_g_field = pf.Core.constant(c.fg_g);
        const fg_b_field = pf.Core.constant(c.fg_b);

        const fg_r_arr: [pf.LANES]f32 = @as([pf.LANES]f32, fg_r_field);
        const fg_g_arr: [pf.LANES]f32 = @as([pf.LANES]f32, fg_g_field);
        const fg_b_arr: [pf.LANES]f32 = @as([pf.LANES]f32, fg_b_field);
        
        _ = fg_r_arr;
        _ = fg_g_arr;
        _ = fg_b_arr;
        
        var final_r_arr: [pf.LANES]f32 = bg_r_arr;
        var final_g_arr: [pf.LANES]f32 = bg_g_arr;
        var final_b_arr: [pf.LANES]f32 = bg_b_arr;

        const local_x_arr: [pf.LANES]f32 = @as([pf.LANES]f32, x_p - pf.Core.constant(c.draw_x_start));
        const local_y_arr: [pf.LANES]f32 = @as([pf.LANES]f32, y_p - pf.Core.constant(c.draw_y_start));

        for (0..pf.LANES) |lane_idx| {
            const lx_scalar = local_x_arr[lane_idx];
            const ly_scalar = local_y_arr[lane_idx];

            if (lx_scalar >= 0 and lx_scalar < @as(f32, @floatFromInt(c.glyph_width)) and ly_scalar >= 0 and ly_scalar < @as(f32, @floatFromInt(c.glyph_height))) {
                const tex_x = @as(usize, @intFromFloat(lx_scalar));
                const tex_y = @as(usize, @intFromFloat(ly_scalar));
                    
                const alpha = c.glyph_bitmap[tex_y * c.glyph_width + tex_x];
                
                // Debug: Render Alpha as Green
                final_r_arr[lane_idx] = 0.0;
                final_g_arr[lane_idx] = @as(f32, @floatFromInt(alpha)) / 255.0;
                final_b_arr[lane_idx] = 0.0;

                // Debug: Blue stripe at tex_x == 5 (middle of 'e')
                if (tex_x == 5) {
                     final_b_arr[lane_idx] = 1.0;
                }
            }
        }

        return .{ .r = @as(pf.Field, final_r_arr), .g = @as(pf.Field, final_g_arr), .b = @as(pf.Field, final_b_arr), .a = @splat(1.0) };
    }
};

const TitleBarContext = struct {
    w: f32,
    h: f32,
    title_bar_h: usize,
    close_btn_s: usize,
};

const TitleBarEvaluator = struct {
    pub fn eval(c: TitleBarContext, x: pf.Field, y: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
        const title_bar_rect = shapes.Rectangle{
            .width = c.w,
            .height = @as(f32, @floatFromInt(c.title_bar_h)),
            .center_x = c.w / 2.0,
            .center_y = @as(f32, @floatFromInt(c.title_bar_h)) / 2.0,
        };
        const title_bar_mask = title_bar_rect.stencil(x, y);
        const title_bar_r: pf.Field = @splat(0.2);
        const title_bar_g: pf.Field = @splat(0.2);
        const title_bar_b: pf.Field = @splat(0.25);

        const close_btn_rect = shapes.Rectangle{
            .width = @as(f32, @floatFromInt(c.close_btn_s)),
            .height = @as(f32, @floatFromInt(c.close_btn_s)),
            .center_x = c.w - @as(f32, @floatFromInt(c.close_btn_s)) / 2.0,
            .center_y = @as(f32, @floatFromInt(c.title_bar_h)) / 2.0,
        };
        const close_btn_mask = close_btn_rect.stencil(x, y);
        const close_btn_r: pf.Field = @splat(0.8);
        const close_btn_g: pf.Field = @splat(0.1);
        const close_btn_b: pf.Field = @splat(0.1);
        
        var r = pf.Core.mix(@splat(0.0), title_bar_r, title_bar_mask);
        var g = pf.Core.mix(@splat(0.0), title_bar_g, title_bar_mask);
        var b = pf.Core.mix(@splat(0.0), title_bar_b, title_bar_mask);

        r = pf.Core.mix(r, close_btn_r, close_btn_mask);
        g = pf.Core.mix(g, close_btn_g, close_btn_mask);
        b = pf.Core.mix(b, close_btn_b, close_btn_mask);

        return .{ .r = r, .g = g, .b = b, .a = @splat(1.0) };
    }
};

fn draw_terminal_slice(ctx: TerminalContext, width_px: usize, out_slice: []u32, y_start_global: usize) void {
    const height_slice = out_slice.len / width_px;
    
    // Fill background
    for (0..height_slice) |y_local| {
        const y_global = y_start_global + y_local;
        const row_offset = y_local * width_px;
        const row_slice = out_slice[row_offset .. row_offset + width_px];
        pf.evaluate(TerminalEvaluator.fill_eval, ctx, 0.0, @as(f32, @floatFromInt(y_global)), row_slice);
    }

    const slice_min_y = @as(f32, @floatFromInt(y_start_global));
    const slice_max_y = @as(f32, @floatFromInt(y_start_global + height_slice));
    const term_offset = @as(f32, @floatFromInt(TITLE_BAR_HEIGHT));

    // Iterate grid rows
    for (0..ctx.terminal_grid.height) |row_idx| {
        const cell_top_y = @as(f32, @floatFromInt(row_idx)) * CHAR_HEIGHT + term_offset;
        const cell_bottom_y = cell_top_y + CHAR_HEIGHT;
        
        if (cell_bottom_y <= slice_min_y or cell_top_y >= slice_max_y) continue;
        
        for (0..ctx.terminal_grid.width) |col_idx| {
            const cell = ctx.terminal_grid.cells[row_idx * ctx.terminal_grid.width + col_idx];
            
            const pixel_x_start = @as(f32, @floatFromInt(col_idx)) * CHAR_WIDTH;
            const pixel_y_start = cell_top_y; 

            // Lookup Cached Glyph (Must be pre-populated!)
            const glyph_ptr = ctx.atlas.cache.getPtr(atlas_mod.GlyphKey{ .codepoint = cell.character, .size = FONT_SIZE });
            
            if (glyph_ptr) |glyph| {
                if (cell.character == 101) {
                     std.debug.print("Render use 'e' ptr: {*}\n", .{glyph.bitmap.ptr});
                }
                const is_cursor_cell = col_idx == ctx.cursor_x and row_idx == ctx.cursor_y;

                var fg_color_val = cell.fg_color;
                var bg_color_val = cell.bg_color;
                var is_inverse_val = cell.is_inverse;

                if (is_cursor_cell) is_inverse_val = !is_inverse_val;
                if (is_inverse_val) {
                    const temp_c = fg_color_val;
                    fg_color_val = bg_color_val;
                    bg_color_val = temp_c;
                }

                // Calculate actual drawing offsets for the glyph bitmap
                // Horizontally: center the glyph within its CHAR_WIDTH space, plus its x_min
                const glyph_x_offset_in_cell = glyph.scaled_x_min + (CHAR_WIDTH - @as(f32, @floatFromInt(glyph.width))) / 2.0;
                const draw_x_start = pixel_x_start + glyph_x_offset_in_cell;

                // Vertically: Center glyph within cell
                const draw_y_start = pixel_y_start + (CHAR_HEIGHT - @as(f32, @floatFromInt(glyph.height))) / 2.0;

                const cell_ctx = CellRenderContext{
                    .fg_r = @as(f32, @floatFromInt(fg_color_val.r)) / 255.0,
                    .fg_g = @as(f32, @floatFromInt(fg_color_val.g)) / 255.0,
                    .fg_b = @as(f32, @floatFromInt(fg_color_val.b)) / 255.0,
                    .bg_r = @as(f32, @floatFromInt(bg_color_val.r)) / 255.0,
                    .bg_g = @as(f32, @floatFromInt(bg_color_val.g)) / 255.0,
                    .bg_b = @as(f32, @floatFromInt(bg_color_val.b)) / 255.0,
                    .is_bold = cell.is_bold,
                    .is_inverse = is_inverse_val,
                    .glyph_bitmap = glyph.bitmap,
                    .glyph_width = glyph.width,
                    .glyph_height = glyph.height,
                    .scaled_x_min = glyph.scaled_x_min,
                    .scaled_y_max = glyph.scaled_y_max,
                    .scaled_ascent = glyph.scaled_ascent,
                    .scaled_descent = glyph.scaled_descent,
                    .draw_x_start = draw_x_start,
                    .draw_y_start = draw_y_start,
                };

                const char_height_usize: usize = @as(usize, @intFromFloat(CHAR_HEIGHT));
                const char_width_usize: usize = @as(usize, @intFromFloat(CHAR_WIDTH));
                
                for (0..char_height_usize) |char_row_offset| {
                    const current_pixel_y_global = pixel_y_start + @as(f32, @floatFromInt(char_row_offset));
                    if (current_pixel_y_global < slice_min_y or current_pixel_y_global >= slice_max_y) continue;
                    
                    const slice_y_idx = @as(usize, @intFromFloat(current_pixel_y_global - slice_min_y));
                    const current_row_start_idx = slice_y_idx * width_px + @as(usize, @intFromFloat(pixel_x_start));
                    
                    if (current_row_start_idx + char_width_usize <= out_slice.len) {
                        const pixel_slice = out_slice[current_row_start_idx .. current_row_start_idx + char_width_usize];
                        pf.evaluate(CellEvaluator.eval, cell_ctx, pixel_x_start, current_pixel_y_global, pixel_slice);
                    }
                }
            }
        }
    }
    
    // Draw Title Bar (if overlaps slice)
    if (y_start_global < TITLE_BAR_HEIGHT) {
        const tb_ctx = TitleBarContext{ 
            .w = @as(f32, @floatFromInt(ctx.width_px)), 
            .h = @as(f32, @floatFromInt(ctx.height_px)), 
            .title_bar_h = TITLE_BAR_HEIGHT,
            .close_btn_s = CLOSE_BUTTON_SIZE,
        };
        const end_tb = @min(TITLE_BAR_HEIGHT, y_start_global + height_slice);
        
        for (y_start_global..end_tb) |y_global| {
            const y_local = y_global - y_start_global;
            const row_offset = y_local * width_px;
            const row_slice = out_slice[row_offset .. row_offset + width_px];
            pf.evaluate(TitleBarEvaluator.eval, tb_ctx, 0.0, @as(f32, @floatFromInt(y_global)), row_slice);
        }
    }
}

pub fn draw_demo_pattern(allocator: std.mem.Allocator, width_px: i32, height_px: i32, time: f32, out_buffer: []u32, terminal_grid: *grid.Grid, cursor_x: usize, cursor_y: usize, atlas: *atlas_mod.Atlas) !void {
    _ = time;
    
    // Pre-populate Atlas Cache
    for (terminal_grid.cells) |cell| {
        try atlas.ensureCached(cell.character, FONT_SIZE);
    }
    try atlas.ensureCached('?', FONT_SIZE);
    try atlas.ensureCached(' ', FONT_SIZE);

    const ctx = TerminalContext{
        .width_px = width_px,
        .height_px = height_px,
        .terminal_grid = terminal_grid,
        .cursor_x = cursor_x,
        .cursor_y = cursor_y,
        .atlas = atlas,
        .overall_bg_ctx = .{ .r = @splat(0.1), .g = @splat(0.1), .b = @splat(0.1) },
    };

    const num_threads = 12;
    const rows_per_thread = @as(usize, @intCast(height_px)) / num_threads + 1;
    var threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    for (0..num_threads) |i| {
        const start_y = i * rows_per_thread;
        if (start_y >= height_px) {
            threads[i] = try std.Thread.spawn(.{}, empty_worker, .{});
            continue;
        }
        var end_y = (i + 1) * rows_per_thread;
        if (end_y > height_px) end_y = @as(usize, @intCast(height_px));
        
        const slice = out_buffer[start_y * @as(usize, @intCast(width_px)) .. end_y * @as(usize, @intCast(width_px))];
        threads[i] = try std.Thread.spawn(.{}, draw_terminal_slice, .{ ctx, @as(usize, @intCast(width_px)), slice, start_y });
    }
    
    for (threads) |t| t.join();
}

fn empty_worker() void {}

// --- Sphere Demo ---

const SphereContext = struct {
    w: f32,
    h: f32,
    t: f32,
};

const SphereEvaluator = struct {
    pub fn eval(c: SphereContext, x: pf.Field, y: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
        const ndc_x = (x / pf.Core.constant(c.w)) * pf.Core.constant(2.0) - pf.Core.constant(1.0);
        const ndc_y = (pf.Core.constant(1.0) - (y / pf.Core.constant(c.h)) * pf.Core.constant(2.0)); 
        const aspect = c.w / c.h;
        const screen_x = ndc_x * pf.Core.constant(aspect);
        const screen_y = ndc_y;

        const cam_origin = vec3.Vec3.init(pf.Core.constant(0.0), pf.Core.constant(1.0), pf.Core.constant(-4.0));
        const screen_point = vec3.Vec3.init(screen_x, screen_y, pf.Core.constant(-2.0));
        const ray_dir = screen_point.sub(cam_origin).normalize();
        const ray = scene3d.Ray{ .origin = cam_origin, .dir = ray_dir };

        const sphere_x = @sin(pf.Core.constant(c.t)) * pf.Core.constant(2.0);
        const sphere_z = @cos(pf.Core.constant(c.t)) * pf.Core.constant(0.5); 
        const sphere = scene3d.Sphere{
            .center = vec3.Vec3.init(sphere_x, pf.Core.constant(0.0), sphere_z),
            .radius = pf.Core.constant(1.0),
        };
        const plane = scene3d.Plane{ .height = pf.Core.constant(-1.0) };

        const color = scene3d.render_scene(ray, sphere, plane);
        return .{ .r = color.r, .g = color.g, .b = color.b, .a = @splat(1.0) };
    }
};

fn draw_sphere_slice(ctx: SphereContext, width_px: usize, out_slice: []u32, y_start_global: usize) void {
    const height_slice = out_slice.len / width_px;
    for (0..height_slice) |y_local| {
        const y_global = y_start_global + y_local;
        const row_offset = y_local * width_px;
        const row_slice = out_slice[row_offset .. row_offset + width_px];
        pf.evaluate(SphereEvaluator.eval, ctx, 0.0, @as(f32, @floatFromInt(y_global)), row_slice);
    }
}

pub fn draw_sphere_demo(allocator: std.mem.Allocator, width_px: i32, height_px: i32, time: f32, out_buffer: []u32) !void {
    const w_f = @as(f32, @floatFromInt(width_px));
    const h_f = @as(f32, @floatFromInt(height_px));
    const ctx = SphereContext{ .w = w_f, .h = h_f, .t = time };

    const num_threads = 12;
    const rows_per_thread = @as(usize, @intCast(height_px)) / num_threads + 1;
    var threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    for (0..num_threads) |i| {
        const start_y = i * rows_per_thread;
        if (start_y >= height_px) {
            threads[i] = try std.Thread.spawn(.{}, empty_worker, .{});
            continue;
        }
        var end_y = (i + 1) * rows_per_thread;
        if (end_y > height_px) end_y = @as(usize, @intCast(height_px));
        
        const slice = out_buffer[start_y * @as(usize, @intCast(width_px)) .. end_y * @as(usize, @intCast(width_px))];
        threads[i] = try std.Thread.spawn(.{}, draw_sphere_slice, .{ ctx, @as(usize, @intCast(width_px)), slice, start_y });
    }
    
    for (threads) |t| t.join();
}
