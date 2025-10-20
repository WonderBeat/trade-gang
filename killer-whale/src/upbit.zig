const std = @import("std");
const builtin = @import("builtin");

const json = @import("json.zig");
const messaging = @import("messaging.zig");
const wcurl = @import("curl.zig");
const metrics = @import("prometheus.zig");
const fastfilter = @import("fastfilter");
const simdjzon = @import("simdjzon");
const zeit = @import("zeit");
const binance = @import("binance.zig");
const time = @import("time.zig");

//for simdjzon
pub const read_buf_cap = 4096;

pub const std_options = std.Options{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .debug,
        .ReleaseFast => .info,
        .ReleaseSmall => .info,
    },
};

pub fn main() !void {
    var debug_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ @constCast(&std.heap.stackFallback(4096 * 3, std.heap.c_allocator)).get(), false },
        };
    };
    if (!is_debug) {
        try metrics.initializeMetrics(.{ .prefix = "upbit_" });
    }

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const intervalMs = try std.fmt.parseInt(u32, std.posix.getenv("INTERVAL") orelse "7000", 0);
    const webDomain = std.posix.getenv("DOMAIN") orelse "https://api-manager.upbit.com.";

    const send_announce_address = try resolve_address(std.posix.getenv("MOTHERSHIP") orelse {
        std.log.err("Mothership address required", .{});
        return;
    });

    var seed = seed: {
        var prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        break :seed std.Random.intRangeAtMost(prng.random(), usize, 0, 999999);
    };

    const httpClient = try wcurl.Curl.init(allocator);
    defer httpClient.deinit();
    if (std.posix.getenv("PROXY_LIST")) |url| {
        std.log.info("Proxy mode: {s}", .{url});
        httpClient.setProxyDownloadUrl(url);
        try httpClient.exchangeProxy();
    }

    const iterations = if (is_debug) 150 else (500 + seed % 500);
    var latestID: u32 = 0;
    var totalCount: u32 = 0;
    var urlBuf: [300]u8 = undefined;
    std.debug.print("Seed: {d} Iterations: {d}\n", .{ seed, iterations });
    var rateReducer: u32 = 1;
    for (0..iterations) |iter| {
        if (iter % 17 == 0) {
            std.log.info("{d} iterations", .{iter});
            const now = (try zeit.instant(.{}));
            if (!is_debug and !time.isTimeBetweenHours(&now, 2, 10) or time.isWeekend(&now)) {
                rateReducer = 5;
            } else {
                rateReducer = 1;
            }
        }
        seed += 1;
        const startIterationTs = std.time.milliTimestamp();
        const url = try buildUrlZ(seed, webDomain, totalCount, &urlBuf);
        const result = httpClient.get(url) catch |errz| {
            metrics.err();
            if (errz == wcurl.CurlError.OperationTimedout) {
                metrics.timeout();
            } else if (errz == wcurl.CurlError.SSLConnectError or errz == wcurl.CurlError.SSLCertProblem or errz == wcurl.CurlError.PeerFailedVerification) {
                metrics.sslError();
            } else {
                std.log.warn("Err {} for {s}", .{ errz, url });
            }
            std.log.debug("Call error {}, for proxy {s}", .{ errz, httpClient.proxyManager.getCurrentProxy() orelse "none" });
            try dropReplaceProxy(httpClient);
            try collectQueryMetrics(httpClient, seed % (10000 / intervalMs) == 0);
            _ = sleepRemaning(startIterationTs, intervalMs * rateReducer);
            continue;
        };

        if (result.status_code != 200) {
            if (result.status_code == 304) {
                std.log.debug("Not modified {d}: {s} ", .{ result.status_code, url });
                metrics.hit();
            } else if (result.status_code == 429) {
                metrics.err();
                metrics.rateLimited();
                try dropReplaceProxy(httpClient);
                if (httpClient.proxyManager.size() == 0) {
                    std.log.warn("Rate limited", .{});
                    std.Thread.sleep(std.time.ns_per_min * 10); // banned and has no other proxies
                }
            } else {
                std.log.warn("Call {d}: {s} ", .{ result.status_code, url });
                metrics.err();
                try dropReplaceProxy(httpClient);
            }

            try collectQueryMetrics(httpClient, seed % (10000 / intervalMs) == 0);
            _ = sleepRemaning(startIterationTs, intervalMs * rateReducer);
            continue;
        }
        const body = (result.body orelse return error.NoBody).items;
        std.debug.assert(body.len > 100);
        const id = extractLatestID(body) catch |errz| {
            std.log.err("Latest ID error for {s}: {}, {s}", .{ url, errz, body[0..@min(body.len, 200)] });
            metrics.err();
            try dropReplaceProxy(httpClient);
            try collectQueryMetrics(httpClient, seed % (10000 / intervalMs) == 0);
            _ = sleepRemaning(startIterationTs, intervalMs * rateReducer);
            continue;
        };
        std.debug.assert(id > 0);
        metrics.hit();
        if (latestID == 0) {
            const announce = try extractAnnounce(allocator, body);
            std.log.info("Preflight test", .{});
            std.log.info("Latest announce ID {d} title {s}, releaseDate {d}", .{
                announce.id,
                announce.title,
                announce.releaseDate,
            });
            const localhost = try resolve_address("127.0.0.1:8081");
            const bytesSent = try messaging.sendAnnounce(allocator, localhost, &announce);
            std.debug.assert(bytesSent > 0);
            std.log.info("Announce sent to localhost {d} bytes", .{bytesSent});
            latestID = id;
            totalCount = announce.total;
        } else if (id != latestID) {
            var announce = try extractAnnounce(allocator, body);
            announce.url = url;
            announce.total = id;
            _ = try messaging.sendAnnounce(allocator, send_announce_address, &announce);
            const currentTs = std.time.milliTimestamp();
            const announceTsMs = announce.releaseDate * 1000;
            const diff = currentTs - announceTsMs;
            const proxyLocation: ?[]const u8 = prxy: {
                if (httpClient.proxyManager.getCurrentProxy()) |proxy| {
                    break :prxy resolveIpLocation(allocator, proxy) catch null;
                } else {
                    break :prxy null;
                }
            };
            defer if (proxyLocation) |loc| allocator.free(loc);
            const proxy = httpClient.proxyManager.getCurrentProxy() orelse "";
            std.log.info("AS {d}, {d}, url {s}, proxy {s}({?s}),TS {d}({d})", .{
                id,
                diff,
                url[8..],
                proxy,
                proxyLocation,
                currentTs,
                announceTsMs,
            });
            latestID = id;
            totalCount = announce.total;
        }
        try collectQueryMetrics(httpClient, seed % (10000 / intervalMs) == 0);
        const etag = try result.curl_response.getHeader("etag") orelse return error.NoETag;
        try httpClient.initHeaders(.{ .etag = etag.get() });
        const execTime = sleepRemaning(startIterationTs, intervalMs * rateReducer);
        std.log.debug("Call {d} ({d}): {s} ", .{ result.status_code, execTime, url });
    }
}

fn collectQueryMetrics(httpClient: *wcurl.Curl, flush: bool) !void {
    if (httpClient.latest_query_metrics()) |cMetrics| {
        const execution_time_ms = cMetrics.total_time - cMetrics.pretransfer_time;
        metrics.latency(@intCast(execution_time_ms));
    }
    if (flush) {
        try metrics.dumpToFile();
    }
}

fn dropReplaceProxy(httpClient: *wcurl.Curl) !void {
    if (try httpClient.dropCurrentProxy() == 0) {
        try httpClient.exchangeProxy();
    }
}

fn sleepRemaning(startIterationTs: i64, intervalTimeMs: u32) i64 {
    const timeTaken = std.time.milliTimestamp() - startIterationTs;
    const sleepRemaningMs: u64 = @intCast(@max(1000, intervalTimeMs - timeTaken));
    std.Thread.sleep(std.time.ns_per_ms * sleepRemaningMs); // cooldown
    return timeTaken;
}

// json parsing basically
fn extractAnnounce(allocator: std.mem.Allocator, body: []const u8) !binance.Announce {
    var parser = try simdjzon.dom.Parser.initFixedBuffer(allocator, body, .{});
    defer parser.deinit();
    try parser.parse();
    var totalCountNode = try parser.element().at_pointer("/data/total_count");
    const totalCount = try totalCountNode.get_uint64();
    var dataSection = try parser.element().at_pointer("/data/notices");
    var first_element = (try dataSection.get_array()).at(0) orelse return error.NoFirstElement;
    var listedAtNode = first_element.at_key("listed_at") orelse return error.NoListedAt;
    const listedAt = try listedAtNode.get_string();
    const timestamp = (try zeit.instant(.{
        .source = .{
            .iso8601 = listedAt,
        },
    })).unixTimestamp();
    var categoryNode = first_element.at_key("category") orelse return error.NoCategory;
    const category = try categoryNode.get_string();
    var categoryNum: u16 = 888;
    if (std.mem.eql(u8, category, "Trade") or std.mem.eql(u8, category, "거래")) {
        categoryNum = 777;
    }
    var titleNode = first_element.at_key("title") orelse return error.NoTitle;
    const title = try titleNode.get_string();
    var idNode = first_element.at_key("id") orelse return error.NoID;
    const id = try idNode.get_int64();
    std.debug.assert(id > 0 and title.len > 0 and timestamp > 0);
    return binance.Announce{
        .allocator = allocator,
        .releaseDate = timestamp,
        .catalogId = categoryNum,
        .title = try allocator.dupe(u8, title),
        .id = @intCast(id),
        .total = @intCast(totalCount),
        .url = "",
    };
}

fn buildUrlZ(seed: usize, domain: [:0]const u8, totalCount: u32, buf: []u8) ![:0]u8 {
    //const category = std.posix.getenv("CATEGORY") orelse "trade";
    const os = switch ((seed ^ 0xfeed) % 2) {
        0 => "web",
        else => "android",
        //else => "ios",
    };
    const pageSize = (((seed / 10) ^ 0xdead * (seed / 10) ^ 0xbabe)) % 22 + 1; //  '/10' helps with etag
    const pad = switch ((seed ^ 0xbaba * seed ^ 0x101) % 4) {
        0 => "+",
        1 => "%20",
        2 => "+%20",
        else => "0",
    };
    const url = "{s}/api/v1/announcements?os={s}&page=1&per_page={s}{d}&category=all&total={d}&seed={d}";
    return try std.fmt.bufPrintZ(buf, url, .{ domain, os, pad, pageSize, totalCount, seed });
}

inline fn extractTotalCount(haystack: []const u8) !u32 {
    return extractInt(u32, haystack, needleTotalCount);
}

inline fn extractPages(haystack: []const u8) !u32 {
    return extractInt(u32, haystack, needleTotalCount);
}

inline fn extractLatestID(haystack: []const u8) !u32 {
    return extractInt(u32, haystack, needleID);
}

const needleTotalCount = "\"total_count\":";
const needlePages = "\"total_count\":";
const needleID = "\"id\":";

fn extractInt(T: type, haystack: []const u8, needle: []const u8) !u32 {
    const start_index = std.mem.indexOf(u8, haystack, needle) orelse return error.NeedleNotFound;
    const start = start_index + needle.len;
    var end: usize = start;
    while (end < haystack.len and std.ascii.isDigit(haystack[end])) {
        end += 1;
    }
    if (start == end) {
        return error.InvalidFormat;
    }
    return try std.fmt.parseInt(T, haystack[start..end], 0);
}

fn resolve_address(address_with_port: []const u8) !std.net.Address {
    var iterator = std.mem.tokenizeScalar(u8, address_with_port, ':');
    const address = iterator.next() orelse return error.AddressParseFailed;
    const port = try std.fmt.parseInt(u16, iterator.next() orelse return error.AddressParseFailed, 0);
    return try std.net.Address.parseIp(address, port);
}

// !!! creates local httpClient
// return memory managed by client
pub fn resolveIpLocation(allocator: std.mem.Allocator, proxyUrl: [:0]const u8) ![]const u8 {
    const httpClient = try wcurl.Curl.init(allocator);
    defer httpClient.deinit();
    const location = wcurl.resolveIpLocation(httpClient, proxyUrl) catch "unknown";
    return allocator.dupe(u8, location);
}

const expect = std.testing.expect;

test "parse total" {
    const jsonText =
        \\ {"success":true,"data":{"total_pages":238,"total_count":4743,"notices"
    ;
    try std.testing.expectEqual(4743, try extractTotalCount(jsonText));
}
test "parse date" {
    const iso = try zeit.instant(.{
        .source = .{
            .iso8601 = "2025-07-28T20:10:07+09:00",
        },
    });
    try expect(iso.unixTimestamp() > 10);
    try std.testing.expectEqual(2025, iso.time().year);
    try std.testing.expectEqual(zeit.Month.jul, iso.time().month);
    try std.testing.expectEqual(28, iso.time().day);
}

test "parse announce" {
    const body = @embedFile("upbit-announce.json");
    const alloc = std.testing.allocator;
    const announce = try extractAnnounce(alloc, body);
    defer announce.deinit();
    try std.testing.expectEqualStrings("업비트 코인빌리기 - 테더(USDT) 지원 종료 안내", announce.title);
    try std.testing.expectEqual(5373, announce.id);
    try std.testing.expectEqual(1753701007, announce.releaseDate);
}

test "buildUrlZ" {
    var buf: [300]u8 = undefined;
    const domain = "https://api-manager.upbit.com";

    // Test with seed 0
    const url1 = try buildUrlZ(0, domain, 100, &buf);
    try std.testing.expectEqualStrings("https://api-manager.upbit.com/api/v1/announcements?os=android&page=1&per_page=%201&category=all&total=100&seed=0", url1);

    // Test with seed 1
    const url2 = try buildUrlZ(1, domain, 200, &buf);
    try std.testing.expectEqualStrings("https://api-manager.upbit.com/api/v1/announcements?os=web&page=1&per_page=+%201&category=all&total=200&seed=1", url2);
}

test {
    std.testing.refAllDecls(@This());
}
