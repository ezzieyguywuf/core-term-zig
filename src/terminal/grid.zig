const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b };
    }

    pub const BLACK = Color.init(0, 0, 0);
    pub const WHITE = Color.init(255, 255, 255);
    pub const RED = Color.init(255, 0, 0);
    pub const GREEN = Color.init(0, 255, 0);
    pub const BLUE = Color.init(0, 0, 255);
    pub const CYAN = Color.init(0, 255, 255);
    pub const MAGENTA = Color.init(255, 0, 255);
    pub const YELLOW = Color.init(255, 255, 0);
    pub const BRIGHT_BLACK = Color.init(128, 128, 128);
    pub const BRIGHT_RED = Color.init(255, 128, 128);
    pub const BRIGHT_GREEN = Color.init(128, 255, 128);
    pub const BRIGHT_YELLOW = Color.init(255, 255, 128);
    pub const BRIGHT_BLUE = Color.init(128, 128, 255);
    pub const BRIGHT_MAGENTA = Color.init(255, 128, 255);
    pub const BRIGHT_CYAN = Color.init(128, 255, 255);
    pub const BRIGHT_WHITE = Color.init(255, 255, 255);
};

pub const Cell = struct {
    character: u21,
    fg_color: Color,
    bg_color: Color,
    is_bold: bool,
    is_italic: bool,
    is_underline: bool,
    is_inverse: bool,

    pub fn init(character: u21, fg_color: Color, bg_color: Color) Cell {
        return .{
            .character = character,
            .fg_color = fg_color,
            .bg_color = bg_color,
            .is_bold = false,
            .is_italic = false,
            .is_underline = false,
            .is_inverse = false,
        };
    }

    pub fn default() Cell {
        return Cell.init(' ', Color.WHITE, Color.BLACK);
    }
};

pub const Grid = struct {
    width: usize,
    height: usize,
    cells: []Cell,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !*Grid {
        const grid = try allocator.create(Grid);
        grid.width = width;
        grid.height = height;
        grid.allocator = allocator;
        grid.cells = try allocator.alloc(Cell, width * height);
        for (grid.cells) |*cell| {
            cell.* = Cell.default();
        }
        return grid;
    }

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.cells);
        self.allocator.destroy(self);
    }

    pub fn get_cell(self: *Grid, x: usize, y: usize) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        return &self.cells[y * self.width + x];
    }

    pub fn set_cell(self: *Grid, x: usize, y: usize, cell: Cell) void {
        if (x >= self.width or y >= self.height) return;
        self.cells[y * self.width + x] = cell;
    }

    pub fn resize(self: *Grid, allocator: std.mem.Allocator, new_width: usize, new_height: usize) !void {
        const old_cells = self.cells;
        const old_width = self.width;
        const old_height = self.height;

        self.cells = try allocator.alloc(Cell, new_width * new_height);
        self.width = new_width;
        self.height = new_height;

        for (self.cells) |*cell| {
            cell.* = Cell.default();
        }

        // Copy old content to new grid
        for (0..@min(old_height, new_height)) |y_idx| {
            for (0..@min(old_width, new_width)) |x_idx| {
                self.set_cell(x_idx, y_idx, old_cells[y_idx * old_width + x_idx]);
            }
        }

        allocator.free(old_cells);
    }
};
