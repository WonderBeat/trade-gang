const std = @import("std");
const zeit = @import("zeit");

pub fn isTimeBetweenHours(instant: *const zeit.Instant, fromHour: u8, toHour: u8) bool {
    const now = instant.time();
    return now.hour >= fromHour and now.hour < toHour;
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
    var hoursSleepRemaning: i64 = isTimeBetweenHours(fromHour, toHour);
    if (hoursSleepRemaning > 0) {
        std.log.info("Sleeping until {d} -> {d} {d}", .{ fromHour, toHour, hoursSleepRemaning });
    }
    while (hoursSleepRemaning > 0) {
        std.time.sleep(std.time.ns_per_min * hoursSleepRemaning);
        hoursSleepRemaning = isTimeBetweenHours(fromHour, toHour);
    }
}

pub fn isWeekend(now: *const zeit.Instant) bool {
    const dayNum = @intFromEnum(zeit.weekdayFromDays(@divFloor(now.unixTimestamp(), std.time.s_per_day)));
    return dayNum == 0 or dayNum == 6;
}

const testing = std.testing;

test "parsing total response" {
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-29T08:00:00.000-0000",
            },
        });
        try std.testing.expect(!isWeekend(&iso));
    }
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-30T08:00:00.000-0000",
            },
        });
        try std.testing.expect(isWeekend(&iso));
    }
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-31T08:00:00.000-0000",
            },
        });
        try std.testing.expect(isWeekend(&iso));
    }
}
