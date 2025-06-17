const std = @import("std");
const curl = @import("curl");
const ArrayList = std.ArrayList;

pub const ProxyManager = struct {
    proxies: ArrayList([:0]const u8),
    current_index: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ProxyManager {
        return ProxyManager{
            .proxies = ArrayList([:0]const u8).init(allocator),
            .current_index = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProxyManager) void {
        for (self.proxies.items) |proxy| {
            self.allocator.free(proxy);
        }
        self.proxies.deinit();
    }

    pub fn isEmpty(self: *ProxyManager) bool {
        return self.proxies.items.len == 0;
    }

    pub fn clear(self: *ProxyManager) void {
        for (self.proxies.items) |proxy| {
            self.allocator.free(proxy);
        }
        self.proxies.clearAndFree();
    }

    pub fn loadFromFile(self: *ProxyManager, file_path: []const u8) !usize {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        const reader = buf_reader.reader();
        return try self.loadFromReader(&reader);
    }

    pub fn loadFromUrl(self: *ProxyManager, url: [:0]const u8) !usize {
        const ca_bundle = try curl.allocCABundle(self.allocator);
        defer ca_bundle.deinit();
        const easy = try curl.Easy.init(self.allocator, .{
            .ca_bundle = ca_bundle,
            .default_timeout_ms = 2000,
        });
        defer easy.deinit();
        const response = easy.get(url) catch |errz| {
            std.log.err("Failed to get proxy list from url: {s}", .{url});
            return errz;
        };
        defer response.deinit();
        const body_buffer = response.body orelse return error.NoBody;
        var stream = std.io.fixedBufferStream(body_buffer.items);
        return try self.loadFromReader(&stream.reader());
    }

    pub fn loadFromReader(self: *ProxyManager, reader: anytype) !usize {
        var buffer: [100]u8 = undefined;
        while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
            if (line.len == 0) continue;
            const zeroTermitaned = try std.fmt.allocPrintZ(self.allocator, "{s}", .{line});
            try self.proxies.append(zeroTermitaned);
        }
        return self.proxies.items.len;
    }

    pub fn size(self: *ProxyManager) usize {
        return self.proxies.items.len;
    }

    pub fn getNextProxy(self: *ProxyManager) ?[:0]const u8 {
        if (self.proxies.items.len == 0) return null;
        self.current_index = (self.current_index + 1) % self.proxies.items.len;
        return self.proxies.items[self.current_index];
    }

    pub fn getCurrentProxy(self: *ProxyManager) ?[:0]const u8 {
        if (self.proxies.items.len == 0) return null;
        return self.proxies.items[self.current_index];
    }

    pub fn dropCurrent(self: *ProxyManager) void {
        if (self.proxies.items.len == 0) return;
        self.allocator.free(self.proxies.swapRemove(self.current_index));
        self.current_index = self.current_index % self.proxies.items.len;
    }
};

const testing = std.testing;

test "ProxyManager init and deinit" {
    var pm = ProxyManager.init(testing.allocator);
    defer pm.deinit();
    try testing.expectEqual(@as(usize, 0), pm.proxies.items.len);
    try testing.expectEqual(@as(usize, 0), pm.current_index);
}

test "ProxyManager isEmpty" {
    var pm = ProxyManager.init(testing.allocator);
    defer pm.deinit();

    try testing.expect(pm.isEmpty());

    const proxy = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    try pm.proxies.append(proxy);

    try testing.expect(!pm.isEmpty());
}

test "ProxyManager clear" {
    var pm = ProxyManager.init(testing.allocator);
    defer pm.deinit();

    // Add some proxies
    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    try pm.proxies.append(proxy1);
    try pm.proxies.append(proxy2);

    try testing.expectEqual(@as(usize, 2), pm.proxies.items.len);

    pm.clear();

    try testing.expectEqual(@as(usize, 0), pm.proxies.items.len);
    try testing.expect(pm.isEmpty());
}

test "ProxyManager size" {
    var pm = ProxyManager.init(testing.allocator);
    defer pm.deinit();

    try testing.expectEqual(@as(usize, 0), pm.size());

    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    try pm.proxies.append(proxy1);
    try pm.proxies.append(proxy2);

    try testing.expectEqual(@as(usize, 2), pm.size());
}

test "ProxyManager getNextProxy" {
    var pm = ProxyManager.init(testing.allocator);
    defer pm.deinit();

    try testing.expect(pm.getNextProxy() == null);

    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    try pm.proxies.append(proxy1);
    try pm.proxies.append(proxy2);

    try testing.expectEqualStrings("http://localhost:8081", pm.getNextProxy().?);
    try testing.expectEqualStrings("http://localhost:8080", pm.getNextProxy().?);
    try testing.expectEqualStrings("http://localhost:8081", pm.getNextProxy().?);
}

test "ProxyManager getCurrentProxy" {
    var pm = ProxyManager.init(testing.allocator);
    defer pm.deinit();

    try testing.expect(pm.getCurrentProxy() == null);

    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    try pm.proxies.append(proxy1);
    try pm.proxies.append(proxy2);

    _ = pm.getNextProxy().?; // Advance to proxy2
    try testing.expectEqualStrings("http://localhost:8081", pm.getCurrentProxy().?);
}

test "ProxyManager dropCurrent" {
    var pm = ProxyManager.init(testing.allocator);
    defer pm.deinit();

    // Should not crash on empty list
    pm.dropCurrent();

    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    const proxy3 = try testing.allocator.dupeZ(u8, "http://localhost:8082");
    try pm.proxies.append(proxy1);
    try pm.proxies.append(proxy2);
    try pm.proxies.append(proxy3);

    _ = pm.getNextProxy().?; // Advance to proxy2
    try testing.expectEqualStrings("http://localhost:8081", pm.getCurrentProxy().?);

    pm.dropCurrent(); // Drop proxy2

    try testing.expectEqual(@as(usize, 2), pm.size());
    try testing.expectEqualStrings("http://localhost:8082", pm.getCurrentProxy().?);
}

test "ProxyManager loadFromFile" {
    var pm = ProxyManager.init(testing.allocator);
    defer pm.deinit();

    // Create a temporary test file
    const test_file_path = "test_proxies.txt";
    const test_content =
        \\http://localhost:8080
        \\http://localhost:8081
        \\
        \\http://localhost:8082
    ;

    const file = try std.fs.cwd().createFile(test_file_path, .{});
    defer std.fs.cwd().deleteFile(test_file_path) catch {}; // Clean up

    try file.writeAll(test_content);
    file.close();

    // Test loadFromFile
    _ = try pm.loadFromFile(test_file_path);

    try testing.expectEqual(@as(usize, 3), pm.size());
    try testing.expectEqualStrings("http://localhost:8080", pm.proxies.items[0]);
    try testing.expectEqualStrings("http://localhost:8081", pm.proxies.items[1]);
    try testing.expectEqualStrings("http://localhost:8082", pm.proxies.items[2]);
}
