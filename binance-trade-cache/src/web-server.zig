const std = @import("std");
const zio = @import("zio");
const http = @import("dusty");
const main = @import("main.zig");
const storage = @import("storage.zig");
const binance = @import("binance.zig");

const AppContext = struct {
    rt: *zio.Runtime,
    store: *main.AppEventStorage,
    streams: []const storage.Pair,
};

const MAX_REQUEST_HEADER_SIZE = 16 * 1024;

fn handleClient(rt: *zio.Runtime, stream: zio.net.Stream, ctx: *AppContext) !void {
    defer stream.close(rt);

    defer stream.shutdown(rt, .both) catch |err| {
        std.log.debug("Failed to shutdown client connection: {}", .{err});
    };

    std.log.info("HTTP client connected from {f}", .{stream.socket.address});

    var read_buffer: [MAX_REQUEST_HEADER_SIZE]u8 = undefined;
    var reader = stream.reader(rt, &read_buffer);

    var write_buffer: [4096]u8 = undefined;
    var writer = stream.writer(rt, &write_buffer);

    var server = std.http.Server.init(&reader.interface, &writer.interface);

    var request = server.receiveHead() catch |err| {
        std.log.debug("Failed to receive request: {}", .{err});
        return err;
    };
    const pair_name = extractPairName(request.head.target) orelse {
        var body_writer = try request.respondStreaming(&read_buffer, .{});
        for (ctx.streams) |pair| {
            try writeBody(&body_writer.writer, ctx, pair.name);
        }
        try body_writer.end();
        return;
    };

    std.log.info("{s} {s} (pair: {s})", .{ @tagName(request.head.method), request.head.target, pair_name });

    var body_writer = try request.respondStreaming(&read_buffer, .{});
    try writeBody(&body_writer.writer, ctx, pair_name);
    try body_writer.end();
}

fn extractPairName(target: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, target, "/stream/")) {
        return null;
    }
    var path_parts = std.mem.splitSequence(u8, target, "/");
    _ = path_parts.next(); // Skip empty string
    _ = path_parts.next(); // Skip "stream"
    const pair_name = path_parts.next() orelse return null;
    return pair_name;
}

pub fn runServer(rt: *zio.Runtime, store: *main.AppEventStorage, streams: []const storage.Pair) !void {
    var ctx = AppContext{ .rt = rt, .store = store, .streams = streams };
    const env = std.posix.getenv("PORT") orelse "8281";
    const host = std.posix.getenv("HOST") orelse "127.0.0.1";
    const port: u16 = try std.fmt.parseInt(u16, env, 0);
    const addr = try zio.net.IpAddress.parseIp4(host, port);
    std.log.info("Listening on {s}:{d}", .{ host, port });
    const server = try addr.listen(rt, .{});
    defer server.close(rt);
    while (true) {
        const stream = try server.accept(rt);
        errdefer stream.close(rt);
        var task = try rt.spawn(handleClient, .{ rt, stream, &ctx }, .{});
        task.detach(rt);
    }
}

fn writeBody(writer: *std.Io.Writer, ctx: *AppContext, stream: []const u8) !void {
    for (ctx.streams) |pair| {
        if (std.mem.eql(u8, pair.name, stream)) {
            var events = try ctx.store.getEventsForBucket(ctx.rt.allocator, pair.id);
            if (events) |*existing_events| {
                defer existing_events.deinit(ctx.rt.allocator);
                _ = try writer.write("[\n");
                for (existing_events.items, 0..) |element, index| {
                    _ = try writer.write(element);
                    if (index < existing_events.items.len - 1) {
                        _ = try writer.write(",");
                    }
                }
                _ = try writer.write("\n]");
            } else {
                _ = try writer.write("No events for this stream");
            }
            return;
        }
    }
    _ = try writer.write("stream not found");
}
