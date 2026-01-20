const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const shm = @import("shm.zig");

const c = @cImport({
    @cInclude("linux/input-event-codes.h");
});

pub const Client = struct {
    display: *wl.Display,
    registry: *wl.Registry,
    compositor: *wl.Compositor,
    shm: *wl.Shm,
    wm_base: *xdg.WmBase,
    seat: ?*wl.Seat,
    pointer: ?*wl.Pointer,

    surface: *wl.Surface,
    xdg_surface: *xdg.Surface,
            xdg_toplevel: *xdg.Toplevel,
            
            configured: bool = false,
            width: i32 = 1280,
            height: i32 = 900,
            running: bool = true,        
        // Frame synchronization
        frame_callback: ?*wl.Callback = null,
        waiting_for_frame: bool = false,
    
        buffer: ?shm.Buffer = null,
        
        // Input state
        pointer_x: f64 = 0,
        pointer_y: f64 = 0,
    
        pub fn init() !*Client {
            const display = try wl.Display.connect(null);
            const registry = try display.getRegistry();
            
            const client = try std.heap.c_allocator.create(Client);
            client.* = .{
                .display = display,
                .registry = registry,
                .compositor = undefined,
                .shm = undefined,
                .wm_base = undefined,
                .seat = undefined,
                .pointer = null,
                .surface = undefined,
                .xdg_surface = undefined,
                .xdg_toplevel = undefined,
                .frame_callback = null,
                .waiting_for_frame = false,
            };
    
            registry.setListener(*Client, registryListener, client);        if (display.roundtrip() != .SUCCESS) return error.RoundTripFailed;

        const surface = try client.compositor.createSurface();
        const xdg_surface = try client.wm_base.getXdgSurface(surface);
        const xdg_toplevel = try xdg_surface.getToplevel();

        client.surface = surface;
        client.xdg_surface = xdg_surface;
        client.xdg_toplevel = xdg_toplevel;

        xdg_surface.setListener(*Client, xdgSurfaceListener, client);
        xdg_toplevel.setListener(*Client, xdgToplevelListener, client);
        xdg_toplevel.setTitle("CoreTerm Zig");

        client.wm_base.setListener(*Client, xdgWmBaseListener, client);

        if (client.seat) |seat| {
            seat.setListener(*Client, seatListener, client);
        }

        client.surface.commit();
        if (display.roundtrip() != .SUCCESS) return error.RoundTripFailed;

        return client;
    }

    pub fn dispatch(self: *Client) !void {
        if (self.display.dispatchPending() != .SUCCESS) return error.DispatchFailed;
    }
    
    pub fn waitForFrame(self: *Client) !void {
        while (self.waiting_for_frame and self.running) {
            if (self.display.dispatch() != .SUCCESS) return error.DispatchFailed;
        }
    }
    
    pub fn setupNextFrame(self: *Client) !void {
        if (self.frame_callback) |cb| {
            cb.destroy();
        }
        self.frame_callback = try self.surface.frame();
        self.frame_callback.?.setListener(*Client, frameListener, self);
        self.waiting_for_frame = true;
    }
    
    fn frameListener(_: *wl.Callback, event: wl.Callback.Event, client: *Client) void {
        switch (event) {
            .done => {},
        }
        if (client.frame_callback) |cb| {
            cb.destroy();
            client.frame_callback = null;
        }
        client.waiting_for_frame = false;
    }

    pub fn ensure_buffer(self: *Client) !void {
        if (!self.configured) return;

        // Reallocate buffer if needed
        if (self.buffer == null or self.buffer.?.width != self.width or self.buffer.?.height != self.height) {
            if (self.buffer) |b| {
                // std.posix.munmap(b.data); // Clean up old mapping
                // b.wl_buffer.destroy();
                _ = b;
            }
            self.buffer = try shm.createShmBuffer(self.shm, self.width, self.height);
        }
    }

    fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, client: *Client) void {
        switch (event) {
            .global => |global| {
                if (std.mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                    client.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
                } else if (std.mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                    client.shm = registry.bind(global.name, wl.Shm, 1) catch return;
                } else if (std.mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                    client.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
                } else if (std.mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                    client.seat = registry.bind(global.name, wl.Seat, 1) catch return;
                }
            },
            .global_remove => {},
        }
    }

    fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, client: *Client) void {
        switch (event) {
            .capabilities => |data| {
                if (data.capabilities.pointer and client.pointer == null) {
                    client.pointer = seat.getPointer() catch return;
                    client.pointer.?.setListener(*Client, pointerListener, client);
                }
            },
        }
    }

    fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, client: *Client) void {
        switch (event) {
            .enter => |evt| {
                client.pointer_x = evt.surface_x.toDouble();
                client.pointer_y = evt.surface_y.toDouble();
            },
            .motion => |evt| {
                client.pointer_x = evt.surface_x.toDouble();
                client.pointer_y = evt.surface_y.toDouble();
            },
            .button => |evt| {
                if (evt.button == c.BTN_LEFT and evt.state == .pressed) {
                    // Title bar logic (30px height)
                    if (client.pointer_y < 30) {
                        // Close button logic (top-right 30px)
                        const width_f = @as(f64, @floatFromInt(client.width));
                        if (client.pointer_x > width_f - 30) {
                            client.running = false; // Initiate close
                        } else {
                            // Drag move
                            if (client.seat) |seat| {
                                client.xdg_toplevel.move(seat, evt.serial);
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, client: *Client) void {
        switch (event) {
            .configure => |configure| {
                xdg_surface.ackConfigure(configure.serial);
                client.configured = true;
                client.surface.commit();
            },
        }
    }

    fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, client: *Client) void {
        switch (event) {
            .configure => |configure| {
                if (configure.width > 0 and configure.height > 0) {
                    client.width = configure.width;
                    client.height = configure.height;
                }
            },
            .close => client.running = false,
        }
    }

    fn xdgWmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, _: *Client) void {
        switch (event) {
            .ping => |ping| wm_base.pong(ping.serial),
        }
    }
};
