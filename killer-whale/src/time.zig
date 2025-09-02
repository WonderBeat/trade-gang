const std = @import("std");
const zeit = @import("zeit");

pub fn isTimeBetweenHours(instant: *const zeit.Instant, fromHour: u8, toHour: u8) bool {
    const now = instant.time();
    return now.hour >= fromHour and now.hour < toHour;
}

pub fn isWeekend(now: *const zeit.Instant) bool {
    const dayNum = @intFromEnum(zeit.weekdayFromDays(@divFloor(now.unixTimestamp(), std.time.s_per_day)));
    return dayNum == 0 or dayNum == 6;
}

const testing = std.testing;

test "isWeekend" {
    // Aug 29 2025 is Friday (weekday 5) - not a weekend
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-29T08:00:00.000-0000",
            },
        });
        try std.testing.expect(!isWeekend(&iso));
    }

    // Aug 30 2025 is Saturday (weekday 6) - weekend
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-30T08:00:00.000-0000",
            },
        });
        try std.testing.expect(isWeekend(&iso));
    }

    // Aug 31 2025 is Sunday (weekday 0) - weekend
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-31T08:00:00.000-0000",
            },
        });
        try std.testing.expect(isWeekend(&iso));
    }
}

test "isTimeBetweenHours" {
    // Test time within range
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-29T10:30:00.000-0000",
            },
        });
        try std.testing.expect(isTimeBetweenHours(&iso, 9, 12));
    }

    // Test time at lower boundary
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-29T09:00:00.000-0000",
            },
        });
        try std.testing.expect(isTimeBetweenHours(&iso, 9, 12));
    }

    // Test time at upper boundary (should be false as range is [from, to))
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-29T12:00:00.000-0000",
            },
        });
        try std.testing.expect(!isTimeBetweenHours(&iso, 9, 12));
    }

    // Test time before range
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-29T08:30:00.000-0000",
            },
        });
        try std.testing.expect(!isTimeBetweenHours(&iso, 9, 12));
    }

    // Test time after range
    {
        const iso = try zeit.instant(.{
            .source = .{
                .iso8601 = "2025-08-29T15:30:00.000-0000",
            },
        });
        try std.testing.expect(!isTimeBetweenHours(&iso, 9, 12));
    }
}
