const std = @import("std");
const expect = std.testing.expect;
const http = std.http;
const ArenaAllocator = std.heap.ArenaAllocator;
const builtin = @import("builtin");

const curl = @import("curl");

const files = @import("file/files.zig");
const messaging = @import("messaging.zig");
const wcurl = @import("curl.zig");

pub fn Parsed(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

const WatermarkedResponse = struct {
    response: []const u8, //
    id: u32,
};

pub fn http_get(allocator: std.mem.Allocator, client: *const curl.Easy, url: []const u8) ![]const u8 {
    const response = rsp: {
        const urlZ: [:0]u8 = try allocator.allocSentinel(u8, url.len, 0);
        @memcpy(urlZ, url);
        defer allocator.free(urlZ);
        break :rsp try client.get(urlZ);
    };
    defer response.deinit();
    if (response.status_code < 200 or response.status_code >= 300) {
        std.log.err("req failed with {d} for URL: {s}", .{ response.status_code, url });
        return error.StatusCodeErr;
    }

    // var arena = try allocator.create(ArenaAllocator);
    // errdefer {
    //     arena.deinit();
    //     allocator.destroy(arena);
    // }
    // arena.* = ArenaAllocator.init(allocator);
    // var arena_alloc = arena.allocator();
    const body_buffer = response.body orelse return error.NoBody;
    if (body_buffer.capacity == 0) {
        std.log.warn("NB: {d}", .{response.status_code});
        return error.NoBody;
    }
    return try allocator.dupe(u8, body_buffer.items);
}

pub fn http_post(allocator: std.mem.Allocator, client: *const curl.Easy, url: []const u8, content: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const response = rsp: {
        errdefer buf.deinit();
        const urlZ: [:0]u8 = try allocator.allocSentinel(u8, url.len, 0);
        @memcpy(urlZ, url);
        defer allocator.free(urlZ);
        try client.setWritefunction(curl.bufferWriteCallback);
        try client.setWritedata(&buf);
        try client.setUrl(urlZ);
        try client.setPostFields(content);
        var resp = try client.perform();
        resp.body = buf;
        break :rsp resp;
    };
    defer response.deinit();
    if (response.status_code < 200 or response.status_code >= 300) {
        std.log.err("req failed with {d} for URL: {s}", .{ response.status_code, url });
        return error.StatusCodeErr;
    }
    const body_buffer = response.body orelse return error.NoBody;
    if (body_buffer.capacity == 0) {
        std.log.warn("NB: {d}", .{response.status_code});
        return error.NoBody;
    }
    return try allocator.dupe(u8, body_buffer.items);
}

pub fn extract_total(text: []const u8) ?u32 {
    const needle = "\"total\":";
    var start_pos = std.mem.indexOf(u8, text, needle) orelse {
        return null;
    };
    start_pos += needle.len;
    const end_pos = std.mem.indexOfPos(u8, text, start_pos, ",") orelse return null;
    return std.fmt.parseInt(u32, text[start_pos..end_pos], 0) catch return null;
}

const available_page_sizes = [_]u32{ 50, 20, 15, 10, 5, 3, 2 };

// const template_url = switch (builtin.mode) {
//     .Debug => "http://127.0.0.1:8765/{s}/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=0x{x}&pageSize={d}&catalogId={s}",
//     else => "https://www.binance.{s}/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=0x{x}&pageSize={d}&catalogId={s}",
// };
const template_url = "https://www.binance.{s}/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=0x{x}&pageSize={d}&catalogId={s}";

pub const ChangeWaitingParams = struct { catalog_id: u16, tld: []const u8, seed: usize, anonymizer: ?[]const u8 };
pub const PunchParams = struct { catalog_id: u16, tld: []const u8, seed: usize, anonymizer: ?[]const u8 };

pub fn check_for_total_change(allocator: std.mem.Allocator, easy: *const curl.Easy, config: *const ChangeWaitingParams, latest_total: *u32) !?u32 {
    const seeded_page = config.seed;
    const page_size = available_page_sizes[seeded_page % available_page_sizes.len];
    const latest_page_possible: u16 = switch (config.catalog_id) {
        161 => switch (page_size) { // 280 max
            2 => 100,
            3 => 15,
            5 => 35,
            10 => 27,
            15 => 9,
            20 => 7,
            50 => 3,
            else => 8,
        },
        48 => switch (page_size) {
            2 => 300,
            3 => 80,
            5 => 100,
            10 => 140,
            15 => 100,
            20 => 40,
            50 => 20,
            else => 100,
        },
        else => switch (page_size) {
            2 => 950,
            3 => 100,
            5 => 300,
            10 => 200,
            15 => 100,
            20 => 100,
            50 => 40,
            else => 100,
        },
    };

    const page_num = (seeded_page % (latest_page_possible - 1)) + 1; // from 1 up to latest_page_possible
    const catalog_str = try std.fmt.allocPrint(allocator, "{d}", .{config.catalog_id});
    defer allocator.free(catalog_str);
    const url = try std.fmt.allocPrint(allocator, template_url, .{ config.tld, page_num, page_size, catalog_str });
    defer allocator.free(url);
    //std.base64.url_safe.Encoder.encode(, source: []const u8)
    //.encode(encoder: *const Base64Encoder, dest: []u8, source: []const u8)

    const body = if (config.anonymizer) |anonymizer_addr|
        try http_post(allocator, easy, anonymizer_addr, url)
    else
        try http_get(allocator, easy, url);

    defer allocator.free(body);
    const new_total = extract_total(body) orelse {
        std.log.err("NNF: {d}:{d},{d}: {s}", .{ config.catalog_id, page_size, page_num, body[0..@min(80, body.len)] });
        return error.NeedleNotFound;
    };
    std.log.debug("ID {d} for {s}", .{ new_total, url });
    if (new_total > latest_total.*) {
        const prev_total = latest_total.*;
        latest_total.* = new_total;
        if (prev_total != 0) {
            return new_total;
        }
    }
    return null;
}

pub fn punch_announce_update(allocator: std.mem.Allocator, easy: *const curl.Easy, config: *const PunchParams, new_total: u32) !?[]const u8 {
    for (1..400) |punch| {
        loop: for (available_page_sizes) |size| {
            const fetch_url = cid: {
                const zero_pad = try repeatZ(allocator, "0", (punch + config.seed) % 300);
                defer allocator.free(zero_pad);
                const plus_pad = try repeatZ(allocator, "+", (punch + config.seed) % 3);
                defer allocator.free(plus_pad);
                const tweaked_catalog_id = try std.fmt.allocPrint(allocator, "{s}{s}{d}", .{ plus_pad, zero_pad, config.catalog_id });
                defer allocator.free(tweaked_catalog_id);
                break :cid try std.fmt.allocPrint(allocator, template_url, .{ config.tld, 1, size, tweaked_catalog_id });
            };

            defer allocator.free(fetch_url);
            var time_spent_query = std.time.milliTimestamp();
            const body_request = if (config.anonymizer) |anonymizer_addr|
                http_post(allocator, easy, anonymizer_addr, fetch_url)
            else
                http_get(allocator, easy, fetch_url);
            const body = body_request catch |erz| {
                std.log.debug("Punch err {s}: attempt: {d} url: {s}", .{ @errorName(erz), punch, fetch_url });
                continue :loop; // ignore errors;
            };
            const total = extract_total(body) orelse {
                std.log.warn("NT {s}...", .{body[0..@min(80, body.len)]});
                allocator.free(body);
                continue :loop;
            };
            time_spent_query = std.time.milliTimestamp() - time_spent_query;
            if (total >= new_total) {
                return body;
            } else {
                allocator.free(body);
            }
            const sleep_remaning: u64 = @intCast(@max(0, 100 - time_spent_query)); // max 100 ms sleep
            std.time.sleep(sleep_remaning * std.time.ns_per_ms);
        }
        std.time.sleep(std.time.ns_per_ms * 100);
    }
    return null;
}

// pub fn wait_for_announcement(allocator: std.mem.Allocator, seed: usize) !void {
//     const curl_module = try wcurl.Curl.init(allocator);
//     defer curl_module.deinit();
//     const easy = curl_module.easy;
//
//     const announcements_hack = [_][]const u8{ "a%256e%256e%256f%2575%256e%2563eme%256et", "a%256e%256e%256fu%256e%2563e%256de%256et", "a%256e%256eou%256e%2563%2565men%2574", "an%256e%256f%2575%256e%2563e%256d%2565n%2574", "an%256e%256func%2565%256de%256et", "an%256e%256func%2565ment", "an%256e%256funce%256den%2574", "an%256eo%2575%256e%2563%2565m%2565%256et", "an%256eo%2575n%2563eme%256et", "an%256eo%2575nce%256d%2565nt", "an%256eo%2575ncem%2565nt", "an%256eou%256e%2563%2565ment", "an%256eou%256ec%2565ment", "ann%256f%2575nc%2565ment", "ann%256fun%2563%2565%256d%2565nt", "ann%256fun%2563ement", "anno%2575%256ec%2565%256d%2565%256et", "anno%2575nce%256dent", "annou%256e%2563ement", "annou%256ec%2565me%256et", "annou%256ecem%2565%256et", "annou%256ecem%2565nt", "annou%256eceme%256et", "annou%256ecemen%2574", "annou%256ecement", "announ%2563e%256de%256et", "announc%2565%256d%2565n%2574", "announc%2565m%2565n%2574", "announcement" };
//     const domain_suffixes = [_][]const u8{ "info", "com" };
//     var latest_fingerprint: u32 = 0;
//     for (1..10000) |outer_iter| {
//         std.log.info("iteration {d}, fingerprint {d}", .{ outer_iter, latest_fingerprint });
//         var time_counter: u96 = 0;
//         const max_url_padding = 495;
//         const suffix = domain_suffixes[(outer_iter + seed) % domain_suffixes.len];
//         for (1..max_url_padding) |iteration| {
//             const hack = try repeatZ(allocator, "0", iteration);
//             defer allocator.free(hack);
//             const announcement_part = announcements_hack[(iteration + seed) % announcements_hack.len];
//             const url_for_templating = "https://www.binance.{s}/en/support/{s}/list/{s}93";
//             const binance_url = try std.fmt.allocPrint(allocator, url_for_templating, //
//                 .{ suffix, announcement_part, hack });
//             defer allocator.free(binance_url);
//             const ts_before = std.time.nanoTimestamp();
//             const result = try http_get(allocator, &easy, binance_url);
//             const request_time_ms = @divFloor(std.time.nanoTimestamp() - ts_before, 1_000_000);
//             time_counter += @intCast(request_time_ms);
//             std.log.debug("query performed in {d}ms, {s}", .{ request_time_ms, binance_url });
//             defer result.deinit();
//             const new_fingerprint = result.value.id;
//             if (latest_fingerprint < new_fingerprint) {
//                 const latest_news_timestamp = extract_timestamp(result.value.response) orelse 0;
//                 const ts = std.time.timestamp();
//                 std.log.info("watermark changed for url {s}", .{binance_url});
//                 if (latest_fingerprint != 0) {
//                     std.log.info("watermark changed,{d},{d},{d}, {d} ::{d} seconds", .{ ts, latest_fingerprint, new_fingerprint, latest_news_timestamp, @divFloor(latest_news_timestamp, 1000) - ts });
//
//                     var dirPath: [100]u8 = undefined;
//                     const absPath = try std.fs.selfExeDirPath(&dirPath);
//                     const tsString = try std.fmt.allocPrintZ(allocator, "{d}", .{ts});
//                     defer allocator.free(tsString);
//                     const path = try std.fs.path.join(allocator, &[_][]const u8{ absPath, tsString });
//                     defer allocator.free(path);
//                     try files.write_file(path, result.value.response);
//                     std.log.debug("file successfully updated at {s}", .{path});
//                 }
//                 latest_fingerprint = new_fingerprint;
//             }
//             std.time.sleep(std.time.ns_per_s * 5);
//         }
//         std.log.info("loop {d} finished. req avg time: {d}", .{ outer_iter, time_counter / max_url_padding });
//         std.time.sleep(std.time.ns_per_s * 30);
//     }
// }

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
pub fn exctact_id_and_tokens(body: []const u8) struct { id: u32, tokens: []const u8 } {
    const needle = "\"id\":";
    const start_index = std.mem.indexOf(u8, body, needle) orelse return .{ .id = 0, .tokens = "" };
    const start = start_index + needle.len;
    var end: usize = start;
    while (end < body.len and std.ascii.isDigit(body[end])) {
        end += 1;
    }
    const id_slice = body[start..end];
    const id = std.fmt.parseInt(u32, id_slice, 10) catch return .{ .id = 0, .tokens = "" };

    return .{ .id = id, .tokens = "" };
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

pub fn perform_timing_tests(allocator: std.mem.Allocator) !void {
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

fn repeatZ(allocator: std.mem.Allocator, pattern: []const u8, count: usize) ![:0]u8 {
    const len = pattern.len * count;
    var result = try allocator.allocSentinel(u8, len, 0);
    for (0..count) |i| {
        @memcpy(result[i * pattern.len .. (i + 1) * pattern.len], pattern);
    }
    return result;
}

test "repeat pattern" {
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
