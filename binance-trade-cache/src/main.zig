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
const bind = @import("fn-binding.zig");

const URI = "fstream.binance.com";
const IS_TLS = true;
const PORT = 443;
const EVENTS_PER_BUCKET = 100;
const NUM_BUCKETS = 400;
const MAX_RECORD_LENGTH = 200;
const WS_RECV_TIMEOUT = 2000;
const STREAM_UPDATE_BUFFER_SIZE: usize = 300;

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

const AGG_TRADE =
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
            metrics.processed();
            if (updates_count % 47700 == 0) {
                const now = std.time.milliTimestamp();
                const latency = now - update.timestamp;
                metrics.latency(latency);
                std.log.debug("Storage Updates processed: {}", .{updates_count});
            }
        }
    }
}

fn retryingWebsocketStreamCollector(
    rt: *zio.Runtime,
    pairs: []const storage.Pair,
    update_channel: *zio.Channel(storage.StreamUpdate),
    shutdown: *std.atomic.Value(bool),
    worker_index: usize,
) !void {
    const tape_buffer = try rt.allocator.alloc(u8, STREAM_UPDATE_BUFFER_SIZE * MAX_RECORD_LENGTH);
    defer rt.allocator.free(tape_buffer);
    while (true) {
        websocketStreamCollector(
            rt,
            pairs,
            update_channel,
            shutdown,
            worker_index,
            tape_buffer,
        ) catch |err| {
            if (err == zio.Cancelable.Canceled) {
                std.log.info("Task cancelled", .{});
            } else {
                std.log.info("Unexpected err {}", .{err});
                return err;
            }
        };
        std.log.warn("Collector {d} stopped. Restarting...", .{worker_index});
        metrics.restarts();
        try rt.sleep(2000);
    }
}

fn websocketStreamCollector(
    rt: *zio.Runtime,
    pairs: []const storage.Pair,
    update_channel: *zio.Channel(storage.StreamUpdate),
    shutdown: *std.atomic.Value(bool),
    worker_index: usize,
    tape_buffer: []u8,
) !void {
    var pair_map = std.StringHashMap(storage.Pair).init(rt.allocator);
    defer pair_map.deinit();

    for (pairs) |pair| {
        try pair_map.put(pair.name, pair);
    }

    const stream_path = try binance.buildCombinedStreamUrlParams(rt.allocator, pairs, .{
        .stream_type = "@trade",
    });
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
    }
    try client.handshake(stream_path, .{
        .timeout_ms = 5000,
        .headers = std.fmt.comptimePrint("Host: {s}\r\nOrigin: {s}", .{ URI, URI }),
    });

    if (std.posix.getenv("RCV_TIMEOUT")) |timeout| {
        const timeout_ms = try std.fmt.parseInt(u32, timeout, 10);
        std.log.info("Using custom net timeout {d}", .{timeout_ms});
        try client.readTimeout(timeout_ms);
    } else {
        try client.readTimeout(WS_RECV_TIMEOUT);
    }
    std.log.info("WebSocket client initialized {d}. Connecting to {s}:{d}...", .{ worker_index, URI, PORT });
    try client.writeTimeout(100);
    var msg = try client.read();
    var last_ping = std.time.milliTimestamp();
    var string_tape = tape.StringTape.init(tape_buffer);
    var updates_count: usize = 0;
    while (msg) |message| {
        {
            defer client.done(message);
            if (builtin.mode == .Debug and shutdown.load(.acquire)) {
                std.log.debug("Shutdown signal received. Exiting", .{});
                break;
            }
            switch (message.type) {
                .text => {
                    const data_section = try binance.extractDataSectionFromJson(message.data);
                    std.debug.assert(std.mem.startsWith(u8, data_section, "{\"e\":\"trade\""));

                    const symbol = try binance.extractSymbol(data_section);
                    const pair = pair_map.get(symbol) orelse return error.SymbolNotFound;
                    const timestamp = try binance.extractTimestampFromAggTrade(data_section);

                    const update = storage.StreamUpdate{
                        .timestamp = timestamp,
                        .pair = pair,
                        .data = try string_tape.write(data_section),
                    };
                    try update_channel.send(rt, update);
                    updates_count += 1;
                },
                .ping => {
                    std.log.debug("Received ping message", .{});
                    const now = std.time.milliTimestamp();
                    if (last_ping + 30 * std.time.ms_per_s < now) {
                        std.log.info("{d} Updates processed {d}", .{ worker_index, updates_count });
                        std.log.debug("Sending PONG", .{});
                        try client.writePong(message.data);
                        last_ping = now;
                    }
                },
                .pong => std.log.info("Received pong message", .{}),
                .close => {
                    const now = std.time.milliTimestamp();
                    const latency = now - last_ping;
                    std.log.err("{d} Received close message. Last ping was at {d}, {d} seconds ago", .{ worker_index, last_ping, @divFloor(latency, 1000) });
                    return;
                },
                else => std.log.err("{d} Received unsupported message type {} [{s}]", .{ worker_index, message, message.data }),
            }
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
        .backing_allocator_zeroes = true,
    }){};
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.c_allocator, false },
        };
    };
    if (!is_debug) {
        try metrics.initializeMetrics(.{ .prefix = "binance_tradecache_" });
    }

    var buffer: [STREAM_UPDATE_BUFFER_SIZE]storage.StreamUpdate = undefined;
    var update_channel = zio.Channel(storage.StreamUpdate).init(&buffer);

    var trading_symbols_strings = try binance.findSymbolsForTradeTracking(allocator);
    defer {
        for (trading_symbols_strings.items) |pair| {
            allocator.free(pair);
        }
        trading_symbols_strings.deinit(allocator);
    }
    const trading_symbols = try storage.generateSymbolsFromStrings(allocator, trading_symbols_strings.items);
    for (trading_symbols) |pair| {
        std.debug.print("{s},", .{pair.name});
    }
    std.debug.print("\n", .{});
    defer allocator.free(trading_symbols);

    var shutdown = std.atomic.Value(bool).init(false);
    // var signal_task = try runtime.spawn(signalHandler, .{ runtime, &shutdown }, .{ .stack_size = 64 * 1024 });
    // defer signal_task.cancel(runtime);

    var store = try AppEventStorage.init(allocator);
    std.debug.assert(NUM_BUCKETS > trading_symbols.len);
    defer store.deinit(allocator);

    var runtime = try zio.Runtime.init(allocator, .{
        .num_executors = 1,
        .thread_pool = .{ .max_threads = 1 },
    });
    defer runtime.deinit();
    var storage_task = try runtime.spawn(storageRoutine, .{ runtime, &update_channel, &store }, .{});
    defer storage_task.cancel(runtime);

    const partitions_count = try std.fmt.parseInt(u32, std.posix.getenv("SOCKETS_COUNT") orelse "3", 0);
    const partitioned_symbols = try array_tools.partitionArray(storage.Pair, trading_symbols, partitions_count, allocator);
    defer allocator.free(partitioned_symbols);

    const TaskHandle = @TypeOf(try runtime.spawn(retryingWebsocketStreamCollector, .{ runtime, &.{}, &update_channel, &shutdown, 0 }, .{}));
    const tasks: []TaskHandle = try allocator.alloc(TaskHandle, partitioned_symbols.len);
    for (partitioned_symbols, 0..) |batch, index| {
        std.log.info("Starting {d} WebSocket collector for {d} pairs", .{ index, batch.len });
        const task = try runtime.spawn(retryingWebsocketStreamCollector, .{ runtime, batch, &update_channel, &shutdown, index }, .{});
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
        .{ runtime, &store, trading_symbols },
        .{},
    );
    defer server_task.cancel(runtime);
    std.log.info("Activating runtime", .{});
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
