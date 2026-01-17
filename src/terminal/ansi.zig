const std = @import("std");
const grid = @import("grid.zig");
const Terminal = @import("terminal.zig").Terminal;

pub const AnsiParser = struct {
    terminal: *Terminal,
    state: AnsiState,
    params: [16]u32, // Max 16 parameters for SGR
    param_idx: usize,
    current_param: u32,

    pub const AnsiState = enum {
        Normal,
        Escape,
        Csi,
        SgrParam,
    };

    pub fn init(term: *Terminal) AnsiParser {
        return .{
            .terminal = term,
            .state = .Normal,
            .params = [_]u32{0} ** 16,
            .param_idx = 0,
            .current_param = 0,
        };
    }

    pub fn parse(self: *AnsiParser, byte: u8) void {
        switch (self.state) {
            .Normal => self.parseNormal(byte),
            .Escape => self.parseEscape(byte),
            .Csi => self.parseCsi(byte),
            .SgrParam => self.parseSgrParam(byte),
        }
    }

    fn parseNormal(self: *AnsiParser, byte: u8) void {
        switch (byte) {
            0x1B => self.state = .Escape, // ESC
            0x08 => { // BS - Backspace
                if (self.terminal.cursor_x > 0) {
                    self.terminal.cursor_x -= 1;
                }
            },
            0x0A => { // LF - Line Feed
                self.terminal.cursor_y += 1;
                // TODO: Implement scrolling if cursor_y is out of bounds
            },
            0x0D => self.terminal.cursor_x = 0, // CR - Carriage Return
            else => self.terminal.write_char(@as(u21, byte)),
        }
    }

    fn parseEscape(self: *AnsiParser, byte: u8) void {
        switch (byte) {
            0x5B => {
                self.state = .Csi;
                self.reset_params();
            }, // '[' - Control Sequence Introducer
            // TODO: Handle other escape sequences (e.g., character sets)
            else => self.state = .Normal, // Unknown escape sequence, return to normal
        }
    }

    fn parseCsi(self: *AnsiParser, byte: u8) void {
        switch (byte) {
            '0'...'9' => {
                self.current_param = self.current_param * 10 + @as(u32, byte - '0');
                self.state = .SgrParam;
            },
            ';' => {
                self.add_param();
                self.state = .SgrParam;
            },
            'm' => {
                self.add_param(); // Add last param
                self.handle_sgr();
                self.state = .Normal;
            }, // SGR - Select Graphic Rendition
            else => {
                // TODO: Handle other CSI sequences
                self.state = .Normal;
            },
        }
    }

    fn parseSgrParam(self: *AnsiParser, byte: u8) void {
        switch (byte) {
            '0'...'9' => self.current_param = self.current_param * 10 + @as(u32, byte - '0'),
            ';' => self.add_param(),
            'm' => {
                self.add_param();
                self.handle_sgr();
                self.state = .Normal;
            },
            else => {
                // Invalid char in SGR param, exit sequence
                self.state = .Normal;
            },
        }
    }

    fn reset_params(self: *AnsiParser) void {
        for (0..self.params.len) |i| {
            self.params[i] = 0;
        }
        self.param_idx = 0;
        self.current_param = 0;
    }

    fn add_param(self: *AnsiParser) void {
        if (self.param_idx < self.params.len) {
            self.params[self.param_idx] = self.current_param;
            self.param_idx += 1;
        }
        self.current_param = 0;
    }

    fn handle_sgr(self: *AnsiParser) void {
        if (self.param_idx == 0) {
            // Default SGR (reset)
            self.terminal.current_fg_color = grid.Color.WHITE;
            self.terminal.current_bg_color = grid.Color.BLACK;
            self.terminal.is_bold = false;
            self.terminal.is_italic = false;
            self.terminal.is_underline = false;
            self.terminal.is_inverse = false;
            return;
        }

        for (0..self.param_idx) |i| {
            const param = self.params[i];
            switch (param) {
                0 => {
                    // Reset all attributes
                    self.terminal.current_fg_color = grid.Color.WHITE;
                    self.terminal.current_bg_color = grid.Color.BLACK;
                    self.terminal.is_bold = false;
                    self.terminal.is_italic = false;
                    self.terminal.is_underline = false;
                    self.terminal.is_inverse = false;
                },
                1 => self.terminal.is_bold = true,
                2 => {},
                3 => self.terminal.is_italic = true,
                4 => self.terminal.is_underline = true,
                7 => self.terminal.is_inverse = true,
                21 => self.terminal.is_bold = false, // Double underline / Normal intensity
                22 => self.terminal.is_bold = false, // Normal intensity
                23 => self.terminal.is_italic = false,
                24 => self.terminal.is_underline = false,
                27 => self.terminal.is_inverse = false,
                // Foreground colors (30-37, 90-97)
                30 => self.terminal.current_fg_color = grid.Color.BLACK,
                31 => self.terminal.current_fg_color = grid.Color.RED,
                32 => self.terminal.current_fg_color = grid.Color.GREEN,
                33 => self.terminal.current_fg_color = grid.Color.YELLOW,
                34 => self.terminal.current_fg_color = grid.Color.BLUE,
                35 => self.terminal.current_fg_color = grid.Color.MAGENTA,
                36 => self.terminal.current_fg_color = grid.Color.CYAN,
                37 => self.terminal.current_fg_color = grid.Color.WHITE,
                // Bright foreground colors
                90 => self.terminal.current_fg_color = grid.Color.BRIGHT_BLACK,
                91 => self.terminal.current_fg_color = grid.Color.BRIGHT_RED,
                92 => self.terminal.current_fg_color = grid.Color.BRIGHT_GREEN,
                93 => self.terminal.current_fg_color = grid.Color.BRIGHT_YELLOW,
                94 => self.terminal.current_fg_color = grid.Color.BRIGHT_BLUE,
                95 => self.terminal.current_fg_color = grid.Color.BRIGHT_MAGENTA,
                96 => self.terminal.current_fg_color = grid.Color.BRIGHT_CYAN,
                97 => self.terminal.current_fg_color = grid.Color.BRIGHT_WHITE,
                // Background colors (40-47, 100-107)
                40 => self.terminal.current_bg_color = grid.Color.BLACK,
                41 => self.terminal.current_bg_color = grid.Color.RED,
                42 => self.terminal.current_bg_color = grid.Color.GREEN,
                43 => self.terminal.current_bg_color = grid.Color.YELLOW,
                44 => self.terminal.current_bg_color = grid.Color.BLUE,
                45 => self.terminal.current_bg_color = grid.Color.MAGENTA,
                46 => self.terminal.current_bg_color = grid.Color.CYAN,
                47 => self.terminal.current_bg_color = grid.Color.WHITE,
                // Bright background colors
                100 => self.terminal.current_bg_color = grid.Color.BRIGHT_BLACK,
                101 => self.terminal.current_bg_color = grid.Color.BRIGHT_RED,
                102 => self.terminal.current_bg_color = grid.Color.BRIGHT_GREEN,
                103 => self.terminal.current_bg_color = grid.Color.BRIGHT_YELLOW,
                104 => self.terminal.current_bg_color = grid.Color.BRIGHT_BLUE,
                105 => self.terminal.current_bg_color = grid.Color.BRIGHT_MAGENTA,
                106 => self.terminal.current_bg_color = grid.Color.BRIGHT_CYAN,
                107 => self.terminal.current_bg_color = grid.Color.BRIGHT_WHITE,
                else => {},
            }
        }
    }
};
