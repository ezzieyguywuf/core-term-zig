const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;

pub const Buffer = struct {
    wl_buffer: *wl.Buffer,
    data: []u8,
    width: i32,
    height: i32,
    stride: i32,
    size: usize,
};

pub fn createShmBuffer(shm: *wl.Shm, width: i32, height: i32) !Buffer {
    const stride = width * 4;
    const size: usize = @intCast(stride * height);

    const fd = try std.posix.memfd_create("zig-wayland-shm", 0);
    const file = std.fs.File{ .handle = fd };
    try file.setEndPos(size);

    const data = try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    const pool = try shm.createPool(fd, @intCast(size));
    defer pool.destroy();

    const buffer = try pool.createBuffer(
        0,
        width,
        height,
        stride,
        wl.Shm.Format.xrgb8888,
    );

    return Buffer{
        .wl_buffer = buffer,
        .data = data,
        .width = width,
        .height = height,
        .stride = stride,
        .size = size,
    };
}
