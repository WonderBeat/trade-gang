const std = @import("std");
//const yaml = @import("ymlz");
const yazap = @import("yazap");
//const zeit = @import("zeit");
const builtin = @import("builtin");
const bin = @import("binance.zig");
const wcurl = @import("curl.zig");
const messaging = @import("messaging.zig");
const parse = @import("parsers.zig");

const App = yazap.App;
const Arg = yazap.Arg;

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
        var root = cmd_parser.rootCommand();
        try root.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        try root.addSubcommand(punch);
        try root.addSubcommand(message);
        const matches = try cmd_parser.parseProcess();

        if (matches.subcommandMatches("message")) |message_cmd_matches| {
            const address = message_cmd_matches.getSingleValue("address") orelse "127.0.0.1:8081";
            const title = "Binance Will Delist ANT, MULTI, VAI, XMR on 2024-02-20";
            const tokens = try parse.extract_coins_from_text(allocator, title);
            defer allocator.free(tokens);
            const ip = try resolve_address(address);
            _ = try messaging.send_announce(allocator, ip, &tokens, std.time.milliTimestamp(), false);
            return;
        } else if (matches.subcommandMatches("punch")) |punch_cmd| {
            const id = punch_cmd.getSingleValue("id") orelse return;
            const catalog = punch_cmd.getSingleValue("catalog") orelse return;
            const curl_module = try wcurl.Curl.init(allocator);
            defer curl_module.deinit();
            const easy = curl_module.easy;
            const update = try bin.punch_announce_update(allocator, &easy, catalog, "com", try std.fmt.parseInt(u32, id, 0));
            if (update) |result| {
                defer result.deinit();
                std.log.info("Punched with result {d} -> {s}", .{ result.value.id, result.value.response });
            }
            return;
        }
    }

    // const japan = try zeit.loadTimeZone(allocator, .@"Asia/Tokyo", null);
    // defer japan.deinit();
    // const now = try zeit.instant(.{});
    // const japan_time = now.in(&japan);
    // try japan_time.time().strftime(std.io.getStdOut().writer(), "%Y-%m-%d %H:%M:%S %Z");
    //
    const catalog = std.posix.getenv("CATALOG") orelse "93";
    const tld = std.posix.getenv("TLD") orelse "com";
    const send_announce_address = try resolve_address(std.posix.getenv("ANNOUNCE_DELIVERY_ADDR") orelse "127.0.0.1:8081");
    std.log.debug("Catalog {s} home address {}", .{ catalog, send_announce_address });

    const iterations = if (is_debug) 2 else 100;
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    var latestTotal: u32 = 0;
    for (0..iterations) |_| {
        const seed = std.Random.intRangeAtMost(prng.random(), usize, 0, 10000);
        const curl_module = try wcurl.Curl.init(allocator);
        defer curl_module.deinit();
        const easy = curl_module.easy;

        try curl_module.set_trim_body(350);
        const config = bin.ChangeWaitingParams{ .catalog_id = catalog, .tld = tld, .seed = seed };
        const result = bin.wait_for_total_change(allocator, &easy, config, &latestTotal) catch |errz| none: {
            std.log.err("fail {d}: {s}", .{ latestTotal, @errorName(errz) });
            break :none null;
        };
        if (result) |change| {
            defer change.deinit();
            const new_total = change.value.id;
            try curl_module.set_trim_body(3000);
            const maybe_update = try bin.punch_announce_update(allocator, &easy, catalog, tld, new_total);
            if (maybe_update) |update| no_update: {
                defer update.deinit();
                std.log.info("Found update {d} >>>> {s}", .{ update.value.id, update.value.response });
                const announce = parse.extract_announce_content(update.value.response) orelse {
                    std.log.warn("Mailformed announce {s}", .{update.value.response});
                    break :no_update;
                };
                if (announce.id != update.value.id and announce.title.len < 5 and announce.ts > 0) {
                    std.log.warn("Mailformed announce {d}:{d} {s}({d})", .{ announce.id, update.value.id, announce.title, announce.ts });
                    break :no_update;
                }
                const ts = std.time.timestamp();
                std.log.info("Timestamps: ours {d}, theirs {d}, diff: {d}", .{ ts, announce.ts, ts - @divFloor(announce.ts, 1000) });
                const coins = try parse.extract_coins_from_text(allocator, announce.title);
                defer allocator.free(coins);
                const is_delist = (std.ascii.indexOfIgnoreCase(announce.title, "will delist") orelse 0) > 0;
                if (coins.len == 0 and is_delist) {
                    std.log.warn("No coins found {d} {s}", .{ announce.id, announce.title });
                    break :no_update;
                }
                const bytes_count = messaging.send_announce(allocator, send_announce_address, &coins, announce.ts, is_delist) catch 0;
                std.log.info("Announce sent {d} ({d} bytes). Sleeping...", .{ update.value.id, bytes_count });
                if (is_delist) {
                    std.log.info("DELISTING", .{});
                    std.time.sleep(std.time.ns_per_s * std.time.s_per_hour * 24); // nothing to do here
                }
            } else {
                std.log.err("Punching was not successfull: {d}", .{new_total});
            }
        } else {
            std.time.sleep(std.time.ns_per_s * 1);
        }
    }
    //try bin.wait_for_announcement(allocator, seed);
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
