const std = @import("std");
const builtin = @import("builtin");

const ws = @import("websocket");
const websockets = @import("websockets.zig");
const metrics = @import("prometheus.zig");
const binance = @import("binance.zig");
const array_tools = @import("array.zig");
const tape = @import("string-tape.zig");
const zio = @import("zio");
const storage = @import("storage.zig");
const server = @import("web-server.zig");

const URI = "fstream.binance.com";
const IS_TLS = true;
const PORT = 443;
const EVENTS_PER_BUCKET = 100;
const NUM_BUCKETS = 400;
const MAX_RECORD_LENGTH = 200;
const WS_RECV_TIMEOUT = 3000;
const STREAM_UPDATE_BUFFER_SIZE: usize = 100;

//
// const uri = "ws.postman-echo.com";
// const uri = "127.0.0.1";
// const port = 8765;
// const tls = false;

pub const std_options = std.Options{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .debug,
        .ReleaseFast => .info,
        .ReleaseSmall => .info,
    },
};

const aggTradeMarker =
    \\"e":"aggTrade"
;

fn signalHandler(rt: *zio.Runtime, shutdown: *std.atomic.Value(bool)) !void {
    // Create signal handler for SIGINT (Ctrl+C)
    var sig = try zio.Signal.init(.interrupt);
    defer sig.deinit();
    try sig.wait(rt);
    std.log.info("Received signal, initiating shutdown...", .{});
    shutdown.store(true, .release);
}

pub const AppEventStorage = storage.RecentEventsStringStorage(
    EVENTS_PER_BUCKET,
    NUM_BUCKETS,
    MAX_RECORD_LENGTH,
);

fn storageRoutine(
    rt: *zio.Runtime,
    update_channel: *zio.Channel(storage.StreamUpdate),
    store: *AppEventStorage,
) !void {
    var timeout = zio.Timeout.init;
    std.log.debug("Storage routine started", .{});
    var updates_count: usize = 0;
    while (true) {
        timeout.set(rt, 10 * std.time.ns_per_s);
        const update = update_channel.receive(rt) catch |err| {
            std.log.err("Store channel error {}", .{err});
            return err;
        };
        timeout.clear(rt);
        store.processEvent(update.pair.id, update.data) catch |err| {
            std.log.err("Store event error {}", .{err});
            return err;
        };
        if (builtin.mode == .Debug) {
            updates_count += 1;
            if (updates_count % 500 == 0) {
                std.log.debug("Updates processed: {}", .{updates_count});
            }
        }
    }
}

fn websocketStreamCollector(
    rt: *zio.Runtime,
    pairs: []const storage.Pair,
    update_channel: *zio.Channel(storage.StreamUpdate),
    shutdown: *std.atomic.Value(bool),
) !void {
    var pair_map = std.StringHashMap(storage.Pair).init(rt.allocator);
    defer pair_map.deinit();

    for (pairs) |pair| {
        try pair_map.put(pair.name, pair);
    }

    const stream_path = try binance.buildCombinedStreamUrlParams(rt.allocator, pairs, .{});
    defer rt.allocator.free(stream_path);

    var client = try websockets.asyncClient(rt, .{
        .port = PORT,
        .host = URI,
        .tls = IS_TLS,
        .buffer_size = 9000,
    });
    defer {
        client.close(.{ .code = 4002 }) catch unreachable;
        client.deinit();
        std.log.warn("Collector stopped", .{});
    }
    std.log.info("WebSocket client initialized. Connecting to {s}:{d}...", .{ URI, PORT });
    try client.handshake(stream_path, .{
        .timeout_ms = 3000,
        .headers = std.fmt.comptimePrint("Host: {s}\r\nOrigin: {s}", .{ URI, URI }),
    });

    try client.readTimeout(WS_RECV_TIMEOUT);
    try client.writeTimeout(100);
    var msg = try client.read();
    var last_ping = std.time.milliTimestamp();
    const tape_buffer = try rt.allocator.alloc(u8, STREAM_UPDATE_BUFFER_SIZE * MAX_RECORD_LENGTH);
    defer rt.allocator.free(tape_buffer);
    var tape_ring_buf = tape.StringTape.init(tape_buffer);
    var updates_count: usize = 0;
    while (msg) |message| {
        defer client.done(message);
        if (builtin.mode == .Debug and shutdown.load(.acquire)) {
            std.log.debug("Shutdown signal received. Exiting", .{});
            break;
        }
        switch (message.type) {
            .text => {
                //std.log.info("Received update: {s}", .{message.data});
                std.debug.assert(std.mem.containsAtLeast(u8, message.data, 1, aggTradeMarker));
                const pair_name = try binance.extractSymbolFromAggTrade(message.data);
                const found_pair = pair_map.get(pair_name);
                if (found_pair) |pair| {
                    const timestamp = try binance.extractTimestampFromAggTrade(message.data);
                    const update = storage.StreamUpdate{
                        .timestamp = timestamp,
                        .pair = pair,
                        .data = try tape_ring_buf.write(message.data),
                    };
                    try update_channel.send(rt, update);
                    if (builtin.mode == .Debug) {
                        updates_count += 1;
                        if (updates_count % 1000 == 0) {
                            std.log.info("WS consumed {d} updates, exiting", .{updates_count});
                            try rt.sleep(500); // so consumer can process events queue
                            return;
                        }
                    }
                } else {
                    std.log.debug("Received update for pair {s} which is not in our tracking list", .{pair_name});
                }
            },
            .ping => {
                std.log.debug("Received ping message", .{});
                const now = std.time.milliTimestamp();
                if (last_ping + 60 * std.time.ms_per_s < now) {
                    std.log.debug("Sending PONG", .{});
                    try client.writePong(message.data);
                    last_ping = now;
                }
            },
            .pong => std.log.info("Received pong message", .{}),
            else => std.log.err("Received unsupported message type {}", .{message}),
        }
        msg = try client.read();
    } else {
        std.log.err("No message received", .{});
    }
}

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{
        .never_unmap = true,
        .retain_metadata = true,
        .verbose_log = false,
        .backing_allocator_zeroes = false,
    }){};
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            //.ReleaseFast, .ReleaseSmall => .{ @constCast(&std.heap.stackFallback(4096 * 3, std.heap.c_allocator)).get(), false },
            //.ReleaseFast, .ReleaseSmall => .{ std.heap.c_allocator, false },
            .ReleaseFast, .ReleaseSmall => .{ debug_allocator.allocator(), false },
        };
    };
    if (!is_debug) {
        try metrics.initializeMetrics(.{ .prefix = "binance_tradecache_" });
    }
    var runtime = try zio.Runtime.init(allocator, .{ .num_executors = 1, .thread_pool = .{ .max_threads = 1 } });
    defer runtime.deinit();
    var buffer: [STREAM_UPDATE_BUFFER_SIZE]storage.StreamUpdate = undefined;
    var update_channel = zio.Channel(storage.StreamUpdate).init(&buffer);

    var crossing_pair_names = try binance.findPairsForTradeTracking(allocator);
    defer {
        for (crossing_pair_names.items) |pair| {
            allocator.free(pair);
        }
        crossing_pair_names.deinit(allocator);
    }
    const crossing_pairs = try storage.generatePairsFromStrings(allocator, crossing_pair_names.items);
    for (crossing_pairs) |pair| {
        std.log.info("Crossing pair: {s}", .{pair.name});
    }
    defer allocator.free(crossing_pairs);

    var shutdown = std.atomic.Value(bool).init(false);
    // var signal_task = try runtime.spawn(signalHandler, .{ runtime, &shutdown }, .{ .stack_size = 64 * 1024 });
    // defer signal_task.cancel(runtime);

    var store = try AppEventStorage.init(allocator);
    defer store.deinit(allocator);
    var storage_task = try runtime.spawn(storageRoutine, .{ runtime, &update_channel, &store }, .{});
    defer storage_task.cancel(runtime);

    const partitioned_pairs = try array_tools.partitionArray(storage.Pair, crossing_pairs, 3, allocator);
    defer allocator.free(partitioned_pairs);

    const TaskHandle = @TypeOf(try runtime.spawn(websocketStreamCollector, .{ runtime, &.{}, &update_channel, &shutdown }, .{}));
    const tasks: []TaskHandle = try allocator.alloc(TaskHandle, partitioned_pairs.len);
    for (partitioned_pairs, 0..) |batch, index| {
        std.log.info("Starting WebSocket collector for {d} pairs", .{batch.len});
        const task = try runtime.spawn(websocketStreamCollector, .{ runtime, batch, &update_channel, &shutdown }, .{});
        tasks[index] = task;
    }
    defer {
        for (tasks) |*task| {
            task.cancel(runtime);
        }
        allocator.free(tasks);
    }

    var server_task = try runtime.spawn(
        server.runServer,
        .{ runtime, &store, crossing_pairs },
        .{},
    );
    defer server_task.cancel(runtime);

    std.log.info("All WebSocket collectors started", .{});
    try runtime.run();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test {
    std.testing.refAllDecls(@This());
}
