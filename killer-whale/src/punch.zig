const std = @import("std");
const builtin = @import("builtin");

const bin = @import("binance.zig");
const messaging = @import("messaging.zig");
const parse = @import("parsers.zig");
const wcurl = @import("curl.zig");
const prometheus = @import("prometheus.zig");
const proxy = @import("proxy-manager.zig");

pub const PunchParams = struct {
    catalogId: u16,
    tld: []const u8,
    seed: usize,
    anonymizer: ?[]const u8,
    iterations: u32 = 500,
    sleep: u32 = 100,
    lastSeenTotal: u32,
    proxyManager: ?proxy.ProxyManager = null,
};

// returns bool - true if important update was received. null if nothing found
pub fn punchNotify(allocator: std.mem.Allocator, curl_cli: *wcurl.Curl, announce_url: std.net.Address, config: *const PunchParams) !bool {
    try curl_cli.initHeaders(.{});
    const easy = curl_cli.easy;
    var fetchParams = bin.FetchParams{
        .catalogId = config.catalogId,
        .tld = config.tld,
        .seed = config.seed,
        .anonymizer = config.anonymizer,
    };
    const startSeed = fetchParams.seed;
    var maybe_update: ?bin.Announce = null;
    for (0..config.iterations) |iter| {
        var time_spent_query = std.time.milliTimestamp();

        fetchParams.seed = startSeed + iter;
        const pageSize: u16 = if ((fetchParams.seed ^ (config.seed << 2)) % 100 > 50) 50 else 10;
        fetchParams.page.size = pageSize;
        const result = bin.fetchDecodeLatestInCatalog(allocator, &easy, &fetchParams) catch |errz| not_found: {
            std.log.err("PErr with {?s} {s}", .{ curl_cli.proxyManager.getCurrentProxy(), @errorName(errz) });
            _ = try curl_cli.dropCurrentProxy();
            try curl_cli.exchangeProxy();
            prometheus.err();
            break :not_found null;
        };
        if (result) |data| {
            defer data.deinit();
            prometheus.hit();
            if (curl_cli.latest_query_metrics()) |metrics| {
                const execution_time_ms = metrics.total_time - metrics.pretransfer_time;
                prometheus.latency(@intCast(execution_time_ms));
            }
            if (data.total > config.lastSeenTotal) {
                std.log.info("Punch success 🚀 {d}: {s}", .{ data.total, data.url });
                maybe_update = data;
                break;
            }
        }
        if (iter % 13 == 0) {
            try prometheus.dumpToFile();
        }
        try curl_cli.exchangeProxy();
        time_spent_query = std.time.milliTimestamp() - time_spent_query;
        const sleep_remaning: u64 = @intCast(@max(50, config.sleep - time_spent_query));
        std.Thread.sleep(sleep_remaning * std.time.ns_per_ms);
    }
    if (maybe_update) |update| no_update: {
        defer update.deinit();
        if (update.title.len < 5 or update.releaseDate < 10000) {
            std.log.warn("Mailformed announce {d} {s}({d})", .{ update.id, update.title, update.releaseDate });
            break :no_update;
        }
        const ts = std.time.timestamp();
        std.log.info("Timestamps: ours {d} announcement {d}, diff: {d}", .{ ts, update.releaseDate, ts - @divFloor(update.releaseDate, 1000) });
        const bytes_count = messaging.sendAnnounce(allocator, announce_url, &update) catch 0;
        std.log.info("Announce sent {d} ({d} bytes). Sleeping...", .{ update.id, bytes_count });
        return bytes_count > 0;
    }
    return false;
}
