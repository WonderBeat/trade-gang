const std = @import("std");
const expect = std.testing.expect;

const ParsedAnnounce = struct { id: u32, title: []const u8, ts: i64 };

pub fn extract_announce_content(body: []const u8) ?ParsedAnnounce {
    const id_needle = "\"id\":";
    const title_needle = "\"title\":\"";
    const release_date_needle = "\"releaseDate\":";

    const id_start_index = std.mem.indexOf(u8, body, id_needle) orelse return .{ .id = 0, .title = "", .ts = 0 };
    const id_start = id_start_index + id_needle.len;
    var id_end: usize = id_start;
    while (id_end < body.len and std.ascii.isDigit(body[id_end])) {
        id_end += 1;
    }
    const id_slice = body[id_start..id_end];
    const id = std.fmt.parseInt(u32, id_slice, 10) catch return null;

    const title_start_index = std.mem.indexOf(u8, body, title_needle) orelse return null;
    const title_start = title_start_index + title_needle.len;
    var title_end: usize = title_start;
    while (title_end < body.len and body[title_end] != '"') {
        title_end += 1;
    }
    const title = body[title_start..title_end];

    const date_start_index = std.mem.indexOf(u8, body, release_date_needle) orelse return null;
    const date_start = date_start_index + release_date_needle.len;
    var date_end: usize = date_start;
    while (date_end < body.len and std.ascii.isDigit(body[date_end])) {
        date_end += 1;
    }
    const date = std.fmt.parseInt(i64, body[date_start..date_end], 0) catch return null;

    return .{ .id = id, .title = title, .ts = date };
}

test "extract announce from response" {
    const response = "{\"code\":\"000000\",\"message\":null,\"messageDetail\":null,\"data\":{\"catalogs\":[{\"catalogId\":161,\"parentCatalogId\":null,\"icon\":\"https://public.bnbstatic.com/image/cms/content/body/202202/ad416a7598c8327ee59a6052c001c9b9.png\",\"catalogName\":\"Delisting\",\"description\":null,\"catalogType\":1,\"total\":252,\"articles\":[{\"id\":207063,\"code\":\"e2fcd2c945654c8d832395335429403e\",\"title\":\"Binance Will Delist CVP, EPX, FOR, LOOM, REEF, VGX on 2024-08-26\",\"type\":1,\"releaseDate\":1723446011329},{\"id\":206836,\"code\":\"e633a048a38a44c29828a441e4c4dac2\",\"title\":\"Notice of Removal of Spot Trading Pairs - 2024-08-02\",\"type\":1,\"releaseDate\":1722409208662}],\"catalogs\":[]}]},\"success\":true}";
    const result = extract_announce_content(response) orelse unreachable;
    try expect(result.id == 207063);
    try expect(result.ts == 1723446011329);
    try expect(std.ascii.eqlIgnoreCase(result.title, "Binance Will Delist CVP, EPX, FOR, LOOM, REEF, VGX on 2024-08-26"));
}

pub fn extract_coins_from_text(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (std.ascii.isUpper(text[i])) {
            var j: usize = i;
            while (j < text.len and std.ascii.isUpper(text[j])) {
                j += 1;
            }
            const coin = text[i..j];
            if (coin.len >= 2 and coin.len <= 5) {
                try list.append(coin);
                i = j;
            } else {
                i += 1;
            }
        } else {
            i += 1;
        }
    }

    return list.toOwnedSlice();
}

test "extract coins from title 1" {
    const alloc = std.testing.allocator;
    const title = "Binance Will Delist ANT, MULTI, VAI, XMR on 2024-02-20";
    const result = try extract_coins_from_text(alloc, title);
    defer alloc.free(result);
    try expect(std.mem.eql(u8, result[0], "ANT"));
    try expect(std.mem.eql(u8, result[1], "MULTI"));
    try expect(std.mem.eql(u8, result[2], "VAI"));
    try expect(std.mem.eql(u8, result[3], "XMR"));
}

test "extract coins from title 2" {
    const alloc = std.testing.allocator;
    const title = "Binance Will Delist CVP, EPX, FOR, LOOM, REEF, VGX on 2024-08-26";
    const result = try extract_coins_from_text(alloc, title);
    defer alloc.free(result);
    try expect(std.mem.eql(u8, result[0], "CVP"));
    try expect(std.mem.eql(u8, result[1], "EPX"));
    try expect(std.mem.eql(u8, result[2], "FOR"));
    try expect(std.mem.eql(u8, result[3], "LOOM"));
    try expect(std.mem.eql(u8, result[4], "REEF"));
    try expect(std.mem.eql(u8, result[5], "VGX"));
}
