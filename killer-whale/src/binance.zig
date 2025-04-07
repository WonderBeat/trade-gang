const std = @import("std");
const expect = std.testing.expect;
const http = std.http;
const ArenaAllocator = std.heap.ArenaAllocator;

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

pub fn fingerprinted_get(allocator: std.mem.Allocator, client: *const curl.Easy, url: []const u8) !Parsed(WatermarkedResponse) {
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

    var arena = try allocator.create(ArenaAllocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }
    arena.* = ArenaAllocator.init(allocator);
    var arena_alloc = arena.allocator();
    const body_buffer = response.body orelse return error.NoBody;
    if (body_buffer.capacity == 0) {
        return error.NoBody;
    }
    const body = try arena_alloc.dupe(u8, body_buffer.items);
    const needle = "\"total\":";
    var start_pos = std.mem.indexOf(u8, body, needle) orelse {
        std.log.err("NNF in {s}\n {s}", .{ url, body });
        return error.NeedleNotFound;
    };
    start_pos += needle.len;
    const end_pos = std.mem.indexOfPos(u8, body, start_pos, ",") orelse return error.NeedleNotFound;
    const id = try std.fmt.parseInt(u32, body[start_pos..end_pos], 0);

    return Parsed(WatermarkedResponse){ .arena = arena, .value = WatermarkedResponse{ .id = id, .response = body } };
}

const available_page_sizes = [_]u32{ 50, 20, 15, 10, 5, 3, 2 };

const template_url = "https://www.binance.{s}/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=0x{x}&pageSize={d}&catalogId={s}";
//const template_url = "http://127.0.0.1:8765/{s}/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=0x{x}&pageSize={d}&catalogId={s}";

pub const ChangeWaitingParams = struct { catalog_id: []const u8, tld: []const u8, seed: usize };

pub fn wait_for_total_change(allocator: std.mem.Allocator, easy: *const curl.Easy, config: ChangeWaitingParams, latest_total: *u32) !?Parsed(WatermarkedResponse) {
    for (1..10) |page_index| {
        if (page_index % 100 == 0) {
            std.log.info("{d} iterations", .{page_index});
        }
        const seeded_page = page_index + config.seed;
        const page_size = available_page_sizes[seeded_page % available_page_sizes.len];
        const latest_page_possible: u16 = switch (page_size) {
            2 => 950,
            3 => 100,
            5 => 300,
            10 => 200,
            15 => 100,
            20 => 100,
            50 => 40,
            else => 100,
        }; // hard limit
        const page_num = (seeded_page % (latest_page_possible - 1)) + 1; // from 1 up to latest_page_possible
        const url = try std.fmt.allocPrint(allocator, template_url, .{ config.tld, page_num, page_size, config.catalog_id });
        defer allocator.free(url);
        var time_spent_query = std.time.milliTimestamp();
        const result = try fingerprinted_get(allocator, easy, url);
        time_spent_query = std.time.milliTimestamp() - time_spent_query;
        const new_total = result.value.id;
        std.log.debug("ID {d} for {s} in {d}ms", .{ new_total, url, time_spent_query });
        if (new_total > latest_total.*) {
            if (latest_total.* != 0) {
                std.log.debug("Total updated {d},{d}", .{ latest_total.*, new_total });
                return result;
            }
            latest_total.* = result.value.id;
        }
        result.deinit();
        const sleep_remaning: u64 = @intCast(@max(50, (5 * std.time.ms_per_s) - time_spent_query)); // min 50ms sleep
        std.log.debug("spleeping for {d}ms", .{sleep_remaning});
        std.time.sleep(sleep_remaning * std.time.ns_per_ms);
    }
    return null;
}

pub fn punch_announce_update(allocator: std.mem.Allocator, easy: *const curl.Easy, catalog_id: []const u8, tld: []const u8, new_total: u32) !?Parsed(WatermarkedResponse) {
    for (1..111) |punch| {
        loop: for (available_page_sizes) |size| {
            const zero_pad = try repeatZ(allocator, "0", punch);
            defer allocator.free(zero_pad);
            const tweaked_catalog_id = try std.fmt.allocPrint(allocator, "+{s}{s}", .{ zero_pad, catalog_id });
            defer allocator.free(tweaked_catalog_id);
            const fetch_url = try std.fmt.allocPrint(allocator, template_url, .{ tld, 1, size, tweaked_catalog_id });
            defer allocator.free(fetch_url);
            const response = fingerprinted_get(allocator, easy, fetch_url) catch |erz| {
                std.log.debug("Punching {d}:{s}: {s}", .{ punch, fetch_url, @errorName(erz) });
                continue :loop; // ignore errors;
            };
            if (response.value.id >= new_total) {
                return response;
            } else {
                response.deinit();
            }
        }
        std.time.sleep(std.time.ns_per_ms * 111);
    }
    return null;
}

pub fn wait_for_announcement(allocator: std.mem.Allocator, seed: usize) !void {
    const curl_module = try wcurl.Curl.init(allocator);
    defer curl_module.deinit();
    const easy = curl_module.easy;

    const announcements_hack = [_][]const u8{ "a%256e%256e%256f%2575%256e%2563eme%256et", "a%256e%256e%256fu%256e%2563e%256de%256et", "a%256e%256eou%256e%2563%2565men%2574", "an%256e%256f%2575%256e%2563e%256d%2565n%2574", "an%256e%256func%2565%256de%256et", "an%256e%256func%2565ment", "an%256e%256funce%256den%2574", "an%256eo%2575%256e%2563%2565m%2565%256et", "an%256eo%2575n%2563eme%256et", "an%256eo%2575nce%256d%2565nt", "an%256eo%2575ncem%2565nt", "an%256eou%256e%2563%2565ment", "an%256eou%256ec%2565ment", "ann%256f%2575nc%2565ment", "ann%256fun%2563%2565%256d%2565nt", "ann%256fun%2563ement", "anno%2575%256ec%2565%256d%2565%256et", "anno%2575nce%256dent", "annou%256e%2563ement", "annou%256ec%2565me%256et", "annou%256ecem%2565%256et", "annou%256ecem%2565nt", "annou%256eceme%256et", "annou%256ecemen%2574", "annou%256ecement", "announ%2563e%256de%256et", "announc%2565%256d%2565n%2574", "announc%2565m%2565n%2574", "announcement" };
    const domain_suffixes = [_][]const u8{ "info", "com" };
    var latest_fingerprint: u32 = 0;
    for (1..10000) |outer_iter| {
        std.log.info("iteration {d}, fingerprint {d}", .{ outer_iter, latest_fingerprint });
        var time_counter: u96 = 0;
        const max_url_padding = 495;
        const suffix = domain_suffixes[(outer_iter + seed) % domain_suffixes.len];
        for (1..max_url_padding) |iteration| {
            const hack = try repeatZ(allocator, "0", iteration);
            defer allocator.free(hack);
            const announcement_part = announcements_hack[(iteration + seed) % announcements_hack.len];
            const url_for_templating = "https://www.binance.{s}/en/support/{s}/list/{s}93";
            const binance_url = try std.fmt.allocPrint(allocator, url_for_templating, //
                .{ suffix, announcement_part, hack });
            defer allocator.free(binance_url);
            const ts_before = std.time.nanoTimestamp();
            const result = try fingerprinted_get(allocator, &easy, binance_url);
            const request_time_ms = @divFloor(std.time.nanoTimestamp() - ts_before, 1_000_000);
            time_counter += @intCast(request_time_ms);
            std.log.debug("query performed in {d}ms, {s}", .{ request_time_ms, binance_url });
            defer result.deinit();
            const new_fingerprint = result.value.id;
            if (latest_fingerprint < new_fingerprint) {
                const latest_news_timestamp = extract_timestamp(result.value.response) orelse 0;
                const ts = std.time.timestamp();
                std.log.info("watermark changed for url {s}", .{binance_url});
                if (latest_fingerprint != 0) {
                    std.log.info("watermark changed,{d},{d},{d}, {d} ::{d} seconds", .{ ts, latest_fingerprint, new_fingerprint, latest_news_timestamp, @divFloor(latest_news_timestamp, 1000) - ts });

                    var dirPath: [100]u8 = undefined;
                    const absPath = try std.fs.selfExeDirPath(&dirPath);
                    const tsString = try std.fmt.allocPrintZ(allocator, "{d}", .{ts});
                    defer allocator.free(tsString);
                    const path = try std.fs.path.join(allocator, &[_][]const u8{ absPath, tsString });
                    defer allocator.free(path);
                    try files.write_file(path, result.value.response);
                    std.log.debug("file successfully updated at {s}", .{path});
                }
                latest_fingerprint = new_fingerprint;
            }
            std.time.sleep(std.time.ns_per_s * 5);
        }
        std.log.info("loop {d} finished. req avg time: {d}", .{ outer_iter, time_counter / max_url_padding });
        std.time.sleep(std.time.ns_per_s * 30);
    }
}

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
