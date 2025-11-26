const std = @import("std");
const zio = @import("zio");
const builtin = @import("builtin");
const StringTape = @import("string-tape.zig").StringTape;

pub const Pair = struct {
    id: usize,
    name: []const u8,
};

pub const StreamUpdate = struct {
    timestamp: u64,
    data: []const u8,
    pair: Pair,
};

pub fn generateSymbolsFromStrings(allocator: std.mem.Allocator, strings: []const []const u8) ![]Pair {
    var pairs = try allocator.alloc(Pair, strings.len);

    for (strings, 0..) |str, i| {
        pairs[i] = Pair{
            .id = @intCast(i),
            .name = str,
        };
    }

    return pairs;
}

pub fn RingBuffer(comptime internal_size: usize) type {
    return struct {
        elements: [internal_size][]const u8,
        head: usize,
        count: usize,

        pub fn init() @This() {
            return @This(){
                .elements = [_][]const u8{""} ** internal_size,
                .head = 0,
                .count = 0,
            };
        }

        pub fn push(self: *@This(), event: []const u8) void {
            self.elements[self.head] = event;
            self.head = (self.head + 1) % internal_size;

            if (self.count < internal_size) {
                self.count += 1;
            }
        }

        pub fn getEvents(self: *const @This(), allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
            var result = std.ArrayList([]const u8){};
            try result.ensureTotalCapacity(allocator, self.count);

            const start_idx = if (self.count == internal_size)
                self.head // If buffer is full, oldest element is at head
            else
                (self.head + internal_size - self.count) % internal_size;

            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                const idx = (start_idx + i) % internal_size;
                try result.append(allocator, self.elements[idx]);
            }

            return result;
        }

        pub fn len(self: *const @This()) usize {
            return self.count;
        }
    };
}

pub fn RecentEventsStringStorage(comptime events_per_bucket: usize, comptime num_buckets: usize, comptime max_record_len: usize) type {
    return struct {
        buffers: [num_buckets]RingBuffer(events_per_bucket),
        tape_buffer: []u8 = undefined,
        tape: StringTape = undefined,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            var obj = @This(){
                .buffers = undefined, //[_]RingBuffer(events_per_bucket){RingBuffer(events_per_bucket).init()} ** num_buckets,
                .tape_buffer = undefined,
                .tape = undefined,
            };
            obj.tape_buffer = try allocator.alloc(u8, num_buckets * events_per_bucket * max_record_len);
            obj.tape = StringTape.init(obj.tape_buffer);
            return obj;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.tape_buffer);
        }

        pub fn processEvent(self: *@This(), bucket: usize, event: []const u8) !void {
            std.debug.assert(event.len < max_record_len);
            const stored_event = try self.tape.write(event);
            if (bucket < num_buckets) {
                self.buffers[bucket].push(stored_event);
            } else {
                return error.BucketOutOfRange;
            }
        }

        pub fn getEventsForBucket(self: *@This(), allocator: std.mem.Allocator, bucket: usize) !?std.ArrayList([]const u8) {
            if (bucket < num_buckets) {
                return try self.buffers[bucket].getEvents(allocator);
            }
            return null;
        }

        pub fn getEventCountForBucket(self: *@This(), bucket: usize) usize {
            if (bucket < num_buckets) {
                return self.buffers[bucket].len();
            }
            return 0;
        }
    };
}

test "RingBuffer basic functionality" {
    var buffer = RingBuffer(10).init();

    try std.testing.expectEqual(@as(usize, 0), buffer.len());

    buffer.push("event1");
    try std.testing.expectEqual(@as(usize, 1), buffer.len());

    buffer.push("event2");
    buffer.push("event3");
    buffer.push("event4");
    try std.testing.expectEqual(@as(usize, 4), buffer.len());

    var events = try buffer.getEvents(std.testing.allocator);
    defer events.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("event1", events.items[0]);
    try std.testing.expectEqualStrings("event2", events.items[1]);
    try std.testing.expectEqualStrings("event3", events.items[2]);
}

test "RingBuffer overflow behavior" {
    var buffer = RingBuffer(3).init(); // Small capacity for testing

    buffer.push("event1");
    buffer.push("event2");
    buffer.push("event3");

    try std.testing.expectEqual(@as(usize, 3), buffer.len());

    // Verify order is correct
    var events_before_overflow = try buffer.getEvents(std.testing.allocator);
    defer events_before_overflow.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("event1", events_before_overflow.items[0]);
    try std.testing.expectEqualStrings("event2", events_before_overflow.items[1]);
    try std.testing.expectEqualStrings("event3", events_before_overflow.items[2]);

    // Add one more event, which should push out the oldest
    buffer.push("event4");

    var events_after_overflow = try buffer.getEvents(std.testing.allocator);
    defer events_after_overflow.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), events_after_overflow.items.len);

    // The oldest event ("event1") should be gone, and the newest should be present
    try std.testing.expectEqualStrings("event2", events_after_overflow.items[0]); // The oldest remaining event
    try std.testing.expectEqualStrings("event4", events_after_overflow.items[2]); // The newest event
}

test "Storage with multiple buckets" {
    var storage = try RecentEventsStringStorage(1024, 5, 100).init(std.testing.allocator);
    defer storage.deinit(std.testing.allocator);

    try storage.processEvent(0, "event1_for_BNBUSDT");
    try storage.processEvent(1, "event1_for_BTCUSDT");
    try storage.processEvent(0, "event2_for_BNBUSDT");

    // Verify BNBUSDT events (bucket 0)
    const bnbusdt_events_opt = try storage.getEventsForBucket(std.testing.allocator, 0);
    var bnbusdt_events = bnbusdt_events_opt.?;
    try std.testing.expectEqual(@as(usize, 2), bnbusdt_events.items.len);
    try std.testing.expectEqualStrings("event1_for_BNBUSDT", bnbusdt_events.items[0]);
    try std.testing.expectEqualStrings("event2_for_BNBUSDT", bnbusdt_events.items[1]);
    bnbusdt_events.deinit(std.testing.allocator);

    // Verify BTCUSDT events (bucket 1)
    const btcusdt_events_opt = try storage.getEventsForBucket(std.testing.allocator, 1);
    var btcusdt_events = btcusdt_events_opt.?;
    try std.testing.expectEqual(@as(usize, 1), btcusdt_events.items.len);
    try std.testing.expectEqualStrings("event1_for_BTCUSDT", btcusdt_events.items[0]);
    btcusdt_events.deinit(std.testing.allocator);

    // Check event counts
    try std.testing.expectEqual(@as(usize, 2), storage.getEventCountForBucket(0));
    try std.testing.expectEqual(@as(usize, 1), storage.getEventCountForBucket(1));
    try std.testing.expectEqual(@as(usize, 0), storage.getEventCountForBucket(2)); // Non-existent pair
}

test "generatePairsFromStrings creates pairs from string array" {
    const strings = [_][]const u8{ "BTCUSDT", "ETHUSDT", "BNBUSDT" };
    const pairs = try generateSymbolsFromStrings(std.testing.allocator, &strings);
    defer std.testing.allocator.free(pairs);

    try std.testing.expectEqual(@as(usize, 3), pairs.len);
    try std.testing.expectEqual(@as(usize, 0), pairs[0].id);
    try std.testing.expectEqualStrings("BTCUSDT", pairs[0].name);
    try std.testing.expectEqual(@as(usize, 1), pairs[1].id);
    try std.testing.expectEqualStrings("ETHUSDT", pairs[1].name);
    try std.testing.expectEqual(@as(usize, 2), pairs[2].id);
    try std.testing.expectEqualStrings("BNBUSDT", pairs[2].name);
}
