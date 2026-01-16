pub const packages = struct {
    pub const @"../zig-wayland" = struct {
        pub const build_root = "/home/wolfgangsanyer/Program/core-term-zig/../zig-wayland";
        pub const build_zig = @import("../zig-wayland");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "zig_wayland", "../zig-wayland" },
};
