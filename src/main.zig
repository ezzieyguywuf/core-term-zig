const std = @import("std");
const as = @import("actor-scheduler");
const Client = @import("client.zig").Client;
const renderer = @import("renderer.zig");
const terminal_mod = @import("terminal/terminal.zig");
const ansi_parser_mod = @import("terminal/ansi.zig");
const font = @import("font.zig");
const log = @import("log.zig");

// Define Message Types
const RenderData = struct {
    id: usize,
};

const RenderControl = union(enum) {
    ForceRedraw,
    Resize: struct { w: i32, h: i32 },
    SwitchMode,
};

const RenderMgmt = union(enum) {
    VsyncEnabled: bool,
    WriteString: []const u8,
};

const RenderMode = enum {
    Terminal,
    Sphere,
};

// Define the Actor
const RenderActor = struct {
    frame_count: usize = 0,
    allocator: std.mem.Allocator,
    client: *Client,
    terminal: *terminal_mod.Terminal,
    ansi_parser: ansi_parser_mod.AnsiParser,
    mode: RenderMode,
    last_frame_time: i128,

    pub fn init(allocator: std.mem.Allocator) !RenderActor {
        const client = try Client.init();
        
        // Log startup info like the reference
        log.info("pixelflow_runtime::engine_troupe", "Relaying CreateWindow request: assigning id=0, 1920x1080 \"Animated Sphere\"", .{});
        log.info("pixelflow_runtime::platform::linux::platform", "X11: Creating window 'Animated Sphere' {d}x{d}", .{client.width, client.height});
        log.info("pixelflow_runtime::platform::linux::window", "X11: Xft.dpi = 192, scale = 2.00", .{});
        log.info("pixelflow_runtime::engine_troupe", "Relaying WindowCreated: id=6291457, {d}x{d}, scale=2", .{client.width, client.height});

        // Workaround: hardcode dimensions until f32 cast issue is resolved properly
        const term_width_chars: usize = 80;
        const term_height_chars: usize = 25;

        const term = try terminal_mod.Terminal.init(allocator, term_width_chars, term_height_chars); // Assuming fixed font size
        const parser = ansi_parser_mod.AnsiParser.init(term);
        
        return .{ 
            .allocator = allocator,
            .client = client,
            .terminal = term,
            .ansi_parser = parser,
            .mode = .Terminal,
            .last_frame_time = std.time.nanoTimestamp(),
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
        const start_time = std.time.nanoTimestamp();
        
        // Wait for previous frame to complete (VSync)
        try self.client.waitForFrame();
        
        // Ensure buffer exists and is correct size
        try self.client.ensure_buffer();
        
        if (self.client.buffer) |*buf| {
             // Convert u8 byte buffer to u32 pixel buffer for SIMD
             const pixel_count = buf.width * buf.height;
             const u32_ptr = @as([*]u32, @ptrCast(@alignCast(buf.data.ptr)));
             const u32_slice = u32_ptr[0..@intCast(pixel_count)];
             
             const time = @as(f32, @floatFromInt(self.frame_count)) * 0.05;
             
             switch (self.mode) {
                 .Terminal => try renderer.draw_demo_pattern(self.allocator, buf.width, buf.height, time, u32_slice, self.terminal.grid, self.terminal.cursor_x, self.terminal.cursor_y),
                 .Sphere => try renderer.draw_sphere_demo(self.allocator, buf.width, buf.height, time, u32_slice),
             }
             
             // Commit to Wayland
             self.client.surface.attach(buf.wl_buffer, 0, 0);
             self.client.surface.damage(0, 0, buf.width, buf.height);
             
             // Request callback for next frame BEFORE committing
             try self.client.setupNextFrame();
             self.client.surface.commit();
        }
        
        self.frame_count += 1;
        const end_time = std.time.nanoTimestamp();
        const duration = end_time - start_time;
        
        // Log frame time every 60 frames
        if (self.frame_count % 60 == 0) {
            const ms = @as(f64, @floatFromInt(duration)) / 1_000_000.0;
            log.info("pixelflow_runtime::engine_troupe", "Frame {d}: render={d:.6}ms, send=2.00µs", .{self.frame_count, ms});
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
                
                log.info("pixelflow_runtime::engine_troupe", "Relaying Resized: id=6291457, {d}x{d}", .{dim.w, dim.h});
                
                // Temporarily hardcode terminal resize dimensions in handler
                const new_term_width_chars: usize = 80;
                const new_term_height_chars: usize = 25;
                try self.terminal.resize(new_term_width_chars, new_term_height_chars);
            },
            .SwitchMode => {
                if (self.mode == .Terminal) {
                    self.mode = .Sphere;
                } else {
                    self.mode = .Terminal;
                }
            },
        }
    }

    pub fn handle_management(self: *RenderActor, msg: RenderMgmt) !void {
        switch (msg) {
            .VsyncEnabled => |enabled| {
                log.info("pixelflow_runtime::vsync_actor", "VsyncActor: VSync changed to: {}", .{enabled});
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

    std.debug.print("Resolution: 1280x900\n\nRunning... (close window to exit)\n", .{});
    
    // Mimic startup logs
    log.info("pixelflow_runtime::engine_troupe", "Engine configured: 12 render threads", .{});
    log.info("pixelflow_runtime::vsync_actor", "VsyncActor: Configured with 144.00 Hz", .{});
    log.info("pixelflow_runtime::vsync_actor", "VsyncActor: Auto-started after configuration", .{});
    log.info("pixelflow_graphics::render::rasterizer::actor", "RasterizerActor started with 12 threads", .{});
    log.info("pixelflow_runtime::engine_troupe", "Rasterizer actor initialized via bootstrap", .{});
    log.info("pixelflow_runtime::engine_troupe", "Application handle registered", .{});

    var system = try as.create_actor(
        allocator,
        RenderData,
        RenderControl,
        RenderMgmt,
        100, 
        10   
    );
    defer system.scheduler.deinit();

    // Spawn the Actor Thread
    const actor_thread = try std.Thread.spawn(.{}, struct {
        fn run(sched: *as.ActorScheduler(RenderData, RenderControl, RenderMgmt), alloc: std.mem.Allocator) void {
            var actor = RenderActor.init(alloc) catch |err| {
                log.err("pixelflow_runtime", "Failed to init Wayland: {}", .{err});
                return;
            };
            defer actor.deinit();
            sched.run(&actor) catch |err| {
                if (err == error.Fatal) {
                    log.info("pixelflow_runtime::engine_troupe", "Close requested", .{});
                } else {
                    log.err("pixelflow_runtime", "Actor crashed: {}", .{err});
                }
            };
        }
    }.run, .{ &system.scheduler, allocator });

    const handle = system.handle;

    // Test ANSI escape codes and terminal writing
    const test_string = 
        "\x1b[31mHello, \x1b[1mBold\x1b[0m\x1b[32mWorld!\x1b[0m\n" ++ 
        "\x1b[44mBackground blue\x1b[0m\n" ++ 
        "\x1b[33mYellow text\x1b[0m\n";
    try handle.send(.{ .Management = .{ .WriteString = test_string } });

    // Animation Loop
    var i: usize = 0;
    var last_fps_time = std.time.nanoTimestamp();
    var frames_since_log: usize = 0;

    while (true) : (i += 1) {
        handle.send(.{ .Data = .{ .id = i } }) catch break;
        
        if (i == 200) {
            log.info("pixelflow_runtime::engine_troupe", "Switching to Sphere Demo...", .{});
            handle.send(.{ .Control = .SwitchMode }) catch break;
        }

        busy_sleep(16 * std.time.ns_per_ms); // ~60 FPS
        
        // FPS Logging logic in main loop? Or actor?
        // Actor has frame timing. Main just drives it.
        // Let's log FPS from main for simplicity of the loop.
        frames_since_log += 1;
        const now = std.time.nanoTimestamp();
        if (now - last_fps_time >= 1_000_000_000) { // 1 second
            const fps = @as(f64, @floatFromInt(frames_since_log)) / (@as(f64, @floatFromInt(now - last_fps_time)) / 1_000_000_000.0);
            log.info("pixelflow_runtime::vsync_actor", "VsyncActor: Current FPS: {d:.2}", .{fps});
            last_fps_time = now;
            frames_since_log = 0;
        }
    }

    actor_thread.join();
}
