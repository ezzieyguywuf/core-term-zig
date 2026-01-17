const std = @import("std");
const grid = @import("grid.zig");

pub const Terminal = struct {
    grid: *grid.Grid,
    allocator: std.mem.Allocator,
    cursor_x: usize,
    cursor_y: usize,
    current_fg_color: grid.Color,
    current_bg_color: grid.Color,
    is_bold: bool,
    is_italic: bool,
    is_underline: bool,
    is_inverse: bool,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !*Terminal {
        const term = try allocator.create(Terminal);
        term.grid = try grid.Grid.init(allocator, width, height);
        term.allocator = allocator;
        term.cursor_x = 0;
        term.cursor_y = 0;
        term.current_fg_color = grid.Color.WHITE;
        term.current_bg_color = grid.Color.BLACK;
        term.is_bold = false;
        term.is_italic = false;
        term.is_underline = false;
        term.is_inverse = false;
        return term;
    }

    pub fn deinit(self: *Terminal) void {
        self.grid.deinit();
        self.allocator.destroy(self);
    }

    pub fn write_char(self: *Terminal, char: u21) void {
        if (self.cursor_x >= self.grid.width) {
            self.cursor_x = 0;
            self.cursor_y +|= 1;
        }
        if (self.cursor_y >= self.grid.height) {
            // TODO: Implement scrolling
            self.cursor_y = self.grid.height - 1;
        }

        var cell = grid.Cell.init(char, self.current_fg_color, self.current_bg_color);
        cell.is_bold = self.is_bold;
        cell.is_italic = self.is_italic;
        cell.is_underline = self.is_underline;
        cell.is_inverse = self.is_inverse;
        self.grid.set_cell(self.cursor_x, self.cursor_y, cell);
        self.cursor_x +|= 1;
    }

    pub fn write_string(self: *Terminal, str: []const u8) void {
        for (str) |char_u8| {
            // Basic ASCII for now, handle UTF-8 later
            self.write_char(@as(u21, char_u8));
        }
    }

    pub fn set_cursor_pos(self: *Terminal, x: usize, y: usize) void {
        self.cursor_x = @min(x, self.grid.width - 1);
        self.cursor_y = @min(y, self.grid.height - 1);
    }

    pub fn clear(self: *Terminal) void {
        for (self.grid.cells) |*cell| {
            cell.* = grid.Cell.default();
        }
        self.cursor_x = 0;
        self.cursor_y = 0;
    }

    pub fn resize(self: *Terminal, new_width: usize, new_height: usize) !void {
        try self.grid.resize(self.allocator, new_width, new_height);
        self.cursor_x = @min(self.cursor_x, self.grid.width - 1);
        self.cursor_y = @min(self.cursor_y, self.grid.height - 1);
    }
};
