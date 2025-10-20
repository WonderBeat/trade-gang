const std = @import("std");
const expect = std.testing.expect;
const http = std.http;
const ArenaAllocator = std.heap.ArenaAllocator;
const builtin = @import("builtin");
const proxy = @import("proxy-manager.zig");

const curl = @import("curl");

const files = @import("file/files.zig");
const messaging = @import("messaging.zig");
const page = @import("page.zig");
const wcurl = @import("curl.zig");
const simdjzon = @import("simdjzon");

pub fn http_get(allocator: std.mem.Allocator, client: *const curl.Easy, url: []const u8) ![]const u8 {
    var response = rsp: {
        const urlZ: [:0]u8 = try allocator.allocSentinel(u8, url.len, 0);
        @memcpy(urlZ, url);
        defer allocator.free(urlZ);
        break :rsp try wcurl.get(allocator, client, urlZ);
    };
    defer response.deinit(allocator);
    if (response.status_code < 200 or response.status_code >= 300) {
        std.log.err("req failed with {d} for URL: {s}", .{ response.status_code, url });
        return error.StatusCodeErr;
    }
    var headerIterator =
        try response.curl_response.iterateHeaders(.{});
    while (try headerIterator.next()) |header| {
        if (isCacheHit(&header)) {
            return NetworkError.CacheHit;
        }
    }

    const body_buffer = response.body orelse return error.NoBody;
    if (body_buffer.capacity == 0) {
        std.log.warn("NB: {d}", .{response.status_code});
        return error.NoBody;
    }
    return try allocator.dupe(u8, body_buffer.items);
}

pub fn http_post(allocator: std.mem.Allocator, client: *const curl.Easy, url: []const u8, content: []const u8) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 2000);
    defer buf.deinit(allocator);
    const response = rsp: {
        errdefer buf.deinit(allocator);
        const urlZ: [:0]u8 = try allocator.allocSentinel(u8, url.len, 0);
        @memcpy(urlZ, url);
        defer allocator.free(urlZ);
        try client.setWritedata(&buf);
        try client.setUrl(urlZ);
        try client.setPostFields(content);
        break :rsp try client.perform();
    };
    if (response.status_code < 200 or response.status_code >= 300) {
        std.log.err("POST failed with {d} for URL: {s}", .{ response.status_code, url });
        return error.StatusCodeErr;
    }
    if (buf.capacity == 0) {
        std.log.warn("NB: {d}", .{response.status_code});
        return error.NoBody;
    }
    return try allocator.dupe(u8, buf.items);
}

const available_page_sizes = [_]u32{ 50, 20, 15, 10, 5, 3, 2 };

const templateUrlApex = "https://www.binance.{s}/bapi/apex/v1/public/apex/cms/article/list/query?type=1&";
const templateUrlComposite = "https://www.binance.{s}/bapi/composite/v1/public/cms/article/catalog/list/query?";
const templateUrlGlobal = "https://www.binance.{s}/bapi/apex/v1/public/apex/cms/article/list/query?pageNo={s}0x{s}{x}&type=1&pageSize={d}&lan={d}";

const templateUrlDebug = "http://127.0.0.1:8765/{s}/";
const templateUrl = "{s}pageNo=0x{x}&pageSize={d}&catalogId={s}&catalogId={d}&lan={d}";

pub const ChangeWaitingParams = struct {
    catalog_id: u16,
    tld: []const u8,
    seed: usize,
    anonymizer: ?[]const u8,
};

pub const FetchParams = struct {
    page: page.Pages.Page = page.Pages.Page{ .size = 10, .offset = 1 },
    catalogId: u16,
    tld: []const u8,
    seed: usize,
    anonymizer: ?[]const u8,
};

pub const Announce = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    total: u32,
    releaseDate: i64,
    catalogId: u16,
    title: []const u8,
    id: u32,

    pub fn parseFirstEveryCatalog(allocator: std.mem.Allocator, url: []const u8, body: []const u8) !std.ArrayList(Announce) {
        var result = try std.ArrayList(Announce).initCapacity(allocator, 1);
        errdefer {
            for (result.items) |article| {
                article.deinit();
            }
            result.deinit(allocator);
        }
        var parser = try simdjzon.dom.Parser.initFixedBuffer(allocator, body, .{});
        defer parser.deinit();
        try parser.parse();
        var dataSection = try parser.element().at_pointer("/data/catalogs");
        var index: u32 = 0;
        var arr = try dataSection.get_array();
        while (true) {
            const next = arr.at(index) orelse break;
            var nxt = try next.get_object();
            // var nxt = try @constCast(&next).get_object(); // drop const
            var cidNode = nxt.at_key("catalogId") orelse return error.NoCatalogId;
            // var cidNode = nxt.find_field("catalogId") catch return error.NoCatalogId;
            const cid = cidNode.get_int64() catch return error.NoCatalogId;
            var totalNode = nxt.at_key("total") orelse return error.NoTotal;
            const total = totalNode.get_int64() catch return error.NoTotal;
            var articlesNode = nxt.at_key("articles") orelse return error.NoArticles;
            var articlesit = (articlesNode.get_array() catch return error.NoArticles);
            var nxtArticle = articlesit.at(0) orelse break;
            var releaseDateNode = nxtArticle.at_key("releaseDate") orelse return error.NoReleaseDate;
            var titleNode = nxtArticle.at_key("title") orelse return error.NoTitle;
            var idNode = nxtArticle.at_key("id") orelse return error.NoId;
            const urlCopy = try allocator.dupe(u8, url);
            errdefer allocator.free(urlCopy);
            const title = allocator.dupe(u8, try titleNode.get_string()) catch return error.NoTitle;
            errdefer allocator.free(title);
            const anotherOne = Announce{
                .allocator = allocator,
                .url = urlCopy,
                .total = @intCast(total),
                .releaseDate = releaseDateNode.get_int64() catch return error.NoReleaseDate,
                .catalogId = @intCast(cid),
                .title = title,
                .id = @intCast(idNode.get_int64() catch return error.NoId),
            };
            try result.append(allocator, anotherOne);
            index += 1;
        }
        return result;
    }

    pub fn deinit(self: *const Announce) void {
        self.allocator.free(self.url);
        self.allocator.free(self.title);
        // if (self._titleGc) { // streaming parser hack
        //     deinitTitle(self.allocator, self.title);
        // }
    }

    // weird deinialization routine
    // fn deinitTitle(allocator: std.mem.Allocator, title: []const u8) void {
    //     const start_ptr = title.ptr; // strange library allocation in parse_string_alloc
    //     const len = title.len + 2;
    //     const full_slice: []const u8 = @as([*]const u8, start_ptr)[0..len];
    //     // Now free the memory using the adjusted slice
    //     allocator.free(full_slice);
    // }

    fn extractTotal(haystack: []const u8) ?u32 {
        const result = extractFirstOccurence(haystack, "\"total\":") orelse return null;
        return std.fmt.parseInt(u32, result, 0) catch return null;
    }

    fn extractReleaseDate(haystack: []const u8) ?i64 {
        const result = extractFirstOccurence(haystack, "\"releaseDate\":") orelse return null;
        return std.fmt.parseInt(i64, result, 0) catch return null;
    }

    fn extractCatalogId(haystack: []const u8) ?u16 {
        const result = extractFirstOccurence(haystack, "\"catalogId\":") orelse return null;
        return std.fmt.parseInt(u16, result, 0) catch return null;
    }

    fn extractTitle(haystack: []const u8) ?[]const u8 {
        return extractFirstOccurence(haystack, "\"title\":") orelse return null;
    }

    fn extractID(haystack: []const u8) ?u32 {
        const result = extractFirstOccurence(haystack, "\"id\":") orelse return null;
        return std.fmt.parseInt(u32, result, 0) catch return null;
    }

    fn extractFirstOccurence(haystack: []const u8, comptime needle: []const u8) ?[]const u8 {
        const start_index = std.mem.indexOf(u8, haystack, needle) orelse return null;
        var start = start_index + needle.len;
        // Skip whitespace
        while (start < haystack.len and std.ascii.isWhitespace(haystack[start])) {
            start += 1;
        }
        // Check if it's a string
        if (start < haystack.len and haystack[start] == '"') {
            start += 1;
            var end: usize = start;
            while (end < haystack.len) {
                if (haystack[end] == '\\' and end + 1 < haystack.len and haystack[end + 1] == '"') {
                    // Escaped quote, skip the backslash and the quote
                    end += 2;
                } else if (haystack[end] == '"') {
                    // Closing quote
                    break;
                } else {
                    end += 1;
                }
            }
            if (end < haystack.len) {
                return haystack[start..end];
            } else {
                return null; // Unterminated string
            }
        } else {
            // Extract until whitespace, comma, or closing brace
            var end: usize = start;
            while (end < haystack.len and !std.ascii.isWhitespace(haystack[end]) and haystack[end] != ',' and haystack[end] != '}') {
                end += 1;
            }
            return haystack[start..end];
        }
    }
};

pub const catalogPages = struct {
    pub const delisting = page.Pages.init(&[_]page.Pages.PageDecl{
        .{ .size = 2, .maxOffsetAvailable = 30 },
        .{ .size = 3, .maxOffsetAvailable = 10 },
        .{ .size = 5, .maxOffsetAvailable = 10 },
        .{ .size = 10, .maxOffsetAvailable = 10 },
        .{ .size = 15, .maxOffsetAvailable = 9 },
        .{ .size = 20, .maxOffsetAvailable = 7 },
        .{ .size = 50, .maxOffsetAvailable = 3 },
    });
    pub const listing = page.Pages.init(&[_]page.Pages.PageDecl{
        .{ .size = 2, .maxOffsetAvailable = 30 },
        .{ .size = 3, .maxOffsetAvailable = 30 },
        .{ .size = 5, .maxOffsetAvailable = 20 },
        .{ .size = 10, .maxOffsetAvailable = 30 },
        .{ .size = 15, .maxOffsetAvailable = 20 },
        .{ .size = 20, .maxOffsetAvailable = 20 },
        .{ .size = 50, .maxOffsetAvailable = 10 },
    });
    pub const default = page.Pages.init(&[_]page.Pages.PageDecl{
        .{ .size = 2, .maxOffsetAvailable = 100 },
        .{ .size = 3, .maxOffsetAvailable = 50 },
        .{ .size = 5, .maxOffsetAvailable = 50 },
        .{ .size = 10, .maxOffsetAvailable = 20 },
        .{ .size = 15, .maxOffsetAvailable = 10 },
        .{ .size = 20, .maxOffsetAvailable = 10 },
        .{ .size = 50, .maxOffsetAvailable = 10 },
    });
};

pub fn fetchDecodeLatestInEveryCatalog(allocator: std.mem.Allocator, easy: *const curl.Easy, config: *const FetchParams) !std.ArrayList(Announce) {
    const url = try buildUrl(allocator, config);
    defer allocator.free(url);
    const body = try fetchPage(allocator, easy, url, config);
    defer allocator.free(body);
    return try Announce.parseFirstEveryCatalog(allocator, url, body);
}

pub fn fetchDecodeLatestInCatalog(allocator: std.mem.Allocator, easy: *const curl.Easy, config: *const FetchParams) !?Announce {
    var allArticles = try fetchDecodeLatestInEveryCatalog(allocator, easy, config);
    defer allArticles.deinit(allocator);
    var result: ?Announce = null;
    for (allArticles.items) |article| {
        if (article.catalogId == config.catalogId) {
            result = article;
        } else {
            article.deinit();
        }
    }
    return result;
}

pub fn fetchPage(allocator: std.mem.Allocator, easy: *const curl.Easy, url: []const u8, config: *const FetchParams) ![]const u8 {
    std.debug.assert(config.page.size > 0);
    std.debug.assert(config.page.offset > 0);
    const body_request = if (config.anonymizer) |anonymizer_addr|
        http_post(allocator, easy, anonymizer_addr, url)
    else
        http_get(allocator, easy, url);
    return try body_request;
}

pub fn buildUrl(allocator: std.mem.Allocator, config: *const FetchParams) ![]const u8 {
    const zeroPad = try repeatZ(allocator, "0", (config.seed ^ (config.seed >> 3)) % 13);
    defer allocator.free(zeroPad);
    const plusPad = try repeatZ(allocator, "+", (config.seed ^ (config.seed >> 2)) % 3);
    defer allocator.free(plusPad);
    // const tweakedCatalogId = try std.fmt.allocPrint(allocator, "{s}{s}{d}", .{ plusPad, zeroPad, config.catalogId });
    // defer allocator.free(tweakedCatalogId);
    // const urlBase = try std.fmt.allocPrint(allocator, templateUrlApex, .{config.tld});
    // defer allocator.free(urlBase);
    // return try std.fmt.allocPrint(allocator, templateUrl, .{ urlBase, config.page.offset, config.page.size, tweakedCatalogId, config.seed, config.seed });
    return try std.fmt.allocPrint(allocator, templateUrlGlobal, .{
        config.tld,
        plusPad,
        zeroPad,
        config.page.offset,
        config.page.size,
        config.seed,
    });
}

fn isCacheHit(header: *const curl.Easy.Response.Header) bool {
    if (std.mem.eql(u8, header.name, "CF-Cache-Status") and !std.mem.eql(u8, header.get(), "MISS") and !std.mem.eql(u8, header.get(), "DYNAMIC")) {
        std.log.warn("Cache hit! Cloudflare: {s}", .{header.get()});
        return true;
    }
    if (std.mem.eql(u8, header.name, "X-Cache") and !std.mem.eql(u8, header.get(), "Miss from cloudfront")) {
        std.log.warn("Cache hit! CloudFront: {s}", .{header.get()});
        return true;
    }
    return false;
}

pub const NetworkError = error{ QueryFailed, CacheHit };
pub const ApplicationError = error{TextNotFound};

fn repeatZ(allocator: std.mem.Allocator, pattern: []const u8, count: usize) ![:0]u8 {
    const len = pattern.len * count;
    var result = try allocator.allocSentinel(u8, len, 0);
    for (0..count) |i| {
        @memcpy(result[i * pattern.len .. (i + 1) * pattern.len], pattern);
    }
    return result;
}

test "repeat pattern" {
    const alloc = std.testing.allocator;
    const pattern = try repeatZ(alloc, "abc", 2);
    defer alloc.free(pattern);
    try expect(std.mem.eql(u8, pattern, "abcabc"));
}

test "parsing total response" {
    const alloc = std.testing.allocator;

    {
        const body = @embedFile("global-announces.json");
        var fetchResult = try Announce.parseFirstEveryCatalog(alloc, "", body);
        defer {
            for (fetchResult.items) |article| {
                article.deinit();
            }
            fetchResult.deinit(alloc);
        }
        try std.testing.expectEqual(8, fetchResult.items.len);
        const article = fetchResult.items[7];
        try std.testing.expectEqual(128, article.catalogId);
        try std.testing.expectEqual(49, article.total);
        try std.testing.expectEqualStrings("Solayer (LAYER) Airdrop Continues: Second Binance HODLer Airdrops Announced – Earn LAYER With Retroactive BNB Simple Earn Subscriptions (2025-06-16)", article.title);
        try std.testing.expectEqual(238891, article.id);
        try std.testing.expectEqual(1750055401345, article.releaseDate);
    }
}
