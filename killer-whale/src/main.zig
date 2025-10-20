const std = @import("std");
const builtin = @import("builtin");
const yazap = @import("yazap");
const App = yazap.App;
const Arg = yazap.Arg;

const punch = @import("punch.zig");
const bin = @import("binance.zig");
const json = @import("json.zig");
const messaging = @import("messaging.zig");
const mqtt = @import("mqtt.zig");
const parse = @import("parsers.zig");
const wcurl = @import("curl.zig");
const curl = @import("curl");
const metrics = @import("prometheus.zig");
const proxy = @import("proxy-manager.zig");
const fastfilter = @import("fastfilter");

//for simdjzon
pub const read_buf_cap = 4096;

const BINANCE_TOPIC = if (builtin.mode == .Debug) "binance-test" else "binance";

//const yaml = @import("ymlz");
pub const std_options = std.Options{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .debug,
        .ReleaseFast => .info,
        .ReleaseSmall => .info,
    },
};

// comptime {
//     var buf = [_]u8{0} ** 1000;
//     var fba = std.heap.FixedBufferAllocator.init(&buf);
//     var allocator = fba.allocator();
//     _ = allocator.alloc(u8, 1) catch 0;
// }

pub fn main() !void {
    var debug_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.c_allocator, false },
        };
    };
    if (!is_debug) {
        try metrics.initializeMetrics(.{ .prefix = "killa_" });
    }

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };
    if (is_debug) {
        var cmd_parser = App.init(allocator, "killer-whale", "Find and Eliminate");
        defer cmd_parser.deinit();
        var message = cmd_parser.createCommand("message", "send announce and exit");
        try message.addArg(Arg.singleValueOption("address", 'a', "destination address"));
        var punchCmd = cmd_parser.createCommand("punch", "Punch and exit");
        try punchCmd.addArg(Arg.singleValueOption("id", 'i', "announce ID"));
        try punchCmd.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        try punchCmd.addArg(Arg.singleValueOption("anonymizer", 'a', "anonymizer address"));
        try punchCmd.addArg(Arg.singleValueOption("tld", 't', "TLD"));
        var avalance = cmd_parser.createCommand("avalance", "avalance and exit");
        try avalance.addArg(Arg.singleValueOption("mqtt", 'm', "mqtt address"));
        try avalance.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        try avalance.addArg(Arg.singleValueOption("total", 't', "id to punch for"));
        try avalance.addArg(Arg.singleValueOption("tld", 't', "TLD"));
        var root = cmd_parser.rootCommand();
        try root.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        try root.addSubcommand(punchCmd);
        try root.addSubcommand(message);
        try root.addSubcommand(avalance);
        const matches = try cmd_parser.parseProcess();

        if (matches.subcommandMatches("message")) |message_cmd_matches| {
            const address = message_cmd_matches.getSingleValue("address") orelse "127.0.0.1:8081";
            const title = "Binance Will Delist ANT, MULTI, VAI, XMR on 2024-02-20";
            const tokens = try parse.extractCoins(allocator, title);
            defer allocator.free(tokens);
            const ip = try resolve_address(address);
            const announce = bin.Announce{ .allocator = allocator, .url = address, .total = 0, .releaseDate = 0, .catalogId = 0, .title = title, .id = 0 };
            const bytes_sent = try messaging.sendAnnounce(allocator, ip, &announce);
            std.log.debug("Msg sent {d} bytes", .{bytes_sent});
            return;
        } else if (matches.subcommandMatches("punch")) |punch_cmd| {
            const id = try std.fmt.parseInt(u16, punch_cmd.getSingleValue("id") orelse return, 0);
            const anonymizer = punch_cmd.getSingleValue("anonymizer") orelse null;
            const tld = punch_cmd.getSingleValue("tld") orelse "me";
            const catalog = try std.fmt.parseInt(u16, punch_cmd.getSingleValue("catalog") orelse return, 0);
            const curl_module = try wcurl.Curl.init(allocator);
            defer curl_module.deinit();

            const config = punch.PunchParams{ .catalogId = catalog, .tld = tld, .anonymizer = anonymizer, .seed = 0, .lastSeenTotal = id };
            const result = try punch.punchNotify(allocator, curl_module, try resolve_address("127.0.0.1:8888"), &config);
            std.log.info("Punched with result {s}...", .{if (result) "success" else "failure"});
            return;
        } else if (matches.subcommandMatches("avalance")) |avalance_cmd| {
            const mqtt_address = avalance_cmd.getSingleValue("mqtt") orelse return;
            const tld = avalance_cmd.getSingleValue("tld") orelse "me";
            const catalog = try std.fmt.parseInt(u16, avalance_cmd.getSingleValue("catalog") orelse "98", 0);
            const total = try std.fmt.parseInt(u16, avalance_cmd.getSingleValue("total") orelse "0", 0);
            const mqtt_cli = try mqtt.Mqtt.init(allocator, mqtt_address);
            defer {
                mqtt_cli.deinit();
            }
            try send_mqtt_alert(mqtt_cli, catalog, total, parse.Tld.from_string(tld).?);
            return;
        }
    }

    const catalog = try std.fmt.parseInt(u16, std.posix.getenv("CATALOG") orelse "93", 0);
    const tld = std.posix.getenv("TLD") orelse "com";

    const send_announce_address = try resolve_address(std.posix.getenv("MOTHERSHIP") orelse {
        std.log.err("Mothership address required", .{});
        return;
    });
    const anonymizer = std.posix.getenv("ANONYMIZER");
    const mqtt_address = std.posix.getenv("MQTT") orelse {
        std.log.err("MQTT address required", .{});
        return;
    };

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const curl_module = try wcurl.Curl.init(allocator);
    defer curl_module.deinit();
    const client = try mqtt.Mqtt.init(allocator, mqtt_address);
    _ = try client.subscribe(BINANCE_TOPIC);
    defer {
        client.deinit();
    }
    if (anonymizer == null) {
        if (std.posix.getenv("FETCH_URL")) |url| {
            curl_module.setProxyDownloadUrl(url);
            try curl_module.exchangeProxy();
        }
    }

    if (std.posix.getenv("PASSIVE")) |_| {
        std.log.info("Passive mode ON: mothership {any}, mqtt {s}", .{ send_announce_address, mqtt_address });
        for (0..1111) |_| {
            if (try passive_punch_mode(allocator, client, curl_module, 10_000, anonymizer, 1, send_announce_address, parse.Tld.Me)) |_| {
                std.Thread.sleep(std.time.ns_per_s * 30); // cooldown
                return;
            }
            _ = try client.ping();
        }
        std.log.info("Passive mode finished", .{});
        return;
    }
    const iterations = if (is_debug) 6 else (20 + prng.random().intRangeAtMost(usize, 0, 30));
    const catalogConfig = switch (catalog) {
        161 => bin.catalogPages.delisting,
        48 => bin.catalogPages.listing,
        else => bin.catalogPages.default,
    };
    var alreadySeenFilter = try fastfilter.BinaryFuse(u32).init(allocator, 50);
    defer alreadySeenFilter.deinit(allocator);
    var initialized: bool = false;
    for (0..iterations) |_| {
        const seed = std.Random.intRangeAtMost(prng.random(), usize, 0, 999999);
        //try curl_module.set_trim_body(0, 400);
        const result: ?bin.Announce = found: {
            var config = bin.FetchParams{
                .catalogId = catalog,
                .tld = tld,
                .seed = seed,
                .anonymizer = anonymizer,
            };
            for (1..iterations) |iter| {
                var timeSpentIoMs = std.time.milliTimestamp();
                config.seed = seed + iter;
                //config.page = catalogConfig.atOffset(config.seed);
                //Global catalog works only for 1 page
                config.page.offset = 1;
                config.page.size = catalogConfig.pages[config.seed % catalogConfig.pages.len].size;
                var success = true;
                const unseen = fetchUpdate(allocator, curl_module, &config, &alreadySeenFilter) catch |err| notFound: {
                    std.log.debug("fetchUpdate failed: {s}", .{@errorName(err)});
                    success = false;
                    metrics.err();
                    break :notFound null;
                };
                if (success) {
                    std.log.debug("fetchUpdate success: {s}", .{if (unseen != null) "found" else "not found"});
                    metrics.hit();
                }
                if (curl_module.latest_query_metrics()) |cMetrics| {
                    const execution_time_ms = cMetrics.total_time - cMetrics.pretransfer_time;
                    metrics.latency(@intCast(execution_time_ms));
                }
                if (unseen) |fetched| {
                    defer fetched.deinit();
                    if (initialized) { // first update might be triggered by empty bin filter
                        std.debug.assert(config.page.offset == 1);
                        std.log.info("Catalog update signal {d}, for {s} / {?s}", .{ fetched.total, fetched.url, curl_module.proxyManager.getCurrentProxy() });
                        const ts = std.time.timestamp();
                        std.log.info("Timestamps: ours {d} announcement {d}, diff: {d}", .{ ts, fetched.releaseDate, ts - @divFloor(fetched.releaseDate, 1000) });
                        if (fetched.catalogId == catalog) {
                            _ = messaging.sendAnnounce(allocator, send_announce_address, &fetched) catch 0;
                            break :found fetched;
                        } else {
                            std.log.info("Catalog mismatch {d} {d}", .{ fetched.catalogId, catalog });
                        }
                    } else {
                        initialized = true;
                        std.log.info("Catalog filter initialized", .{});
                    }
                }
                // if (iter % 5 == 0) {
                //     try client.ping();
                // }
                if (iter % 13 == 0) {
                    try metrics.dumpToFile();
                }
                if (success) {
                    try curl_module.exchangeProxy();
                } else {
                    const proxiesCount = try curl_module.dropCurrentProxy();
                    if (proxiesCount == 0) {
                        try curl_module.exchangeProxy();
                    }
                }
                timeSpentIoMs = std.time.milliTimestamp() - timeSpentIoMs;
                const sleepRemaningMs: u64 = @intCast(@max(100, 2000 - timeSpentIoMs));
                std.Thread.sleep(std.time.ns_per_ms * sleepRemaningMs); // cooldown
            }
            break :found null;
        };

        if (result == null) {
            std.log.info("Update NOT found after direct punching", .{});
        } else {
            std.log.info("Update found as a result of a signal with proxy: {?s}", .{curl_module.proxyManager.getCurrentProxy()});
            std.Thread.sleep(std.time.ns_per_min * 5);
        }
        //try client.ping();
        std.Thread.sleep(std.time.ns_per_s * 1);
    }
}

fn send_mqtt_alert(cli: *mqtt.Mqtt, catalog: u16, total: u32, tld: parse.Tld) !void {
    var buf: [30:0]u8 = undefined;
    const mqttMsg = try std.fmt.bufPrint(&buf, "{d}|{d}|{s}", .{ catalog, total, tld.to_string() });
    _ = try cli.send(BINANCE_TOPIC, mqttMsg);
}

fn passive_punch_mode(
    allocator: std.mem.Allocator,
    mqtt_cli: *mqtt.Mqtt,
    curl_cli: *wcurl.Curl,
    timeoutMs: i32,
    anonymizer: ?[]const u8,
    seed: usize,
    send_announce_address: std.net.Address,
    overwrite_tld: ?parse.Tld,
) !?struct { catalog: u16, total: u32 } {
    if (try wait_for_message(allocator, mqtt_cli, timeoutMs)) |alert| {
        const alert_tld = (overwrite_tld orelse alert.tld).to_string();
        std.log.info("Cooperative punching activated {d}:{d}:{s}", .{ alert.catalog, alert.total, alert_tld });
        const conf = punch.PunchParams{
            .catalogId = alert.catalog,
            .tld = alert_tld,
            .seed = seed,
            .anonymizer = anonymizer,
            .lastSeenTotal = alert.total,
        };
        const success = try punch.punchNotify(
            allocator,
            curl_cli,
            send_announce_address,
            &conf,
        );
        if (success) {
            std.log.info("Update was found in passive punch mode: {?s}", .{curl_cli.proxyManager.getCurrentProxy()});
        } else {
            std.log.info("Update NOT found in passive punch mode", .{});
        }
        return .{ .catalog = alert.catalog, .total = alert.total };
    }
    return null;
}

fn wait_for_message(
    allocator: std.mem.Allocator,
    mqtt_cli: *mqtt.Mqtt,
    timeoutMs: i32,
) !?struct { catalog: u16, total: u32, tld: parse.Tld } {
    if (try mqtt_cli.receive_string(timeoutMs)) |alert| {
        defer allocator.free(alert);
        var iterator = std.mem.splitScalar(u8, alert, '|');
        const alert_catalog = try std.fmt.parseInt(u16, iterator.first(), 0);
        const alert_latestTotal: u32 = try std.fmt.parseInt(u32, iterator.next().?, 0);
        const tld = parse.Tld.from_string(iterator.next().?) orelse return error.MqttMsgErr;
        return .{ .catalog = alert_catalog, .total = alert_latestTotal, .tld = tld };
    }
    return null;
}

fn filterLastUnseenInList(articles: *const std.ArrayList(bin.Announce), unseenFilter: *fastfilter.BinaryFuse(u32)) !?bin.Announce {
    var result: ?bin.Announce = null;
    var keysToAdd: [10]u64 = std.mem.zeroes([10]u64);
    var keysIndex: u32 = 0;
    for (articles.items) |article| {
        if (unseenFilter.contain(article.id)) {
            std.log.debug("Skipping already seen: {d}", .{article.id});
        } else {
            result = article;
            keysToAdd[keysIndex] = article.id;
            keysIndex += 1;
        }
    }
    if (keysIndex > 0) {
        var buffer: [2048]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const allocator = fba.allocator();
        try unseenFilter.populate(allocator, keysToAdd[0..keysIndex]);
    }
    return result;
}

fn fetchUpdate(allocator: std.mem.Allocator, curl_module: *const wcurl.Curl, config: *const bin.FetchParams, alreadySeenFilter: *fastfilter.BinaryFuse(u32)) !?bin.Announce {
    var latestPerCatalog = bin.fetchDecodeLatestInEveryCatalog(allocator, &curl_module.easy, config) catch |errz| {
        std.log.err("F: {s} with {?s}", .{ @errorName(errz), curl_module.proxyManager.getCurrentProxy() });
        metrics.err();
        if (errz == wcurl.CurlError.OperationTimedout) {
            metrics.timeout();
        } else if (errz == wcurl.CurlError.SSLConnectError or errz == wcurl.CurlError.SSLCertProblem) {
            metrics.sslError();
        }
        return error.FetchError;
    };
    var unseen: ?bin.Announce = null;
    defer {
        for (latestPerCatalog.items) |article| {
            if (unseen == null or article.id != unseen.?.id) {
                article.deinit();
            }
        }
        latestPerCatalog.deinit(allocator);
    }
    unseen = try filterLastUnseenInList(&latestPerCatalog, alreadySeenFilter);
    std.log.debug("Found {d} articles in, {s} new", .{ latestPerCatalog.items.len, if (unseen != null) "1" else "nothing" });
    return unseen;
}

fn resolve_address(address_with_port: []const u8) !std.net.Address {
    var iterator = std.mem.tokenizeScalar(u8, address_with_port, ':');
    const address = iterator.next() orelse return error.AddressParseFailed;
    const port = try std.fmt.parseInt(u16, iterator.next() orelse return error.AddressParseFailed, 0);
    return try std.net.Address.parseIp(address, port);
}

test {
    std.testing.refAllDecls(@This());
}
