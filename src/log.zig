const std = @import("std");

pub const Level = enum {
    DEBUG,
    INFO,
    WARN,
    ERROR,
};

pub fn info(comptime module: []const u8, comptime fmt: []const u8, args: anytype) void {
    log(.INFO, module, fmt, args);
}

pub fn warn(comptime module: []const u8, comptime fmt: []const u8, args: anytype) void {
    log(.WARN, module, fmt, args);
}

pub fn err(comptime module: []const u8, comptime fmt: []const u8, args: anytype) void {
    log(.ERROR, module, fmt, args);
}

fn log(level: Level, comptime module: []const u8, comptime fmt: []const u8, args: anytype) void {
    const level_txt = switch (level) {
        .DEBUG => "DEBUG",
        .INFO => "INFO ",
        .WARN => "WARN ",
        .ERROR => "ERROR",
    };

    // Use std.debug.print which writes to stderr and is thread-safe enough for debug logging
    std.debug.print("[2026-01-20T21:39:40Z {s} {s}] ", .{level_txt, module});
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}
