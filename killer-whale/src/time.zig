const std = @import("std");
const zeit = @import("zeit");

// returns hours remaining to sleep or -1 if not in range
pub fn sleepRemaningHours(fromHour: u8, toHour: u8) !i64 {
    const now = (try zeit.instant(.{})).time();
    if (now.hour < fromHour or now.hour >= toHour) {
        return toHour - now.hour;
    }
    return -1;
}

pub fn sleepWhileNotInRangeUTC(fromHour: u8, toHour: u8) !void {
    var hoursSleepRemaning: i64 = sleepRemaningHours(fromHour, toHour);
    if (hoursSleepRemaning > 0) {
        std.log.info("Sleeping until {d} -> {d} {d}", .{ fromHour, toHour, hoursSleepRemaning });
    }
    while (hoursSleepRemaning > 0) {
        std.time.sleep(std.time.ns_per_min * hoursSleepRemaning);
        hoursSleepRemaning = sleepRemaningHours(fromHour, toHour);
    }
}
