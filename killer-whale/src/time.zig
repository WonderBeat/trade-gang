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

/// Sleeps until the current UTC time falls within the specified hour range.
/// If the current hour is outside the [fromHour, toHour) range, the function
/// will sleep for the remaining hours until toHour is reached.
///
/// Parameters:
///   fromHour: The starting hour of the allowed range (inclusive)
///   toHour: The ending hour of the allowed range (exclusive)
///
/// Returns:
///   void - continues execution once the time is within range
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
