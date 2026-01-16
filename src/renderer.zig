const std = @import("std");
const pf = @import("pixelflow/core.zig");
const shapes = @import("pixelflow/shapes.zig");
const grid = @import("terminal/grid.zig");

pub const CHAR_WIDTH: f32 = 8.0;
pub const CHAR_HEIGHT: f32 = 16.0;

pub fn draw_demo_pattern(width_px: i32, height_px: i32, time: f32, out_buffer: []u32, terminal_grid: *grid.Grid) !void {

    const Context = struct {
        r: f32,
        g: f32,
        b: f32,
        char_w: f32,
        char_h: f32,
        grid_w: usize,
    };

    // Iterate over each cell in the terminal grid
    for (0..terminal_grid.height) |row_idx| {
        for (0..terminal_grid.width) |col_idx| {
            const cell = terminal_grid.cells[row_idx * terminal_grid.width + col_idx];
            const bg_color = cell.bg_color;
            
            // Calculate pixel coordinates for this cell
            const pixel_x_start = @as(f32, @floatFromInt(col_idx)) * CHAR_WIDTH;
            const pixel_y_start = @as(f32, @floatFromInt(row_idx)) * CHAR_HEIGHT;

            const ctx = Context{
                .r = @as(f32, @floatFromInt(bg_color.r)) / 255.0,
                .g = @as(f32, @floatFromInt(bg_color.g)) / 255.0,
                .b = @as(f32, @floatFromInt(bg_color.b)) / 255.0,
                .char_w = CHAR_WIDTH,
                .char_h = CHAR_HEIGHT,
                .grid_w = @as(usize, @intCast(width_px)), // Actual pixel width of the buffer
            };

            // Define a simple rectangle for the cell's background
            const cell_painter = struct {
                pub fn eval(c: Context, x: pf.Field, y: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
                    const cell_rect = shapes.Rectangle{
                        .width = c.char_w,
                        .height = c.char_h,
                        .center_x = x.get(0) + c.char_w / 2.0, // x.get(0) is the start of the current SIMD lane
                        .center_y = y.get(0) + c.char_h / 2.0,
                    };
                    
                    // The stencil will be 1.0 inside the cell, 0.0 outside
                    const mask = cell_rect.stencil(x, y);

                    // Draw the cell's background color
                    const color_r = pf.Core.constant(c.r);
                    const color_g = pf.Core.constant(c.g);
                    const color_b = pf.Core.constant(c.b);

                    return .{ 
                        .r = pf.Core.mix(@splat(0.0), color_r, mask),
                        .g = pf.Core.mix(@splat(0.0), color_g, mask),
                        .b = pf.Core.mix(@splat(0.0), color_b, mask),
                        .a = @splat(1.0) 
                    };
                }
            };

            const row_offset = @as(usize, @intCast(pixel_y_start)) * @as(usize, @intCast(width_px)) + @as(usize, @intCast(pixel_x_start));
            const cell_pixel_slice = out_buffer[row_offset .. row_offset + @as(usize, @intCast(CHAR_WIDTH)) * @as(usize, @intCast(CHAR_HEIGHT))];

            // Evaluate for the current cell's pixel area
            pf.evaluate(cell_painter.eval, ctx, pixel_x_start, pixel_y_start, cell_pixel_slice);
        }
    }

    // For demo, keep drawing the animated cursor on top of everything
    // (This part will eventually be removed or integrated with terminal cursor)
    const w_f = @as(f32, @floatFromInt(width_px));
    const h_f = @as(f32, @floatFromInt(height_px));

    const CursorContext = struct {
        w: f32,
        h: f32,
        t: f32,
    };
    const cursor_ctx = CursorContext{ .w = w_f, .h = h_f, .t = time };

    const cursor_painter = struct {
        pub fn eval(c: CursorContext, x: pf.Field, y: pf.Field) struct { r: pf.Field, g: pf.Field, b: pf.Field, a: pf.Field } {
            // Cursor: Circle moving
            const term_w = c.w * 0.8; // Use same terminal dimensions as before for cursor calculation
            const term_h = c.h * 0.8;
            const cursor_x = c.w / 2.0 + @sin(c.t) * (term_w / 2.0 - 50.0);
            const cursor_y = c.h / 2.0 + @cos(c.t) * (term_h / 2.0 - 50.0);
            
            const cursor = shapes.Circle{
                .radius = 20.0,
                .center_x = cursor_x,
                .center_y = cursor_y,
            };
            
            const d_cursor = cursor.eval(x, y);
            const cursor_mask = d_cursor <= @as(pf.Field, @splat(0.0));
            
            const cur_r: pf.Field = @splat(0.0);
            const cur_g: pf.Field = @splat(1.0);
            const cur_b: pf.Field = @splat(0.0);
            
            // Read existing pixel data from the buffer to blend with cursor
            // This would require a `materialize_into_fields` or similar, 
            // which is more complex. For now, we will draw cursor on black.
            // Or, for a quick PoC, we assume the existing background is already drawn
            // and just overlay the cursor.
            // We need current color to mix.

            // This part is tricky. pf.evaluate writes into out_buffer. If we want to read existing data,
            // we need to pass a slice of current colors to this eval.
            // For now, I'll draw the cursor on a black background, and it will overwrite.
            // A proper solution involves another `pf.evaluate` call to get existing pixels, or texture sampling.

            return .{ 
                .r = pf.Core.select(cursor_mask, cur_r, @splat(0.0)),
                .g = pf.Core.select(cursor_mask, cur_g, @splat(0.0)),
                .b = pf.Core.select(cursor_mask, cur_b, @splat(0.0)),
                .a = @splat(1.0) 
            };
        }
    };
    
    // This will overwrite existing pixels where cursor is drawn.
    // A more advanced rendering would read existing pixels and blend.
    for (0..@intCast(height_px)) |row| {
        const row_offset = row * @as(usize, @intCast(width_px));
        const row_slice = out_buffer[row_offset .. row_offset + @as(usize, @intCast(width_px))];
        pf.evaluate(cursor_painter.eval, cursor_ctx, 0.0, @as(f32, @floatFromInt(row)), row_slice);
    }

}
