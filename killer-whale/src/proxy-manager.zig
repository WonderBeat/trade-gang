const std = @import("std");
const curl = @import("curl");
const ArrayList = std.ArrayList;

pub const ProxyManager = struct {
    proxies: ArrayList([:0]const u8),
    current_index: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ProxyManager {
        return ProxyManager{
            .proxies = try ArrayList([:0]const u8).initCapacity(allocator, 10),
            .current_index = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProxyManager) void {
        for (self.proxies.items) |proxy| {
            self.allocator.free(proxy);
        }
        self.proxies.deinit(self.allocator);
    }

    pub fn isEmpty(self: *const ProxyManager) bool {
        return self.proxies.items.len == 0;
    }

    pub fn clear(self: *ProxyManager) void {
        for (self.proxies.items) |proxy| {
            self.allocator.free(proxy);
        }
        self.proxies.clearAndFree(self.allocator);
    }

    pub fn loadFromFile(self: *ProxyManager, file_path: []const u8) !usize {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var buffer: [2048]u8 = undefined;
        var reader = file.reader(&buffer);
        return try self.loadFromReader(&reader.interface);
    }

    pub fn loadFromUrl(self: *ProxyManager, url: [:0]const u8) !usize {
        const ca_bundle = try curl.allocCABundle(self.allocator);
        defer ca_bundle.deinit();
        const easy = try curl.Easy.init(.{
            .ca_bundle = ca_bundle,
            .default_timeout_ms = 2000,
        });
        defer easy.deinit();
        var buffer: [2048]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        const response = easy.fetch(url, .{ .writer = &writer }) catch |errz| {
            std.log.err("Failed to get proxy list from url: {s}", .{url});
            return errz;
        };
        std.debug.assert(response.status_code >= 200 and response.status_code < 400);
        var stream = std.Io.Reader.fixed(writer.buffered());
        return try self.loadFromReader(&stream);
    }

    pub fn loadFromReader(self: *ProxyManager, reader: *std.Io.Reader) !usize {
        while (true) {
            const line = reader.takeDelimiterExclusive('\n') catch {
                return self.proxies.items.len;
            };
            if (line.len < 2) continue; // skip empty lines
            const zeroTermitaned = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{line}, 0);
            try self.proxies.append(self.allocator, zeroTermitaned);
        }
        return self.proxies.items.len;
    }

    pub fn size(self: *const ProxyManager) usize {
        return self.proxies.items.len;
    }

    pub fn getNextProxy(self: *ProxyManager) ?[:0]const u8 {
        if (self.proxies.items.len == 0) return null;
        self.current_index = (self.current_index + 1) % self.proxies.items.len;
        return self.proxies.items[self.current_index];
    }

    pub fn getCurrentProxy(self: *const ProxyManager) ?[:0]const u8 {
        if (self.proxies.items.len == 0) return null;
        return self.proxies.items[self.current_index];
    }

    pub fn dropCurrent(self: *ProxyManager) void {
        if (self.proxies.items.len == 0) return;
        self.allocator.free(self.proxies.swapRemove(self.current_index));
        if (self.proxies.items.len == 0) {
            self.current_index = 0;
        } else {
            self.current_index = self.current_index % self.proxies.items.len;
        }
    }
};

const testing = std.testing;

test "ProxyManager init and deinit" {
    var pm = try ProxyManager.init(testing.allocator);
    defer pm.deinit();
    try testing.expectEqual(@as(usize, 0), pm.proxies.items.len);
    try testing.expectEqual(@as(usize, 0), pm.current_index);
}

test "ProxyManager isEmpty" {
    var pm = try ProxyManager.init(testing.allocator);
    defer pm.deinit();

    try testing.expect(pm.isEmpty());

    const proxy = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    try pm.proxies.append(testing.allocator, proxy);

    try testing.expect(!pm.isEmpty());
}

test "ProxyManager clear" {
    var pm = try ProxyManager.init(testing.allocator);
    defer pm.deinit();

    // Add some proxies
    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    try pm.proxies.append(testing.allocator, proxy1);
    try pm.proxies.append(testing.allocator, proxy2);

    try testing.expectEqual(@as(usize, 2), pm.proxies.items.len);

    pm.clear();

    try testing.expectEqual(@as(usize, 0), pm.proxies.items.len);
    try testing.expect(pm.isEmpty());
}

test "ProxyManager size" {
    var pm = try ProxyManager.init(testing.allocator);
    defer pm.deinit();

    try testing.expectEqual(@as(usize, 0), pm.size());

    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    try pm.proxies.append(testing.allocator, proxy1);
    try pm.proxies.append(testing.allocator, proxy2);

    try testing.expectEqual(@as(usize, 2), pm.size());
}

test "ProxyManager getNextProxy" {
    var pm = try ProxyManager.init(testing.allocator);
    defer pm.deinit();

    try testing.expect(pm.getNextProxy() == null);

    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    try pm.proxies.append(testing.allocator, proxy1);
    try pm.proxies.append(testing.allocator, proxy2);

    try testing.expectEqualStrings("http://localhost:8081", pm.getNextProxy().?);
    try testing.expectEqualStrings("http://localhost:8080", pm.getNextProxy().?);
    try testing.expectEqualStrings("http://localhost:8081", pm.getNextProxy().?);
}

test "ProxyManager getCurrentProxy" {
    var pm = try ProxyManager.init(testing.allocator);
    defer pm.deinit();

    try testing.expect(pm.getCurrentProxy() == null);

    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    try pm.proxies.append(testing.allocator, proxy1);
    try pm.proxies.append(testing.allocator, proxy2);

    _ = pm.getNextProxy().?; // Advance to proxy2
    try testing.expectEqualStrings("http://localhost:8081", pm.getCurrentProxy().?);
}

test "ProxyManager dropCurrent" {
    var pm = try ProxyManager.init(testing.allocator);
    defer pm.deinit();

    // Should not crash on empty list
    pm.dropCurrent();

    const proxy1 = try testing.allocator.dupeZ(u8, "http://localhost:8080");
    const proxy2 = try testing.allocator.dupeZ(u8, "http://localhost:8081");
    const proxy3 = try testing.allocator.dupeZ(u8, "http://localhost:8082");
    try pm.proxies.append(testing.allocator, proxy1);
    try pm.proxies.append(testing.allocator, proxy2);
    try pm.proxies.append(testing.allocator, proxy3);

    _ = pm.getNextProxy().?; // Advance to proxy2
    try testing.expectEqualStrings("http://localhost:8081", pm.getCurrentProxy().?);

    pm.dropCurrent(); // Drop proxy2

    try testing.expectEqual(@as(usize, 2), pm.size());
    try testing.expectEqualStrings("http://localhost:8082", pm.getCurrentProxy().?);
}

test "ProxyManager loadFromFile" {
    var pm = try ProxyManager.init(testing.allocator);
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
