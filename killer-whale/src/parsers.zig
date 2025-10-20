const std = @import("std");
const binance = @import("binance.zig");
const expect = std.testing.expect;

const ParsedAnnounce = struct { id: u32, title: []const u8, ts: i64 };

// detects if title contains listing or delisting
// returns confidence level
// 0 means not found
pub fn isAnnounceImportant(title: []const u8) u8 {
    const has_list = greater_than_zero(std.ascii.indexOfIgnoreCase(title, " will list"));
    const has_delist = greater_than_zero(std.ascii.indexOfIgnoreCase(title, " will delist"));
    const has_binance: u8 = if (std.ascii.startsWithIgnoreCase(title, "binance")) 1 else 0;
    const has_vote = greater_than_zero(std.ascii.indexOfIgnoreCase(title, "vote "));
    const has_year = greater_than_zero(std.ascii.indexOfIgnoreCase(title, " 20"));
    return has_list + has_delist + has_binance + has_vote + has_year;
}

inline fn greater_than_zero(value: ?usize) u8 {
    if (value == null or value.? == 0) {
        return 0;
    } else {
        return 1;
    }
}

test "detect delisting" {
    try expect(isAnnounceImportant("Binance Will Delist CVP, EPX, FOR, LOOM, REEF, VGX on 2024-08-26") == 3);

    try expect(isAnnounceImportant("Binance Announced the First Batch of Vote to Delist Results and Will Delist BADGER, BAL, BETA, CREAM, CTXC, ELF, FIRO, HARD, NULS, PROS, SNT, TROY, UFT, VIDT on 2025-04-16") == 4);
    try expect(isAnnounceImportant("Binance Announced the First Batch of Vote to Delist Results and Will Delist BADGER, BAL, BETA, CREAM, CTXC, ELF, FIRO, HARD, NULS, PROS, SNT, TROY, UFT, VIDT on 2025-04-16") == 4);
    try expect(isAnnounceImportant("Binance Announced the First Batch of Vote to List Results and Will List Mubarak (MUBARAK), CZ'S Dog (BROCCOLI714), Tutorial (TUT), and Banana For Scale (BANANAS31) With Seed Tags Applied") == 3);
}

pub fn extractCoins(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
    var list = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    defer list.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        if (std.ascii.isUpper(text[i])) {
            var j: usize = i;
            while (j < text.len and (std.ascii.isUpper(text[j]) or std.ascii.isDigit(text[j]))) {
                j += 1;
            }
            const coin = text[i..j];
            const in_the_middle = i > 0 and j < text.len;
            if (in_the_middle) {
                const has_no_chars_on_side = !std.ascii.isAlphabetic(text[i - 1]) and !std.ascii.isAlphabetic(text[j]);
                if (has_no_chars_on_side and coin.len >= 3 and coin.len <= 12) {
                    try list.append(allocator, coin);
                    i = j;
                } else {
                    i += 1;
                }
            } else {
                i += 1;
            }
        } else {
            i += 1;
        }
    }

    return try list.toOwnedSlice(allocator);
}

test "extract coins from title 1" {
    const alloc = std.testing.allocator;
    const title = "Binance Will Delist ANT, MULTI, VAI, XMR on 2024-02-20";
    const result = try extractCoins(alloc, title);
    defer alloc.free(result);
    try expect(std.mem.eql(u8, result[0], "ANT"));
    try expect(std.mem.eql(u8, result[1], "MULTI"));
    try expect(std.mem.eql(u8, result[2], "VAI"));
    try expect(std.mem.eql(u8, result[3], "XMR"));
}

test "extract coins from title 2" {
    const alloc = std.testing.allocator;
    const title = "Binance Will Delist CVP, EPX, FOR, LOOM, REEF, VGX on 2024-08-26";
    const result = try extractCoins(alloc, title);
    defer alloc.free(result);
    try expect(std.mem.eql(u8, result[0], "CVP"));
    try expect(std.mem.eql(u8, result[1], "EPX"));
    try expect(std.mem.eql(u8, result[2], "FOR"));
    try expect(std.mem.eql(u8, result[3], "LOOM"));
    try expect(std.mem.eql(u8, result[4], "REEF"));
    try expect(std.mem.eql(u8, result[5], "VGX"));
}

test "extract coins from title 3" {
    const alloc = std.testing.allocator;
    const title =
        "Binance Announced the First Batch of Vote to List Results and Will List Mubarak (MUBARAK), CZ'S Dog (BROCCOLI714), Tutorial (TUT), and Banana For Scale (BANANAS31) With Seed Tags Applied";
    const result = try extractCoins(alloc, title);
    defer alloc.free(result);
    try expect(std.mem.eql(u8, result[0], "MUBARAK"));
    try expect(std.mem.eql(u8, result[1], "BROCCOLI714"));
    try expect(std.mem.eql(u8, result[2], "TUT"));
    try expect(std.mem.eql(u8, result[3], "BANANAS31"));
}

test "extract coins from title 4" {
    const alloc = std.testing.allocator;
    const title =
        "Introducing Babylon (BABY) on Binance HODLer Airdrops! Earn BABY With Retroactive BNB Simple Earn Subscriptions";
    const result = try extractCoins(alloc, title);
    defer alloc.free(result);
    try expect(std.mem.eql(u8, result[0], "BABY"));
    try expect(std.mem.eql(u8, result[1], "BABY"));
    try expect(std.mem.eql(u8, result[2], "BNB"));
}

pub const Tld = enum {
    Info,
    Com,
    Me,

    pub fn to_string(self: Tld) []const u8 {
        return switch (self) {
            .Info => "info",
            .Com => "com",
            .Me => "me",
        };
    }

    pub fn from_string(s: []const u8) ?Tld {
        if (std.mem.eql(u8, s, "info")) {
            return .Info;
        } else if (std.mem.eql(u8, s, "com")) {
            return .Com;
        } else if (std.mem.eql(u8, s, "me")) {
            return .Me;
        } else {
            return null;
        }
    }

    pub fn to_i32(self: Tld) i32 {
        return @intFromEnum(self);
    }

    pub fn from_i32(i: i32) ?Tld {
        return switch (i) {
            0 => .Info,
            1 => .Com,
            2 => .Me,
            else => null,
        };
    }
};

test "Tld to_string" {
    try expect(std.mem.eql(u8, Tld.Info.to_string(), "info"));
    try expect(std.mem.eql(u8, Tld.Com.to_string(), "com"));
    try expect(std.mem.eql(u8, Tld.Me.to_string(), "me"));
}

test "Tld to_i32" {
    try expect(Tld.Info.to_i32() == 0);
    try expect(Tld.Com.to_i32() == 1);
    try expect(Tld.Me.to_i32() == 2);
}
