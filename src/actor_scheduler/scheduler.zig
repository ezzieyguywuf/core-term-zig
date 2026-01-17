const std = @import("std");
const primitive = @import("primitive.zig");
const BoundedQueue = primitive.BoundedQueue;

pub const SystemStatus = enum {
    Idle,
    Busy,
};

pub const ActorStatus = enum {
    Idle,
    Busy,
};

pub const HandlerError = error{
    Recoverable,
    Fatal,
};

pub const HandlerResult = HandlerError!void;

pub fn Message(comptime D: type, comptime C: type, comptime M: type) type {
    return union(enum) {
        Data: D,
        Control: C,
        Management: M,
        Shutdown,
    };
}

const System = enum {
    Wake,
    Shutdown,
};

// Backoff constants
const SPIN_ATTEMPTS: u32 = 100;
const YIELD_ATTEMPTS: u32 = 20;

pub fn ActorHandle(comptime D: type, comptime C: type, comptime M: type) type {
    return struct {
        const MsgType = Message(D, C, M);
        const Self = @This();

        tx_doorbell: *BoundedQueue(System),
        tx_data: *BoundedQueue(D),
        tx_control: *BoundedQueue(C),
        tx_mgmt: *BoundedQueue(M),

        // Cloning in Zig is manual for reference types if ownership is shared.
        // Here we just copy the pointers since the Queues are heap-allocated and ref-counted or owned by the Scheduler?
        // In this simple implementation, we assume the Scheduler owns the queues and they live as long as the Scheduler.
        // For a robust implementation, we might need shared_ptr style management or just assume Scheduler outlives Handles.
        // Rust uses Arc<SharedInternal>. Here we will rely on the Scheduler keeping them alive.
        // WARNING: If Scheduler dies, these pointers dangle. In a real app, use refcounting.

        pub fn send(self: Self, msg: MsgType) !void {
            switch (msg) {
                .Data => |d| {
                    // Blocking send for Data
                    try self.tx_data.send(d);
                    try self.wake();
                },
                .Control => |c| {
                    // Backoff retry for Control
                    try self.send_with_backoff(self.tx_control, c);
                    try self.wake();
                },
                .Management => |m| {
                    // Backoff retry for Management
                    try self.send_with_backoff(self.tx_mgmt, m);
                    try self.wake();
                },
                .Shutdown => {
                    try self.tx_doorbell.send(.Shutdown);
                },
            }
        }

        fn wake(self: Self) !void {
            // Non-blocking wake attempt
            _ = self.tx_doorbell.try_send(.Wake) catch |err| switch (err) {
                error.Full => {}, // Already woke
                else => return err,
            };
        }

        fn send_with_backoff(self: Self, queue: anytype, item: anytype) !void {
            _ = self;
            var attempt: u32 = 0;
            while (true) {
                queue.try_send(item) catch |err| switch (err) {
                    error.Full => {
                        if (attempt < SPIN_ATTEMPTS) {
                            // Spin
                        } else if (attempt < SPIN_ATTEMPTS + YIELD_ATTEMPTS) {
                            std.Thread.yield() catch {};
                        } else {
                            // Sleep fallback - just yield for now to avoid std version issues
                            std.Thread.yield() catch {};
                        }
                        attempt += 1;
                        continue;
                    },
                    else => return err,
                };
                return;
            }
        }
    };
}

pub fn ActorScheduler(comptime D: type, comptime C: type, comptime M: type) type {
    return struct {
        const Self = @This();
        const Handle = ActorHandle(D, C, M);
        const Msg = Message(D, C, M);

        allocator: std.mem.Allocator,

        // Queues
        q_doorbell: *BoundedQueue(System),
        q_data: *BoundedQueue(D),
        q_control: *BoundedQueue(C),
        q_mgmt: *BoundedQueue(M),

        // Config
        data_burst_limit: usize,
        mgmt_burst_limit: usize,
        ctrl_burst_limit: usize,

        pub fn init(allocator: std.mem.Allocator, data_burst: usize, data_buf_size: usize) !Self {
            const q_doorbell = try BoundedQueue(System).init(allocator, 1);
            const q_data = try BoundedQueue(D).init(allocator, data_buf_size);
            // Default buffers for control/mgmt
            const q_control = try BoundedQueue(C).init(allocator, 32);
            const q_mgmt = try BoundedQueue(M).init(allocator, 32);

            return Self{
                .allocator = allocator,
                .q_doorbell = q_doorbell,
                .q_data = q_data,
                .q_control = q_control,
                .q_mgmt = q_mgmt,
                .data_burst_limit = data_burst,
                .mgmt_burst_limit = 32,
                .ctrl_burst_limit = 320,
            };
        }

        pub fn deinit(self: *Self) void {
            self.q_doorbell.deinit();
            self.q_data.deinit();
            self.q_control.deinit();
            self.q_mgmt.deinit();
        }

        pub fn handle(self: *Self) Handle {
            return Handle{
                .tx_doorbell = self.q_doorbell,
                .tx_data = self.q_data,
                .tx_control = self.q_control,
                .tx_mgmt = self.q_mgmt,
            };
        }

        pub fn run(self: *Self, actor: anytype) !void {
            var working = false;

            while (true) {
                const signal = if (working)
                    self.q_doorbell.try_recv()
                else
                    self.q_doorbell.recv();

                const sys_msg = signal catch |err| switch (err) {
                    error.Empty => .Wake, // Fallthrough to work if we were polling
                    error.Closed => return, // Done
                    else => return err,
                };

                switch (sys_msg) {
                    .Shutdown => return,
                    .Wake => {
                        // Work loop
                        const status = try self.process_queues(actor);
                        if (status == .Busy) {
                            working = true;
                        } else {
                            working = false;
                        }
                    },
                }
            }
        }

        fn process_queues(self: *Self, actor: anytype) !SystemStatus {
            var more_work = false;

            // 1. Control (Half budget)
            if (try self.drain(self.q_control, actor, .handle_control, self.ctrl_burst_limit / 2)) {
                more_work = true;
            }

            // 2. Management
            if (try self.drain(self.q_mgmt, actor, .handle_management, self.mgmt_burst_limit)) {
                more_work = true;
            }

            // 3. Control (Remaining)
            if (try self.drain(self.q_control, actor, .handle_control, self.ctrl_burst_limit / 2)) {
                more_work = true;
            }

            // 4. Data
            if (try self.drain(self.q_data, actor, .handle_data, self.data_burst_limit)) {
                more_work = true;
            }

            const sys_status = if (more_work) SystemStatus.Busy else SystemStatus.Idle;

            // Park the actor (opportunity to yield/sleep/check OS events)
            const actor_status = try actor.park(sys_status);

            if (more_work or actor_status == .Busy) {
                return .Busy;
            }
            return .Idle;
        }

        fn drain(self: *Self, queue: anytype, actor: anytype, comptime func: anytype, limit: usize) !bool {
            _ = self;
            var count: usize = 0;
            while (count < limit) : (count += 1) {
                const msg = queue.try_recv() catch |err| switch (err) {
                    error.Empty => return false, // Drained
                    error.Closed => return false,
                    else => return err,
                };

                // Call the actor function by name
                switch (func) {
                    .handle_control => try actor.handle_control(msg),
                    .handle_management => try actor.handle_management(msg),
                    .handle_data => try actor.handle_data(msg),
                    else => unreachable,
                }
            }
            return true; // Hit limit, maybe more work
        }
    };
}

// Convenience function to create actor system
pub fn create_actor(
    allocator: std.mem.Allocator,
    comptime D: type,
    comptime C: type,
    comptime M: type,
    data_buffer_size: usize,
    data_burst_limit: usize,
) !struct { handle: ActorHandle(D, C, M), scheduler: ActorScheduler(D, C, M) } {
    var sched = try ActorScheduler(D, C, M).init(allocator, data_burst_limit, data_buffer_size);
    const h = sched.handle();
    return .{ .handle = h, .scheduler = sched };
}
