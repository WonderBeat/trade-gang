const std = @import("std");
const builtin = @import("builtin");

const yazap = @import("yazap");
const App = yazap.App;
const Arg = yazap.Arg;

const bin = @import("binance.zig");
const messaging = @import("messaging.zig");
const mqtt = @import("mqtt.zig");
const parse = @import("parsers.zig");
const wcurl = @import("curl.zig");
const prometheus = @import("prometheus.zig");
const proxy = @import("proxy-manager.zig");

const BINANCE_TOPIC = if (builtin.mode == .Debug) "binance-test" else "binance";

//const yaml = @import("ymlz");
//const zeit = @import("zeit");
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
        try prometheus.initializeMetrics(.{ .prefix = "killa_" });
    }

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };
    if (is_debug) {
        var cmd_parser = App.init(allocator, "killer-whale", "Find and Eliminate");
        defer cmd_parser.deinit();
        var message = cmd_parser.createCommand("message", "send announce and exit");
        try message.addArg(Arg.singleValueOption("address", 'a', "destination address"));
        var punch = cmd_parser.createCommand("punch", "Punch and exit");
        try punch.addArg(Arg.singleValueOption("id", 'i', "announce ID"));
        try punch.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        try punch.addArg(Arg.singleValueOption("anonymizer", 'a', "anonymizer address"));
        try punch.addArg(Arg.singleValueOption("tld", 't', "TLD"));
        var avalance = cmd_parser.createCommand("avalance", "avalance and exit");
        try avalance.addArg(Arg.singleValueOption("mqtt", 'm', "mqtt address"));
        try avalance.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        try avalance.addArg(Arg.singleValueOption("total", 't', "id to punch for"));
        try avalance.addArg(Arg.singleValueOption("tld", 't', "TLD"));
        var root = cmd_parser.rootCommand();
        try root.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        try root.addSubcommand(punch);
        try root.addSubcommand(message);
        try root.addSubcommand(avalance);
        const matches = try cmd_parser.parseProcess();

        if (matches.subcommandMatches("message")) |message_cmd_matches| {
            const address = message_cmd_matches.getSingleValue("address") orelse "127.0.0.1:8081";
            const title = "Binance Will Delist ANT, MULTI, VAI, XMR on 2024-02-20";
            const tokens = try parse.extract_coins_from_text(allocator, title);
            defer allocator.free(tokens);
            const ip = try resolve_address(address);
            const bytes_sent = try messaging.send_announce(allocator, ip, &tokens, 77777, 69, &"LOVE YOU", false);
            std.log.debug("Msg sent {d} bytes", .{bytes_sent});
            return;
        } else if (matches.subcommandMatches("punch")) |punch_cmd| {
            //const id = punch_cmd.getSingleValue("id") orelse return;
            const address = punch_cmd.getSingleValue("anonymizer") orelse null;
            const tld = punch_cmd.getSingleValue("tld") orelse "me";
            const catalog = try std.fmt.parseInt(u16, punch_cmd.getSingleValue("catalog") orelse return, 0);
            const curl_module = try wcurl.Curl.init(allocator);
            defer curl_module.deinit();
            const easy = curl_module.easy;

            const config = bin.FetchSingleParams{
                .catalogId = catalog,
                .tld = tld,
                .seed = 1,
                .anonymizer = address,
            };
            const update = try bin.fetchPage(allocator, &easy, &config);
            if (update) |result| {
                std.log.info("Punched with result {s}...", .{result.body[0..300]});
                result.clear(allocator);
            }
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

    var latest_total: u32 = 0;
    const curl_module = try wcurl.Curl.init(allocator);
    defer curl_module.deinit();
    const client = try mqtt.Mqtt.init(allocator, mqtt_address);
    _ = try client.subscribe(BINANCE_TOPIC);
    defer {
        client.deinit();
    }
    const easy = curl_module.easy;
    if (anonymizer == null) {
        if (std.posix.getenv("FETCH_URL")) |url| {
            curl_module.setProxyDownloadUrl(url);
            try curl_module.exchangeProxy();
        }
    }

    if (std.posix.getenv("PASSIVE")) |_| {
        std.log.info("Passive mode ON: mothership {}, mqtt {s}", .{ send_announce_address, mqtt_address });
        for (0..1111) |_| {
            if (try passive_punch_mode(allocator, client, curl_module, 14000, anonymizer, 1, send_announce_address, null)) |_| {
                std.time.sleep(std.time.ns_per_s * 30); // cooldown
                return;
            }
            _ = try client.ping();
        }
        return;
    }
    const iterations = if (is_debug) 3 else (20 + prng.random().intRangeAtMost(usize, 0, 30));
    const catalogConfig = switch (catalog) {
        161 => bin.catalogPages.delisting,
        48 => bin.catalogPages.listing,
        else => bin.catalogPages.default,
    };
    for (0..iterations) |_| {
        const seed = std.Random.intRangeAtMost(prng.random(), usize, 0, 999999);
        try curl_module.set_trim_body(0, 400);
        const result: ?u32 = found: {
            //var config = bin.ChangeWaitingParams{ .catalog_id = catalog, .tld = tld, .seed = seed, .anonymizer = anonymizer };

            var config = bin.FetchSingleParams{ .catalogId = catalog, .tld = tld, .seed = seed, .anonymizer = anonymizer };
            for (1..iterations) |iter| {
                prometheus.latest(latest_total);
                var time_spent_query = std.time.milliTimestamp();
                config.seed = seed + iter;
                config.page = catalogConfig.atOffset(config.seed);
                const fetchResult = bin.fetchPage(allocator, &easy, &config) catch |errz| none: {
                    const time_spent_err = std.time.milliTimestamp() - time_spent_query;
                    std.log.err("F {d}: {s} with {?s} in {d}ms", .{ latest_total, @errorName(errz), curl_module.proxyManager.getCurrentProxy(), time_spent_err });
                    prometheus.err();
                    if (errz == wcurl.CurlError.OperationTimedout) {
                        prometheus.timeout();
                    } else if (errz == wcurl.CurlError.SSLConnectError or errz == wcurl.CurlError.SSLCertProblem) {
                        prometheus.sslError();
                    }
                    break :none null;
                };
                const success = fetchResult != null;
                time_spent_query = std.time.milliTimestamp() - time_spent_query;
                if (success) {
                    prometheus.hit();
                    if (curl_module.latest_query_metrics()) |metrics| {
                        const execution_time_ms = metrics.total_time - metrics.pretransfer_time;
                        prometheus.latency(@intCast(execution_time_ms));
                    }
                    try curl_module.exchangeProxy();
                } else {
                    if (try curl_module.dropCurrentProxy() == 0) {
                        try curl_module.exchangeProxy();
                    }
                }
                if (fetchResult) |fetched| {
                    defer fetched.clear(allocator);
                    if (fetched.extractTotal()) |fetched_total| {
                        if (fetched_total > latest_total) {
                            if (latest_total != 0) {
                                std.log.info("Catalog update signal {d}, for {s} / {?s}", .{ fetched_total, fetched.url, curl_module.proxyManager.getCurrentProxy() });
                                for (0..5) |nextPageIndex| {
                                    config.page = catalogConfig.atOffset(config.seed + nextPageIndex);
                                    const nextPage = bin.fetchPage(allocator, &easy, &config) catch null;
                                    if (nextPage) |np| {
                                        defer np.clear(allocator);
                                        std.log.debug("Next page total: {?d} for {s} / {?s}", .{ np.extractTotal(), np.url, curl_module.proxyManager.getCurrentProxy() });
                                    } else {
                                        try curl_module.exchangeProxy();
                                    }
                                }
                                break :found fetched_total;
                            }
                            latest_total = fetched_total;
                            std.log.debug("Total set to {d}", .{fetched_total});
                        }
                    } else {
                        std.log.err("Catalog update total not found {s}", .{fetched.body});
                    }
                }
                if (iter % 5 == 0) {
                    try client.ping();
                }
                if (iter % 13 == 0) {
                    std.log.info("latest total {d}", .{latest_total});
                    const file = try std.fs.cwd().createFile("metrics.prometheus", .{});
                    defer file.close();
                    try prometheus.writeMetrics(file.writer());
                }
                const sleep_max_ms: i32 = if (success) 1500 else 200;
                const sleep_remaning: i32 = @intCast(@max(100, sleep_max_ms - time_spent_query)); // min 50ms sleep

                if (try passive_punch_mode(
                    allocator,
                    client,
                    curl_module,
                    sleep_remaning,
                    anonymizer,
                    seed,
                    send_announce_address,
                    parse.Tld.from_string(tld).?,
                )) |update| {
                    if (update.catalog == catalog) {
                        latest_total = update.total;
                    }
                    try client.ping();
                    std.time.sleep(std.time.ns_per_s * 15); // cooldown
                    try client.ping();
                }
            }
            break :found null;
        };

        if (result) |new_total| {
            send_mqtt_alert(client, catalog, new_total, parse.Tld.from_string(tld).?) catch |errz| {
                std.log.warn("Mqtt send error {s}", .{@errorName(errz)});
            };
            const config = PunchParams{ .catalogId = catalog, .tld = tld, .anonymizer = anonymizer, .seed = seed, .lastSeenTotal = new_total };
            const success = try punch_notify(allocator, curl_module, send_announce_address, &config);
            if (success) {
                std.log.info("Update found as a result of a signal with proxy: {?s}", .{curl_module.proxyManager.getCurrentProxy()});
            }
            latest_total = new_total;
        }

        try client.ping();
        std.time.sleep(std.time.ns_per_s * 1);
    }
    if (latest_total == 0) { // we have nothing to hunt for
        return;
    }
    std.log.info("Bruteforce something after {d}", .{latest_total});
    const seed = std.Random.intRangeAtMost(prng.random(), usize, 0, 999999);
    const config = PunchParams{ .catalogId = catalog, .tld = tld, .anonymizer = anonymizer, .seed = seed, .sleep = 1200, .iterations = if (is_debug) 5 else @intCast(40 + seed % 20), .lastSeenTotal = latest_total };
    const success = try punch_notify(allocator, curl_module, send_announce_address, &config);
    if (success) {
        std.log.info("Update was found with bruteforce with proxy: {?s}", .{curl_module.proxyManager.getCurrentProxy()});
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
    timeout: i32,
    anonymizer: ?[]const u8,
    seed: usize,
    send_announce_address: std.net.Address,
    overwrite_tld: ?parse.Tld,
) !?struct { catalog: u16, total: u32 } {
    if (try wait_for_message(allocator, mqtt_cli, timeout)) |alert| {
        const alert_tld = (overwrite_tld orelse alert.tld).to_string();
        std.log.info("Cooperative punching activated {d}:{d}:{s}", .{ alert.catalog, alert.total, alert_tld });
        const conf = PunchParams{
            .catalogId = alert.catalog,
            .tld = alert_tld,
            .seed = seed,
            .anonymizer = anonymizer,
            .lastSeenTotal = alert.total,
        };
        _ = try punch_notify(
            allocator,
            curl_cli,
            send_announce_address,
            &conf,
        );
        return .{ .catalog = alert.catalog, .total = alert.total };
    }
    return null;
}

fn wait_for_message(
    allocator: std.mem.Allocator,
    mqtt_cli: *mqtt.Mqtt,
    timeout: i32,
) !?struct { catalog: u16, total: u32, tld: parse.Tld } {
    if (try mqtt_cli.receive_string(timeout)) |alert| {
        defer allocator.free(alert);
        var iterator = std.mem.splitScalar(u8, alert, '|');
        const alert_catalog = try std.fmt.parseInt(u16, iterator.first(), 0);
        const alert_latestTotal: u32 = try std.fmt.parseInt(u32, iterator.next().?, 0);
        const tld = parse.Tld.from_string(iterator.next().?) orelse return error.MqttMsgErr;
        return .{ .catalog = alert_catalog, .total = alert_latestTotal, .tld = tld };
    }
    return null;
}

const PunchParams = struct {
    catalogId: u16,
    tld: []const u8,
    seed: usize,
    anonymizer: ?[]const u8,
    iterations: u32 = 500,
    sleep: u32 = 100,
    lastSeenTotal: u32,
    proxyManager: ?proxy.ProxyManager = null,
};

fn punch_notify(allocator: std.mem.Allocator, curl_cli: *wcurl.Curl, announce_url: std.net.Address, config: *const PunchParams) !bool {
    try curl_cli.set_trim_body(0, 0);
    const easy = curl_cli.easy;
    var fetch_params = bin.FetchSingleParams{
        .catalogId = config.catalogId,
        .tld = config.tld,
        .seed = config.seed,
        .anonymizer = config.anonymizer,
    };
    const startSeed = fetch_params.seed;
    var maybe_update: ?bin.FetchResult = null;
    for (0..config.iterations) |iter| {
        var time_spent_query = std.time.milliTimestamp();

        fetch_params.seed = startSeed + iter;
        const pageSize: u16 = if ((fetch_params.seed ^ (config.seed << 2)) % 100 > 50) 50 else 10;
        fetch_params.page.size = pageSize;
        const result = bin.fetchPage(allocator, &easy, &fetch_params) catch |errz| not_found: {
            std.log.debug("PErr with {?s} {s}", .{ curl_cli.proxyManager.getCurrentProxy(), @errorName(errz) });
            _ = try curl_cli.dropCurrentProxy();
            prometheus.err();
            break :not_found null;
        };
        if (result) |data| {
            defer data.clear(allocator);
            if (data.extractTotal()) |total| {
                prometheus.hit();
                if (curl_cli.latest_query_metrics()) |metrics| {
                    const execution_time_ms = metrics.total_time - metrics.pretransfer_time;
                    prometheus.latency(@intCast(execution_time_ms));
                }
                if (total > config.lastSeenTotal) {
                    std.log.info("Punch success 🚀 {d}: {s}", .{ total, data.url });
                    maybe_update = data;
                    break;
                }
            } else {
                std.log.err("Total not found: {s}", .{data.body});
            }
        }
        if (iter % 13 == 0) {
            const file = try std.fs.cwd().createFile("metrics.prometheus", .{});
            defer file.close();
            try prometheus.writeMetrics(file.writer());
        }
        try curl_cli.exchangeProxy();
        time_spent_query = std.time.milliTimestamp() - time_spent_query;
        const sleep_remaning: u64 = @intCast(@max(50, config.sleep - time_spent_query));
        std.time.sleep(sleep_remaning * std.time.ns_per_ms);
    }
    if (maybe_update) |update| no_update: {
        defer update.clear(allocator);
        const updated_id = update.extractTotal() orelse {
            std.log.warn("No total in update {s}", .{update.url});
            break :no_update;
        };
        const announce = parse.extract_announce_content(update.body) orelse {
            std.log.warn("Mailformed announce {s}", .{update.url});
            break :no_update;
        };
        if (announce.title.len < 5 or announce.ts < 1000) {
            std.log.warn("Mailformed announce {d}:{d} {s}({d})", .{ announce.id, updated_id, announce.title, announce.ts });
            break :no_update;
        }
        const ts = std.time.timestamp();
        std.log.info("Timestamps: ours {d} announcement {d}, diff: {d}", .{ ts, announce.ts, ts - @divFloor(announce.ts, 1000) });
        const coins = try parse.extract_coins_from_text(allocator, announce.title);
        defer allocator.free(coins);
        const is_important = parse.listing_delisting(announce.title) >= 3;
        if (coins.len == 0 and is_important) {
            std.log.warn("No coins found {d} {s}", .{ announce.id, announce.title });
            break :no_update;
        }
        const bytes_count = messaging.send_announce(allocator, announce_url, &coins, announce.ts, config.catalogId, &announce.title, is_important) catch 0;
        std.log.info("Announce sent {d} ({d} bytes). Sleeping...", .{ updated_id, bytes_count });
        if (is_important) {
            std.log.info("🔴 Call to action sent", .{});
            std.time.sleep(std.time.ns_per_s * if (builtin.mode == .Debug) 1 else std.time.s_per_hour); // nothing to do here
        } else {
            std.time.sleep(std.time.ns_per_s * std.time.s_per_min * 1);
        }
    }
    return maybe_update != null;
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
