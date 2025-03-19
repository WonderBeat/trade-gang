const std = @import("std");
const http = std.http;
const json = std.json;
const Request = std.http.Client.Request;
const ArenaAllocator = std.heap.ArenaAllocator;
const yaml = @import("ymlz");
const curl = @import("curl");
const builtin = @import("builtin");
const files = @import("file/files.zig");
const bin = @import("binance.zig");

pub const default_level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .debug,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

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
    const urlZ: [:0]u8 = try allocator.allocSentinel(u8, url.len, 0);

    @memcpy(urlZ, url);
    defer allocator.free(urlZ);

    const response = try client.get(urlZ);
    defer response.deinit();
    if (response.status_code != 200) {
        std.log.err("HTTP request failed with status code: {d} for URL: {s}\n", .{ response.status_code, url });
        return error.QueryFailed;
    }

    var arena = try allocator.create(ArenaAllocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }
    arena.* = ArenaAllocator.init(allocator);
    var arena_alloc = arena.allocator();
    const body_buffer = response.body orelse return error.QueryFailed;
    if (body_buffer.capacity == 0) {
        return error.QueryFailed;
    }
    const body = try arena_alloc.dupe(u8, body_buffer.items);
    const needle = "\"total\":";
    var start_pos = std.mem.indexOf(u8, body, needle) orelse return error.NeedleNotFound;
    start_pos += needle.len;
    const end_pos = std.mem.indexOfPos(u8, body, start_pos, ",") orelse return error.NeedleNotFound;
    const id = try std.fmt.parseInt(u32, body[start_pos..end_pos], 0);

    return Parsed(WatermarkedResponse){ .arena = arena, .value = WatermarkedResponse{ .id = id, .response = body } };
}

fn wait_for_update(allocator: std.mem.Allocator, comptime url_for_templating: [:0]const u8, seed: usize) !void {
    const ca_bundle = try curl.allocCABundle(allocator);
    defer ca_bundle.deinit();
    const easy = try curl.Easy.init(allocator, .{
        .default_user_agent = "open-ai", //
        .ca_bundle = ca_bundle,
    });
    _ = curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_ACCEPT_ENCODING, "gzip");
    _ = curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_TCP_KEEPALIVE, @as(c_long, 1));
    defer easy.deinit();
    const hostname = std.posix.getenv("HOSTNAME") orelse "UNDEF";
    const user_agent = try std.fmt.allocPrint(allocator, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:135.0) Gecko/20100101 Firefox/135.0, {s}", .{hostname});
    defer allocator.free(user_agent);
    const headers = blk: {
        var h = try easy.createHeaders();
        errdefer h.deinit();
        try h.add("Origin", "www.binance.com");
        try h.add("Accept", "text/html,application/xhtml+xml");
        try h.add("user_agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:135.0) Gecko/20100101 Firefox/135.0");
        try h.add("Accep-Language", "en-US,en;q=0.5");
        const cookie = std.posix.getenv("COOKIE") orelse "";
        try h.add("Cookie", cookie);
        try h.add("User-Agent", user_agent);
        break :blk h;
    };
    defer headers.deinit();
    try easy.setHeaders(headers);

    const announcements_hack = [_][]const u8{ "a%256e%256e%256f%2575%256e%2563eme%256et", "a%256e%256e%256fu%256e%2563e%256de%256et", "a%256e%256eou%256e%2563%2565men%2574", "an%256e%256f%2575%256e%2563e%256d%2565n%2574", "an%256e%256func%2565%256de%256et", "an%256e%256func%2565ment", "an%256e%256funce%256den%2574", "an%256eo%2575%256e%2563%2565m%2565%256et", "an%256eo%2575n%2563eme%256et", "an%256eo%2575nce%256d%2565nt", "an%256eo%2575ncem%2565nt", "an%256eou%256e%2563%2565ment", "an%256eou%256ec%2565ment", "ann%256f%2575nc%2565ment", "ann%256fun%2563%2565%256d%2565nt", "ann%256fun%2563ement", "anno%2575%256ec%2565%256d%2565%256et", "anno%2575nce%256dent", "annou%256e%2563ement", "annou%256ec%2565me%256et", "annou%256ecem%2565%256et", "annou%256ecem%2565nt", "annou%256eceme%256et", "annou%256ecemen%2574", "annou%256ecement", "announ%2563e%256de%256et", "announc%2565%256d%2565n%2574", "announc%2565m%2565n%2574", "announcement" };
    const domain_suffixes = [_][]const u8{ "info", "com" };
    var latest_fingerprint: u32 = 0;
    for (1..10000) |outer_iter| {
        std.log.info("iteration {d}, fingerprint {d}", .{ outer_iter, latest_fingerprint });
        var time_counter: u96 = 0;
        const max_url_padding = 490;
        const suffix = domain_suffixes[(outer_iter + seed) % domain_suffixes.len];
        for (1..max_url_padding) |iteration| {
            const hack = try bin.repeatZ(allocator, "0", iteration);
            defer allocator.free(hack);
            const announcement_part = announcements_hack[(iteration + seed) % announcements_hack.len];
            const binance_url = try std.fmt.allocPrint(allocator, url_for_templating, //
                .{ suffix, announcement_part, hack });
            defer allocator.free(binance_url);
            const ts_before = std.time.nanoTimestamp();
            const result = try fingerprinted_get(allocator, &easy, binance_url);
            const request_time_ms = @divFloor(std.time.nanoTimestamp() - ts_before, 1_000_000);
            time_counter += @intCast(request_time_ms);
            std.log.debug("query performed in {d}ms {s}", .{ request_time_ms, binance_url });
            defer result.deinit();
            const new_fingerprint = result.value.id;
            if (latest_fingerprint < new_fingerprint) {
                const latest_news_timestamp = bin.extract_timestamp(result.value.response) orelse 0;
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
            std.time.sleep(std.time.ns_per_s * 4);
        }
        std.log.info("loop {d} finished. req avg time: {d}", .{ outer_iter, time_counter / max_url_padding });
        std.time.sleep(std.time.ns_per_s * 30);
    }
}

pub fn main() !void {
    var debug_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //var log_builder = nexlog.LogBuilder.init();
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.c_allocator, false },
        };
    };
    //const JsonHandler = nexlog.output.json_handler.JsonHandler;
    // var json_handler = try JsonHandler.init(allocator, .{
    //     .min_level = .debug,
    //     .pretty_print = true, // Optional: Makes the JSON output more readable
    //     .output_file = null,
    // });

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };
    const seed = brk: {
        var prng = std.rand.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        break :brk std.rand.intRangeAtMost(prng.random(), usize, 0, 10000);
    };
    try wait_for_update(allocator, "https://www.binance.{s}/en/support/{s}/list/{s}93", seed);
}

test {
    std.testing.refAllDecls(@This());
}
