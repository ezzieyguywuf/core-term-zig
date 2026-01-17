const std = @import("std");
const as = @import("actor-scheduler");
const Client = @import("client.zig").Client;
const renderer = @import("renderer.zig");
const terminal_mod = @import("terminal/terminal.zig");
const ansi_parser_mod = @import("terminal/ansi.zig");

// Define Message Types
const RenderData = struct {
    id: usize,
};

const RenderControl = union(enum) {
    ForceRedraw,
    Resize: struct { w: i32, h: i32 },
};

const RenderMgmt = union(enum) {
    VsyncEnabled: bool,
    WriteString: []const u8,
};

// Define the Actor
const RenderActor = struct {
    frame_count: usize = 0,
    allocator: std.mem.Allocator,
    client: *Client,
    terminal: *terminal_mod.Terminal,
    ansi_parser: ansi_parser_mod.AnsiParser,

    pub fn init(allocator: std.mem.Allocator) !RenderActor {
        const client = try Client.init();

        const term_width_chars: usize = 80;

        const term_height_chars: usize = 25;

        const term = try terminal_mod.Terminal.init(allocator, term_width_chars, term_height_chars); // Assuming fixed font size

        const parser = ansi_parser_mod.AnsiParser.init(term);

        return .{
            .allocator = allocator,

            .client = client,

            .terminal = term,

            .ansi_parser = parser,
        };
    }
    pub fn deinit(self: *RenderActor) void {
        self.terminal.deinit();
        // client deinit? Client is allocated by c_allocator.
        // We should deinit client here too if it was allocated by our allocator.
        // For now, client is leaked. In proper app, it would be freed.
    }

    pub fn handle_data(self: *RenderActor, msg: RenderData) !void {
        _ = msg;
        self.frame_count += 1;

        // Ensure buffer exists and is correct size
        try self.client.ensure_buffer();

        if (self.client.buffer) |*buf| {
            // Convert u8 byte buffer to u32 pixel buffer for SIMD
            // Safe because we created it with xrgb8888 (4 bytes per pixel)
            const pixel_count = buf.width * buf.height;
            const u32_ptr = @as([*]u32, @ptrCast(@alignCast(buf.data.ptr)));
            const u32_slice = u32_ptr[0..@intCast(pixel_count)];

            const time = @as(f32, @floatFromInt(self.frame_count)) * 0.05;
            renderer.draw_demo_pattern(buf.width, buf.height, time, u32_slice, self.terminal.grid);

            // Commit to Wayland
            self.client.surface.attach(buf.wl_buffer, 0, 0);
            self.client.surface.damage(0, 0, buf.width, buf.height);
            self.client.surface.commit();
        }
    }

    pub fn handle_control(self: *RenderActor, msg: RenderControl) !void {
        switch (msg) {
            .ForceRedraw => {
                // Trigger redraw logic if needed
            },
            .Resize => |dim| {
                // Resize the client's window internally
                self.client.width = dim.w;
                self.client.height = dim.h;
                // Resize the terminal grid based on character dimensions
                const char_width_f32: f32 = renderer.CHAR_WIDTH;
                const char_height_f32: f32 = renderer.CHAR_HEIGHT;
                try self.terminal.resize(@as(usize, @as(f32, dim.w) / char_width_f32), @as(usize, @as(f32, dim.h) / char_height_f32));
            },
        }
    }

    pub fn handle_management(self: *RenderActor, msg: RenderMgmt) !void {
        switch (msg) {
            .VsyncEnabled => |enabled| {
                std.debug.print("\n[GPU] VSync changed to: {}\n", .{enabled});
            },
            .WriteString => |str| {
                for (str) |byte| {
                    self.ansi_parser.parse(byte);
                }
            },
        }
    }

    pub fn park(self: *RenderActor, status: as.SystemStatus) !as.ActorStatus {
        _ = status;
        try self.client.dispatch();

        if (!self.client.running) return error.Fatal;

        busy_sleep(1 * std.time.ns_per_ms);

        return .Idle;
    }
};

fn busy_sleep(ns: i128) void {
    const start = std.time.nanoTimestamp();
    while (std.time.nanoTimestamp() - start < ns) {}
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Initializing Zig CoreTerm...\n", .{});

    var system = try as.create_actor(allocator, RenderData, RenderControl, RenderMgmt, 100, 10);
    defer system.scheduler.deinit();

    // Spawn the Actor Thread
    const actor_thread = try std.Thread.spawn(.{}, struct {
        fn run(sched: *as.ActorScheduler(RenderData, RenderControl, RenderMgmt), alloc: std.mem.Allocator) void {
            var actor = RenderActor.init(alloc) catch |err| {
                std.debug.print("Failed to init Wayland: {}\n", .{err});
                return;
            };
            defer actor.deinit();
            sched.run(&actor) catch |err| {
                std.debug.print("Actor crashed: {}\n", .{err});
            };
        }
    }.run, .{ &system.scheduler, allocator });

    const handle = system.handle;

    std.debug.print("Window should be open. Animating...\n", .{});

    // Animation Loop
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try handle.send(.{ .Data = .{ .id = i } });
        busy_sleep(16 * std.time.ns_per_ms); // ~60 FPS

        // Simple check if we should stop?
        // We can't easily check if the actor died here without atomic flag.
    }

    // Test ANSI escape codes and terminal writing
    const test_string =
        "\x1b[31mHello, \x1b[1mBold\x1b[0m\x1b[32mWorld!\x1b[0m\n" ++
        "\x1b[44mBackground blue\x1b[0m\n" ++
        "\x1b[33mYellow text\x1b[0m\n";
    try handle.send(.{ .Management = .{ .WriteString = test_string } });

    std.debug.print("\nSending Shutdown...\n", .{});
    try handle.send(.Shutdown);

    actor_thread.join();
}
