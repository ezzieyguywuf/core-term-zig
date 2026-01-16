const std = @import("std");
const Scanner = @import("zig_wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Wayland Protocol Generation
    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_seat", 1);
    scanner.generate("xdg_wm_base", 1);

    const wayland_mod = b.createModule(.{
        .root_source_file = scanner.result,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "core-term",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    // We'll expose actor_scheduler as a module so it can be imported cleanly
    const actor_scheduler_mod = b.addModule("actor-scheduler", .{
        .root_source_file = b.path("src/actor_scheduler/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    exe.root_module.addImport("actor-scheduler", actor_scheduler_mod);
    exe.root_module.addImport("wayland", wayland_mod);
    exe.linkSystemLibrary("wayland-client");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe_unit_tests.root_module.addImport("actor-scheduler", actor_scheduler_mod);
    exe_unit_tests.root_module.addImport("wayland", wayland_mod);
    exe_unit_tests.linkSystemLibrary("wayland-client");
    exe_unit_tests.linkLibC();

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
