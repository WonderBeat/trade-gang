const std = @import("std");
const expect = std.testing.expect;
const http = std.http;

pub fn extract_timestamp(body: []const u8) ?i128 {
    const needle = "releaseDate\":";
    const index = std.mem.indexOf(u8, body, needle) orelse return null;
    const start_ts = index + needle.len;
    var i: usize = 0;
    while (std.ascii.isDigit(body[start_ts + i])) {
        i += 1;
    }
    const end_ts = start_ts + i;
    return std.fmt.parseInt(i128, body[start_ts..end_ts], 0) catch blk: {
        break :blk 0;
    };
}

pub fn repeatZ(allocator: std.mem.Allocator, pattern: []const u8, count: usize) ![:0]const u8 {
    const result_len = pattern.len * count;
    var result = try allocator.allocSentinel(u8, result_len, 0);
    for (0..count) |i| {
        std.mem.copyForwards(u8, result[i * pattern.len .. (i + 1) * pattern.len], pattern);
    }
    return result;
}

pub fn isCacheHit(header: *const http.Header) bool {
    if (std.mem.eql(u8, header.name, "CF-Cache-Status") and !std.mem.eql(u8, header.value, "MISS") and !std.mem.eql(u8, header.value, "DYNAMIC")) {
        std.log.debug("", .{});
        .warn("Cache hit! Cloudflare: {s}", .{header.value});
        return true;
    }
    if (std.mem.eql(u8, header.name, "X-Cache") and !std.mem.eql(u8, header.value, "Miss from cloudfront")) {
        std.log.warn("Cache hit! CloudFront: {s}", .{header.value});
        return true;
    }
    return false;
}

pub fn performTimingTests(allocator: std.mem.Allocator) !void {
    const warmup = "https://www.binance.me/en/support/announcement";
    const url_for_templating = "https://www.binance.me/en/support/announcement/list/{s}";

    // const warmup = "https://www.binance.info/bapi/apex/v1/public/apex/cms/article/list/query";
    // const url_for_templating = "https://www.binance.info/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo={s}&pageSize=2&catalogId=161";
    const page = "93";
    const baselineURL = std.fmt.comptimePrint(url_for_templating, .{page});
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    var buffer: [18096]u8 = undefined;

    for (1..300) |iteration| {
        const hack = try repeatZ(allocator, "0", iteration);
        defer allocator.free(hack);
        const hexed = try std.mem.concat(allocator, u8, &[_][]const u8{ hack, page });
        defer allocator.free(hexed);
        const headers = [_]http.Header{
            http.Header{ .name = "Origin", .value = hexed }, //
            //                http.Header{ .name = "Host", .value = "www.binance.info" },
        };
        const binanceURLHexed = try std.fmt.allocPrint(
            allocator,
            url_for_templating,
            .{hexed},
        );

        defer allocator.free(binanceURLHexed);
        // warmup
        _ = try timedRequest(&client, &buffer, &headers, warmup, false);
        std.time.sleep(std.time.ns_per_s);
        //baseline
        var diff = @divTrunc(try timedRequest(&client, &buffer, &headers, baselineURL, true), 1000000);
        std.debug.print("{d}, baseline, {d}, {s}\n", .{ iteration, diff, baselineURL });
        std.time.sleep(std.time.ns_per_s);
        //test
        diff = @divTrunc(try timedRequest(&client, &buffer, &headers, binanceURLHexed, true), 1000000);
        std.debug.print("{d}, test, {d}, {s}\n", .{ iteration, diff, binanceURLHexed });
        std.time.sleep(std.time.ns_per_s);
    }
}

pub const NetworkError = error{ QueryFailed, CacheHit };
pub const ApplicationError = error{TextNotFound};

pub fn timedRequest(client: *http.Client, buffer: []u8, headers: []const http.Header, url: []const u8, fail_on_err: bool) !i128 {
    var req = try client.open(.HEAD, try std.Uri.parse(url), .{
        .server_header_buffer = buffer, //
        .extra_headers = headers,
        .redirect_behavior = .not_allowed,
    });
    defer req.deinit();
    const start = std.time.nanoTimestamp();
    try req.send();
    try req.wait();
    const end = std.time.nanoTimestamp();
    var headerIterator = req.response.iterateHeaders();
    if (fail_on_err) {
        while (headerIterator.next()) |header| {
            if (isCacheHit(&header)) {
                return NetworkError.CacheHit;
            }
        }
        if (req.response.status != .ok) {
            std.log.err("HTTP request failed with status code: {?s} for URL: {s}", .{ req.response.status.phrase(), url });
            return NetworkError.CacheHit;
        }
    }
    return end - start;
}

test "test repeat pattern" {
    const alloc = std.testing.allocator;
    const pattern = try repeatZ(alloc, "abc", 2);
    defer alloc.free(pattern);
    try expect(std.mem.eql(u8, pattern, "abcabc"));
}

test "extract timestamp" {
    const text = "\"type\":1,\"releaseDate\":1742200205404},";
    const result = extract_timestamp(text);
    try expect(result == 1742200205404);
}
