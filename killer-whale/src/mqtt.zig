const mqttz = @import("mqttz");
const std = @import("std");

pub const Mqtt = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    client: mqttz.posix.Client,

    pub fn init(allocator: std.mem.Allocator, host: []const u8) !*Self {
        var client = try mqttz.posix.Client.init(.{
            .port = 1883,
            .host = host,
            // It IS possible to use the posix client without an allocator, see readme
            .allocator = allocator,
        });

        errdefer client.deinit();
        const client_id = std.posix.getenv("HOSTNAME") orelse "unknown";

        _ = try client.connect(.{ .timeout = 200 }, .{ .user_properties = &.{
            .{ .key = "client", .value = client_id },
        }, .username = "binance", .password = "security_is_not_an_0ption" });

        if (try client.readPacket(.{})) |packet| switch (packet) {
            .disconnect => |_| {
                client.deinit();
                return error.Closed;
            },
            else => {
                //   std.log.debug("Mqtt: {any}", .{packet});
            },
        };
        const self = try allocator.create(Self);
        self.* = .{ .allocator = allocator, .client = client };
        return self;
    }

    pub fn subscribe(self: *Self, topic: []const u8) !u16 {
        const packet_identifier = try self.client.subscribe(.{}, .{ .topics = &.{
            .{ .filter = topic, .qos = .at_most_once },
        } });
        if (try self.client.readPacket(.{ .timeout = 250 })) |packet| switch (packet) {
            .disconnect => |_| {
                return error.Closed;
            },
            .suback => |s| {
                std.debug.assert(s.packet_identifier == packet_identifier);
            },
            else => {
                unreachable;
            },
        };
        return packet_identifier;
    }

    pub fn send(self: *Self, topic: []const u8, text: []const u8) !?u16 {
        return try self.client.publish(.{ .timeout = 200, .retries = 2 }, .{ .topic = topic, .message = text, .content_type = "text", .message_expiry_interval = 15 });
    }

    pub fn ping(self: *Self) !void {
        try self.client.ping(.{ .timeout = 50 });
        const packet = try self.client.readPacket(.{ .timeout = 333 }) orelse {
            std.log.debug("No ping response", .{});
            return;
        };
        switch (packet) {
            .pong => |_| {
                std.log.debug("Received PONG", .{});
            },
            else => {
                std.log.debug("PING unexpected packet: {any}", .{packet});
            },
        }
    }

    pub fn receive_string(self: *Self, timeout_ms: i32) !?[]const u8 {
        const packet = try self.client.readPacket(.{ .timeout = timeout_ms }) orelse {
            return null;
        };
        switch (packet) {
            .publish => |*publish| {
                std.log.debug("Received {s}:{s}", .{ publish.topic, publish.message });
                return try self.allocator.dupe(u8, publish.message);
            },
            else => {
                std.log.debug("unexpected packet: {any}", .{packet});
            },
        }
        return null;
    }

    pub fn deinit(self: *Self) void {
        self.client.disconnect(.{ .timeout = 100 }, .{ .reason = .normal }) catch {};
        self.client.deinit();
        self.allocator.destroy(self);
    }
};
