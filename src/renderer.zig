const std = @import("std");
const pf = @import("pixelflow/core.zig");
const shapes = @import("pixelflow/shapes.zig");
const grid = @import("terminal/grid.zig");
const font = @import("font.zig"); // Corrected import path

pub const CHAR_WIDTH: f32 = @as(f32, font.FONT_WIDTH);
pub const CHAR_HEIGHT: f32 = @as(f32, font.FONT_HEIGHT);

pub fn draw_demo_pattern(width_px: i32, height_px: i32, time: f32, out_buffer: []u32, terminal_grid: *grid.Grid) !void {
    _ = time; // Mark as unused if not directly used outside of cursor drawing

    // We will draw the entire buffer first with the overall background, then overlay terminal cells
    for (0..@intCast(height_px)) |y_px| {
        const row_offset = y_px * @as(usize, @intCast(width_px));
        const row_slice = out_buffer[row_offset .. row_offset + @as(usize, @intCast(width_px))];
        const fill_context = struct {
            pub fn eval(_: void, x_field: pf.Field, y_field: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
                _ = x_field;
                _ = y_field;
                return .{ .r = bg_r_overall, .g = bg_g_overall, .b = bg_b_overall, .a = @splat(1.0) };
            }
        };
        try pf.evaluate(fill_context.eval, {}, 0.0, @as(f32, @floatFromInt(y_px)), row_slice);
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
    };

    // Iterate over each cell in the terminal grid
    for (0..terminal_grid.height) |row_idx| {
        for (0..terminal_grid.width) |col_idx| {
            const cell = terminal_grid.cells[row_idx * terminal_grid.width + col_idx];
            
            // Calculate pixel coordinates for this cell
            const pixel_x_start = @as(f32, @floatFromInt(col_idx)) * CHAR_WIDTH;
            const pixel_y_start = @as(f32, @floatFromInt(row_idx)) * CHAR_HEIGHT;

            const is_cursor_cell = 
                col_idx == terminal_grid.cursor_x and 
                row_idx == terminal_grid.cursor_y;

            var fg_color = cell.fg_color;
            var bg_color = cell.bg_color;
            var is_inverse = cell.is_inverse;

            if (is_cursor_cell) {
                // Invert colors for cursor (or other cursor style)
                is_inverse = !is_inverse;
            }

            if (is_inverse) {
                const temp_c = fg_color;
                fg_color = bg_color;
                bg_color = temp_c;
            }

            const ctx = CellRenderContext{
                .fg_r = @as(f32, @floatFromInt(fg_color.r)) / 255.0,
                .fg_g = @as(f32, @floatFromInt(fg_color.g)) / 255.0,
                .fg_b = @as(f32, @floatFromInt(fg_color.b)) / 255.0,
                .bg_r = @as(f32, @floatFromInt(bg_color.r)) / 255.0,
                .bg_g = @as(f32, @floatFromInt(bg_color.g)) / 255.0,
                .bg_b = @as(f32, @floatFromInt(bg_color.b)) / 255.0,
                .is_bold = cell.is_bold,
                .is_inverse = is_inverse,
                .character_bitmap = if (cell.character < font.BITMAP_FONT.len) 
                                      font.BITMAP_FONT[cell.character] 
                                  else 
                                      font.BITMAP_FONT['?'], // Fallback for unprintable
            };

            // Manifold for a single cell, including its background and character
            const cell_painter = struct {
                pub fn eval(c: CellRenderContext, x_p: pf.Field, y_p: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
                    // 1. Draw cell background
                    const current_x_px = x_p.get(0); // Current pixel column for SIMD lane
                    const current_y_px = y_p.get(0); // Current pixel row for SIMD lane

                    const local_x = x_p - pf.Core.constant(current_x_px); // X relative to cell origin
                    const local_y = y_p - pf.Core.constant(current_y_px); // Y relative to cell origin

                    const bg_r = pf.Core.constant(c.bg_r);
                    const bg_g = pf.Core.constant(c.bg_g);
                    const bg_b = pf.Core.constant(c.bg_b);

                    // Draw character pixels over background
                    var final_r = bg_r;
                    var final_g = bg_g;
                    var final_b = bg_b;

                    const fg_r = pf.Core.constant(c.fg_r);
                    const fg_g = pf.Core.constant(c.fg_g);
                    const fg_b = pf.Core.constant(c.fg_b);

                    // This `eval` is called for a slice of output pixels, typically a full row segment.
                    // We need to iterate over SIMD lanes for each pixel.
                    for (0..pf.LANES) |lane_idx| {
                        const lx_scalar = local_x.get(lane_idx);
                        const ly_scalar = local_y.get(lane_idx);

                        if (lx_scalar >= 0 and lx_scalar < CHAR_WIDTH and ly_scalar >= 0 and ly_scalar < CHAR_HEIGHT) {
                            // Inside the character cell
                            const font_row_idx = @as(usize, @intFromFloat(ly_scalar));
                            const font_col_idx = @as(usize, @intFromFloat(lx_scalar));
                            
                            if (font_row_idx < font.FONT_HEIGHT and font_col_idx < font.FONT_WIDTH) {
                                const row_byte = c.character_bitmap[font_row_idx];
                                const is_pixel_set = (row_byte >> (font.FONT_WIDTH - 1 - font_col_idx)) & 0x01;

                                if (is_pixel_set != 0) {
                                    final_r.set(lane_idx, fg_r.get(lane_idx));
                                    final_g.set(lane_idx, fg_g.get(lane_idx));
                                    final_b.set(lane_idx, fg_b.get(lane_idx));
                                    
                                    if (c.is_bold) {
                                        // Simple bolding: make slightly brighter
                                        final_r.set(lane_idx, @min(1.0, fg_r.get(lane_idx) * 1.2));
                                        final_g.set(lane_idx, @min(1.0, fg_g.get(lane_idx) * 1.2));
                                        final_b.set(lane_idx, @min(1.0, fg_b.get(lane_idx) * 1.2));
                                    }
                                }
                            }
                        }
                    }

                    return .{ .r = final_r, .g = final_g, .b = final_b, .a = @splat(1.0) };
                }
            };

            // pf.evaluate will call cell_painter.eval for each SIMD lane group
            // For each pixel row of the character, we need to call evaluate separately
            for (0..@as(usize, @intCast(CHAR_HEIGHT))) |char_row_offset| {
                const current_pixel_y = pixel_y_start + @as(f32, @floatFromInt(char_row_offset));
                const current_row_start_idx = @as(usize, @intFromFloat(current_pixel_y)) * @as(usize, @intCast(width_px)) + @as(usize, @intFromFloat(pixel_x_start));
                
                if (current_row_start_idx + pf.LANES <= out_buffer.len) {
                    const pixel_slice_for_row = out_buffer[current_row_start_idx .. current_row_start_idx + pf.LANES];
                    try pf.evaluate(cell_painter.eval, ctx, pixel_x_start, current_pixel_y, pixel_slice_for_row);
                }
            }
        }
    }

    // Draw title bar on top of everything
    const TITLE_BAR_HEIGHT: f32 = 30.0;
    const CLOSE_BUTTON_SIZE: f32 = 30.0;

    const TitleBarContext = struct {
        w: f32,
        h: f32,
        title_bar_h: f32,
        close_btn_s: f32,
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
                .height = c.title_bar_h,
                .center_x = c.w / 2.0,
                .center_y = c.title_bar_h / 2.0,
            };
            const title_bar_mask = title_bar_rect.stencil(x, y);
            const title_bar_r: pf.Field = @splat(0.2);
            const title_bar_g: pf.Field = @splat(0.2);
            const title_bar_b: pf.Field = @splat(0.25);

            // Close Button
            const close_btn_rect = shapes.Rectangle{
                .width = c.close_btn_s,
                .height = c.close_btn_s,
                .center_x = c.w - c.close_btn_s / 2.0,
                .center_y = c.title_bar_h / 2.0,
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
    for (0..@as(usize, @intCast(TITLE_BAR_HEIGHT))) |y_px| {
        const row_offset = y_px * @as(usize, @intCast(width_px));
        const row_slice = out_buffer[row_offset .. row_offset + @as(usize, @intCast(width_px))];
        try pf.evaluate(title_bar_painter.eval, title_bar_ctx, 0.0, @as(f32, @floatFromInt(y_px)), row_slice);
    }
}