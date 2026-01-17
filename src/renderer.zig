const std = @import("std");
const pf = @import("pixelflow/core.zig");
const shapes = @import("pixelflow/shapes.zig");
const grid = @import("terminal/grid.zig");
const font = @import("font.zig");

pub const CHAR_WIDTH: f32 = @as(f32, font.FONT_WIDTH);
pub const CHAR_HEIGHT: f32 = @as(f32, font.FONT_HEIGHT);

pub const TITLE_BAR_HEIGHT: usize = 30;
pub const CLOSE_BUTTON_SIZE: usize = 30;

pub fn draw_demo_pattern(width_px: i32, height_px: i32, time: f32, out_buffer: []u32, terminal_grid: *grid.Grid, cursor_x: usize, cursor_y: usize) !void {
    // Background for areas outside the terminal
    const OverallBackgroundContext = struct {
        r: pf.Field,
        g: pf.Field,
        b: pf.Field,
    };
    const overall_bg_ctx = OverallBackgroundContext{
        .r = @splat(0.1),
        .g = @splat(0.1),
        .b = @splat(0.1),
    };

    // We will draw the entire buffer first with the overall background, then overlay terminal cells
    for (0..@intCast(height_px)) |y_px| {
        const row_offset = y_px * @as(usize, @intCast(width_px));
        const row_slice = out_buffer[row_offset .. row_offset + @as(usize, @intCast(width_px))];
        const fill_context = struct {
            pub fn eval(c: OverallBackgroundContext, x_field: pf.Field, y_field: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
                _ = x_field;
                _ = y_field;
                return .{ .r = c.r, .g = c.g, .b = c.b, .a = @splat(1.0) };
            }
        };
        pf.evaluate(fill_context.eval, overall_bg_ctx, 0.0, @as(f32, @floatFromInt(y_px)), row_slice);
    }

    const CellRenderContext = struct {
        fg_r: f32,
        fg_g: f32,
        fg_b: f32,
        bg_r: f32,
        bg_g: f32,
        bg_b: f32,
        is_bold: bool,
        is_inverse: bool,
        character_bitmap: [font.FONT_HEIGHT]u8,
        // The actual x and y pixel position of the top-left of the cell being drawn
        cell_pixel_x: f32,
        cell_pixel_y: f32,
    };

    // Iterate over each cell in the terminal grid
    for (0..terminal_grid.height) |row_idx| {
        for (0..terminal_grid.width) |col_idx| {
            const cell = terminal_grid.cells[row_idx * terminal_grid.width + col_idx];
            
            // Calculate pixel coordinates for this cell
            const pixel_x_start = @as(f32, @floatFromInt(col_idx)) * CHAR_WIDTH;
            const pixel_y_start = @as(f32, @floatFromInt(row_idx)) * CHAR_HEIGHT;

            const is_cursor_cell = 
                col_idx == cursor_x and 
                row_idx == cursor_y;

            var fg_color_val = cell.fg_color;
            var bg_color_val = cell.bg_color;
            var is_inverse_val = cell.is_inverse;


            if (is_cursor_cell) {
                // Invert colors for cursor (or other cursor style)
                is_inverse_val = !is_inverse_val;
            }

            if (is_inverse_val) {
                const temp_c = fg_color_val;
                fg_color_val = bg_color_val;
                bg_color_val = temp_c;
            }

            const ctx = CellRenderContext{
                .fg_r = @as(f32, @floatFromInt(fg_color_val.r)) / 255.0,
                .fg_g = @as(f32, @floatFromInt(fg_color_val.g)) / 255.0,
                .fg_b = @as(f32, @floatFromInt(fg_color_val.b)) / 255.0,
                .bg_r = @as(f32, @floatFromInt(bg_color_val.r)) / 255.0,
                .bg_g = @as(f32, @floatFromInt(bg_color_val.g)) / 255.0,
                .bg_b = @as(f32, @floatFromInt(bg_color_val.b)) / 255.0,
                .is_bold = cell.is_bold,
                .is_inverse = is_inverse_val,
                .character_bitmap = if (cell.character < font.BITMAP_FONT.len) 
                                      font.BITMAP_FONT[cell.character] 
                                  else 
                                      font.BITMAP_FONT['?'], // Fallback for unprintable
                .cell_pixel_x = pixel_x_start,
                .cell_pixel_y = pixel_y_start,
            };

            // Manifold for a single cell, including its background and character
            const cell_painter = struct {
                pub fn eval(c: CellRenderContext, x_p: pf.Field, y_p: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
                    const bg_r_field = pf.Core.constant(c.bg_r);
                    const bg_g_field = pf.Core.constant(c.bg_g);
                    const bg_b_field = pf.Core.constant(c.bg_b);

                    const fg_r_field = pf.Core.constant(c.fg_r);
                    const fg_g_field = pf.Core.constant(c.fg_g);
                    const fg_b_field = pf.Core.constant(c.fg_b);

                    const bg_r_arr: [pf.LANES]f32 = @as([pf.LANES]f32, bg_r_field);
                    const bg_g_arr: [pf.LANES]f32 = @as([pf.LANES]f32, bg_g_field);
                    const bg_b_arr: [pf.LANES]f32 = @as([pf.LANES]f32, bg_b_field);

                    const fg_r_arr: [pf.LANES]f32 = @as([pf.LANES]f32, fg_r_field);
                    const fg_g_arr: [pf.LANES]f32 = @as([pf.LANES]f32, fg_g_field);
                    const fg_b_arr: [pf.LANES]f32 = @as([pf.LANES]f32, fg_b_field);

                    var final_r_arr: [pf.LANES]f32 = bg_r_arr;
                    var final_g_arr: [pf.LANES]f32 = bg_g_arr;
                    var final_b_arr: [pf.LANES]f32 = bg_b_arr;

                    // Convert global pixel coordinates to local character cell coordinates
                    const local_x_arr: [pf.LANES]f32 = @as([pf.LANES]f32, x_p - pf.Core.constant(c.cell_pixel_x));
                    const local_y_arr: [pf.LANES]f32 = @as([pf.LANES]f32, y_p - pf.Core.constant(c.cell_pixel_y));

                    // Iterate over each SIMD lane
                    for (0..pf.LANES) |lane_idx| {
                        const lx_scalar = local_x_arr[lane_idx];
                        const ly_scalar = local_y_arr[lane_idx];

                        // Check if pixel is within character bounds
                        if (lx_scalar >= 0 and lx_scalar < CHAR_WIDTH and ly_scalar >= 0 and ly_scalar < CHAR_HEIGHT) {
                            const font_row_idx = @as(usize, @intFromFloat(ly_scalar));
                            const font_col_idx = @as(usize, @intFromFloat(lx_scalar));
                            
                            if (font_row_idx < font.FONT_HEIGHT and font_col_idx < font.FONT_WIDTH) {
                                const row_byte = c.character_bitmap[font_row_idx];
                                // Check if the specific pixel in the bitmap is set
                                const is_pixel_set = (row_byte >> @as(u3, @intCast(font.FONT_WIDTH - 1 - font_col_idx))) & 0x01;

                                if (is_pixel_set != 0) {
                                    final_r_arr[lane_idx] = fg_r_arr[lane_idx];
                                    final_g_arr[lane_idx] = fg_g_arr[lane_idx];
                                    final_b_arr[lane_idx] = fg_b_arr[lane_idx];
                                    
                                    if (c.is_bold) {
                                        final_r_arr[lane_idx] = @min(1.0, fg_r_arr[lane_idx] * 1.2);
                                        final_g_arr[lane_idx] = @min(1.0, fg_g_arr[lane_idx] * 1.2);
                                        final_b_arr[lane_idx] = @min(1.0, fg_b_arr[lane_idx] * 1.2);
                                    }
                                }
                            }
                        }
                    }

                    return .{ .r = @as(pf.Field, final_r_arr), .g = @as(pf.Field, final_g_arr), .b = @as(pf.Field, final_b_arr), .a = @splat(1.0) };
                }
            };

            // Evaluate for each pixel row of the character
            for (0..font.FONT_HEIGHT) |char_row_offset| {
                const current_pixel_y = pixel_y_start + @as(f32, @floatFromInt(char_row_offset));
                const current_row_start_idx = @as(usize, @intFromFloat(current_pixel_y)) * @as(usize, @intCast(width_px)) + @as(usize, @intFromFloat(pixel_x_start));
                
                // Ensure the slice is within bounds and aligned for SIMD processing
                if (current_row_start_idx + pf.LANES <= out_buffer.len) {
                    const pixel_slice_for_row = out_buffer[current_row_start_idx .. current_row_start_idx + pf.LANES];
                    pf.evaluate(cell_painter.eval, ctx, pixel_x_start, current_pixel_y, pixel_slice_for_row);
                } else { 
                    // Handle potential out-of-bounds for the last few pixels in a row if not a multiple of LANES
                    // For now, skip these pixels to avoid complexity in PoC
                }
            }
        }
    }

    // Draw title bar on top of everything
    const TitleBarContext = struct {
        w: f32,
        h: f32,
        title_bar_h: usize,
        close_btn_s: usize,
    };
    
    const title_bar_ctx = TitleBarContext{ 
        .w = @as(f32, @floatFromInt(width_px)), 
        .h = @as(f32, @floatFromInt(height_px)), 
        .title_bar_h = TITLE_BAR_HEIGHT,
        .close_btn_s = CLOSE_BUTTON_SIZE,
    };

    const title_bar_painter = struct {
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

            // Close Button
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

            // Overlay close button on title bar
            r = pf.Core.mix(r, close_btn_r, close_btn_mask);
            g = pf.Core.mix(g, close_btn_g, close_btn_mask);
            b = pf.Core.mix(b, close_btn_b, close_btn_mask);

            return .{ .r = r, .g = g, .b = b, .a = @splat(1.0) };
        }
    };

    // Iterate rows for title bar and close button
    for (0..TITLE_BAR_HEIGHT) |y_px| {
        const row_offset = y_px * @as(usize, @intCast(width_px));
        const row_slice = out_buffer[row_offset .. row_offset + @as(usize, @intCast(width_px))];
        pf.evaluate(title_bar_painter.eval, title_bar_ctx, 0.0, @as(f32, @floatFromInt(y_px)), row_slice);
    }
}

pub fn draw_sphere_demo(width_px: i32, height_px: i32, time: f32, out_buffer: []u32) !void {
    const w_f = @as(f32, @floatFromInt(width_px));
    const h_f = @as(f32, @floatFromInt(height_px));

    const Context = struct {
        w: f32,
        h: f32,
        t: f32,
    };
    const ctx = Context{ .w = w_f, .h = h_f, .t = time };

    const sphere_painter = struct {
        pub fn eval(c: Context, x: pf.Field, y: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
            // UV coordinates (-1.0 to 1.0)
            const uv_x = (x / pf.Core.constant(c.w)) * @as(pf.Field, @splat(2.0)) - @as(pf.Field, @splat(1.0));
            const uv_y = (y / pf.Core.constant(c.h)) * @as(pf.Field, @splat(2.0)) - @as(pf.Field, @splat(1.0));
            
            // Correct aspect ratio
            const aspect = c.w / c.h;
            const u = uv_x * pf.Core.constant(aspect);
            const v = uv_y;

            // Animate sphere center
            const center_x = @sin(pf.Core.constant(c.t)) * @as(pf.Field, @splat(0.5));
            const center_y = @cos(pf.Core.constant(c.t * 1.3)) * @as(pf.Field, @splat(0.3));
            
            // Sphere SDF (2D circle essentially)
            const radius: pf.Field = @splat(0.5);
            const d_x = u - center_x;
            const d_y = v - center_y;
            const dist = pf.Core.sqrt(d_x * d_x + d_y * d_y) - radius;
            
            const mask = dist <= @as(pf.Field, @splat(0.0));
            
            // Shading (Fake 3D)
            // Normal (simplified)
            const n_x = d_x / radius;
            const n_y = d_y / radius;
            // Fake Z normal: sqrt(1 - x^2 - y^2)
            const n_z_sq = @as(pf.Field, @splat(1.0)) - (n_x * n_x + n_y * n_y);
            // Clamp to 0
            const n_z = pf.Core.sqrt(@max(@as(pf.Field, @splat(0.0)), n_z_sq));

            // Light direction (top-right)
            const l_x: pf.Field = @splat(0.577);
            const l_y: pf.Field = @splat(0.577);
            const l_z: pf.Field = @splat(0.577);

            // Diffuse: N dot L
            const diff = @max(@as(pf.Field, @splat(0.0)), n_x * l_x + n_y * l_y + n_z * l_z);
            
            // Specular: reflect(L, N) dot V (view is 0,0,1)
            // r = l - 2(n.l)n
            // fast specular: pow(max(0, dot(R, V)), shininess)
            // since V is 0,0,1, dot(R, V) is just R.z
            // R = I - 2.0 * dot(N, I) * N  where I = -L
            // Actually simpler: Blinn-Phong
            // H = normalize(L + V). V=(0,0,1). H = normalize(0.577, 0.577, 1.577)
            // H approx (0.3, 0.3, 0.9)
            // spec = max(0, N dot H) ^ power
            const h_x: pf.Field = @splat(0.32);
            const h_y: pf.Field = @splat(0.32);
            const h_z: pf.Field = @splat(0.89);
            
            const spec_base = @max(@as(pf.Field, @splat(0.0)), n_x * h_x + n_y * h_y + n_z * h_z);
            const spec = spec_base * spec_base * spec_base * spec_base * spec_base; // pow 32 approx

            // Chrome color
            const base_r: pf.Field = @splat(0.7);
            const base_g: pf.Field = @splat(0.7);
            const base_b: pf.Field = @splat(0.8);

            // Sky background (checkerboard?)
            // uv_y gradient
            const sky_r = @as(pf.Field, @splat(0.1)) + uv_y * @as(pf.Field, @splat(0.2));
            const sky_g = @as(pf.Field, @splat(0.1)) + uv_y * @as(pf.Field, @splat(0.1));
            const sky_b = @as(pf.Field, @splat(0.2));

            // Combine
            const sphere_r = base_r * (diff * @as(pf.Field, @splat(0.5)) + @as(pf.Field, @splat(0.2))) + spec;
            const sphere_g = base_g * (diff * @as(pf.Field, @splat(0.5)) + @as(pf.Field, @splat(0.2))) + spec;
            const sphere_b = base_b * (diff * @as(pf.Field, @splat(0.5)) + @as(pf.Field, @splat(0.2))) + spec;

            const final_r = pf.Core.select(mask, sphere_r, sky_r);
            const final_g = pf.Core.select(mask, sphere_g, sky_g);
            const final_b = pf.Core.select(mask, sphere_b, sky_b);

            return .{ .r = final_r, .g = final_g, .b = final_b, .a = @splat(1.0) };
        }
    };

    for (0..@intCast(height_px)) |y_px| {
        const row_offset = y_px * @as(usize, @intCast(width_px));
        const row_slice = out_buffer[row_offset .. row_offset + @as(usize, @intCast(width_px))];
        pf.evaluate(sphere_painter.eval, ctx, 0.0, @as(f32, @floatFromInt(y_px)), row_slice);
    }
}
