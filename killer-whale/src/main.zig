const std = @import("std");
//const yaml = @import("ymlz");
const yazap = @import("yazap");
//const zeit = @import("zeit");
const builtin = @import("builtin");
const bin = @import("binance.zig");
const wcurl = @import("curl.zig");
const messaging = @import("messaging.zig");

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
        try message.addArg(Arg.singleValueOption("port", 'p', "destination port"));
        var punch = cmd_parser.createCommand("punch", "Punch and exit");
        try punch.addArg(Arg.singleValueOption("id", 'i', "announce ID"));
        try punch.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        var root = cmd_parser.rootCommand();
        try root.addArg(Arg.singleValueOption("catalog", 'c', "catalog ID"));
        try root.addSubcommand(punch);
        try root.addSubcommand(message);
        const matches = try cmd_parser.parseProcess();

        if (matches.subcommandMatches("message")) |message_cmd_matches| {
            const address = message_cmd_matches.getSingleValue("address") orelse "127.0.0.1";
            const port = message_cmd_matches.getSingleValue("port") orelse "8081";
            const tokens: []const []const u8 = &.{
                "hello",
                "world",
            };

            const ip = try std.net.Address.parseIp(address, try std.fmt.parseInt(u16, port, 0));
            _ = try messaging.send_announce(allocator, ip, &tokens);
            return;
        } else if (matches.subcommandMatches("punch")) |punch_cmd| {
            const id = punch_cmd.getSingleValue("id") orelse return;
            const catalog = punch_cmd.getSingleValue("catalog") orelse return;
            const curl_module = try wcurl.Curl.init(allocator);
            defer curl_module.deinit();
            const easy = curl_module.easy;
            const update = try bin.punch_announce_update(allocator, &easy, catalog, try std.fmt.parseInt(u32, id, 0));
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

    const iterations = if (is_debug) 1 else 100;
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
        const result = bin.wait_for_total_change(allocator, &easy, .{ .catalog_id = catalog, .tld = "com", .seed = seed }, &latestTotal) catch |errz| none: {
            std.log.err("fail {d}: {s}", .{ latestTotal, @errorName(errz) });
            break :none null;
        };
        if (result) |change| {
            defer change.deinit();
            const new_total = change.value.id;
            try curl_module.set_trim_body(2000);
            const maybe_update = try bin.punch_announce_update(allocator, &easy, catalog, new_total);
            if (maybe_update) |update| {
                defer update.deinit();
                std.log.info("Found update {d}: {d} {s}", .{ std.time.microTimestamp(), update.value.id, update.value.response });
                const tokens: []const []const u8 = &.{
                    "hello",
                    "world",
                };
                const address = try std.net.Address.parseIp("45.76.156.26", 8081);
                const bytes_count = messaging.send_announce(allocator, address, &tokens) catch 0;
                std.log.info("Announce sent with status: {d}. Sleeping...", .{bytes_count});
                std.time.sleep(std.time.ns_per_s * std.time.s_per_hour); // nothing to do here
            } else {
                std.log.warn("Punching was not successfull: {d}", .{new_total});
            }
        } else {
            std.time.sleep(std.time.ns_per_s * 1);
        }
    }
    //try bin.wait_for_announcement(allocator, seed);
}

test {
    std.testing.refAllDecls(@This());
}
