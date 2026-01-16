const std = @import("std");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Condition = Thread.Condition;

/// A thread-safe bounded queue that supports blocking send and receive.
/// Similar to Rust's mpsc::sync_channel.
pub fn BoundedQueue(comptime T: type) type {
    return struct {
        mutex: Mutex = .{},
        not_empty: Condition = .{},
        not_full: Condition = .{},
        items: []T,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,
        closed: bool = false,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !*Self {
            const self = try allocator.create(Self);
            const items = try allocator.alloc(T, capacity);
            self.* = .{
                .items = items,
                .allocator = allocator,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.close(); // Ensure waiting threads are woken
            self.allocator.free(self.items);
            self.allocator.destroy(self);
        }

        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.closed = true;
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }

        /// Send a message. Blocks if the queue is full.
        /// Returns error.Closed if the queue is closed.
        pub fn send(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count == self.items.len) {
                if (self.closed) return error.Closed;
                self.not_full.wait(&self.mutex);
            }

            if (self.closed) return error.Closed;

            self.items[self.tail] = item;
            self.tail = (self.tail + 1) % self.items.len;
            self.count += 1;
            self.not_empty.signal();
        }

        /// Try to send a message. Returns error.Full if full.
        pub fn try_send(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed) return error.Closed;
            if (self.count == self.items.len) return error.Full;

            self.items[self.tail] = item;
            self.tail = (self.tail + 1) % self.items.len;
            self.count += 1;
            self.not_empty.signal();
        }

        /// Receive a message. Blocks if the queue is empty.
        /// Returns error.Closed if the queue is closed and empty.
        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count == 0) {
                if (self.closed) return error.Closed;
                self.not_empty.wait(&self.mutex);
            }

            const item = self.items[self.head];
            self.head = (self.head + 1) % self.items.len;
            self.count -= 1;
            self.not_full.signal();
            return item;
        }

        /// Try to receive a message. Returns error.Empty if empty.
        pub fn try_recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) {
                if (self.closed) return error.Closed;
                return error.Empty;
            }

            const item = self.items[self.head];
            self.head = (self.head + 1) % self.items.len;
            self.count -= 1;
            self.not_full.signal();
            return item;
        }
    };
}
