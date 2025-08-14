const std = @import("std");
const zeit = @import("zeit");

pub fn sleepWhileNotInRangeUTC(fromHour: usize, toHour: usize) !void {
    var now = (try zeit.instant(.{})).time();
    if (now.hour < fromHour or now.hour >= toHour) {
        std.log.info("Sleeping until {d} -> {d} ({d})", .{ fromHour, toHour, now.hour });
    }
    while (now.hour < fromHour or now.hour >= toHour) {
        std.time.sleep(std.time.ns_per_min * 10);
        now = (try zeit.instant(.{})).time();
    }
}
