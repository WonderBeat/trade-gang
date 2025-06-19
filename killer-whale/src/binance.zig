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

pub fn http_get(allocator: std.mem.Allocator, client: *const curl.Easy, url: []const u8) ![]const u8 {
    const response = rsp: {
        const urlZ: [:0]u8 = try allocator.allocSentinel(u8, url.len, 0);
        @memcpy(urlZ, url);
        defer allocator.free(urlZ);
        break :rsp try wcurl.get(allocator, client, urlZ);
    };
    defer response.deinit();
    if (response.status_code < 200 or response.status_code >= 300) {
        std.log.err("req failed with {d} for URL: {s}", .{ response.status_code, url });
        return error.StatusCodeErr;
    }
    var headerIterator = try response.iterateHeaders(.{});
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
    var buf = std.ArrayList(u8).init(allocator);
    const response = rsp: {
        errdefer buf.deinit();
        const urlZ: [:0]u8 = try allocator.allocSentinel(u8, url.len, 0);
        @memcpy(urlZ, url);
        defer allocator.free(urlZ);
        try client.setWritefunction(curl.bufferWriteCallback);
        try client.setWritedata(&buf);
        try client.setUrl(urlZ);
        try client.setPostFields(content);
        var resp = try client.perform();
        resp.body = buf;
        break :rsp resp;
    };
    defer response.deinit();
    if (response.status_code < 200 or response.status_code >= 300) {
        std.log.err("POST failed with {d} for URL: {s}", .{ response.status_code, url });
        return error.StatusCodeErr;
    }
    const body_buffer = response.body orelse return error.NoBody;
    if (body_buffer.capacity == 0) {
        std.log.warn("NB: {d}", .{response.status_code});
        return error.NoBody;
    }
    return try allocator.dupe(u8, body_buffer.items);
}

const available_page_sizes = [_]u32{ 50, 20, 15, 10, 5, 3, 2 };

const templateUrlApex = "https://www.binance.{s}/bapi/apex/v1/public/apex/cms/article/list/query?type=1&";
const templateUrlComposite = "https://www.binance.{s}/bapi/composite/v1/public/cms/article/catalog/list/query?";
const templateUrlGlobal = "https://www.binance.{s}/bapi/apex/v1/public/apex/cms/article/list/query?pageNo=0x{x}&type=1&pageSize={d}&lan={d}";

const templateUrlDebug = "http://127.0.0.1:8765/{s}/";
const templateUrl = "{s}pageNo=0x{x}&pageSize={d}&catalogId={s}&catalogId={d}&lan={d}";

pub const ChangeWaitingParams = struct {
    catalog_id: u16,
    tld: []const u8,
    seed: usize,
    anonymizer: ?[]const u8,
};

pub const FetchSingleParams = struct {
    page: page.Pages.Page = page.Pages.Page{ .size = 10, .offset = 1 },
    catalogId: u16,
    tld: []const u8,
    seed: usize,
    anonymizer: ?[]const u8,
};

pub const FetchResult = struct {
    url: []const u8,
    body: []const u8,

    pub fn clear(self: *const FetchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.body);
    }

    pub fn extractTotal(self: *const FetchResult) ?u32 {
        const result = self.extractFirstOccurence("\"total\":") orelse return null;
        return std.fmt.parseInt(u32, result, 0) catch return null;
    }

    pub fn extractReleaseDate(self: *const FetchResult) ?i64 {
        const result = self.extractFirstOccurence("\"releaseDate\":") orelse return null;
        return std.fmt.parseInt(i64, result, 0) catch return null;
    }

    pub fn extractCatalogId(self: *const FetchResult) ?u16 {
        const result = self.extractFirstOccurence("\"catalogId\":") orelse return null;
        return std.fmt.parseInt(u16, result, 0) catch return null;
    }

    pub fn extractTitle(self: *const FetchResult) ?[]const u8 {
        return self.extractFirstOccurence("\"title\":") orelse return null;
    }

    pub fn extractID(self: *const FetchResult) ?u32 {
        const result = self.extractFirstOccurence("\"id\":") orelse return null;
        return std.fmt.parseInt(u32, result, 0) catch return null;
    }

    fn extractFirstOccurence(self: *const FetchResult, comptime needle: []const u8) ?[]const u8 {
        const start_index = std.mem.indexOf(u8, self.body, needle) orelse return null;
        var start = start_index + needle.len;
        // Skip whitespace
        while (start < self.body.len and std.ascii.isWhitespace(self.body[start])) {
            start += 1;
        }
        // Check if it's a string
        if (start < self.body.len and self.body[start] == '"') {
            start += 1;
            var end: usize = start;
            while (end < self.body.len) {
                if (self.body[end] == '\\' and end + 1 < self.body.len and self.body[end + 1] == '"') {
                    // Escaped quote, skip the backslash and the quote
                    end += 2;
                } else if (self.body[end] == '"') {
                    // Closing quote
                    break;
                } else {
                    end += 1;
                }
            }
            if (end < self.body.len) {
                return self.body[start..end];
            } else {
                return null; // Unterminated string
            }
        } else {
            // Extract until whitespace, comma, or closing brace
            var end: usize = start;
            while (end < self.body.len and !std.ascii.isWhitespace(self.body[end]) and self.body[end] != ',' and self.body[end] != '}') {
                end += 1;
            }
            return self.body[start..end];
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

pub fn fetchPage(allocator: std.mem.Allocator, easy: *const curl.Easy, config: *const FetchSingleParams) !?FetchResult {
    std.debug.assert(config.page.size > 0);
    std.debug.assert(config.page.offset > 0);
    const fetch_url = buildUrl(allocator, config) catch unreachable;
    errdefer allocator.free(fetch_url);
    const body_request = if (config.anonymizer) |anonymizer_addr|
        http_post(allocator, easy, anonymizer_addr, fetch_url)
    else
        http_get(allocator, easy, fetch_url);
    const body = try body_request;
    errdefer allocator.free(body);
    return .{ .body = body, .url = fetch_url };
}

fn buildUrl(allocator: std.mem.Allocator, config: *const FetchSingleParams) ![]const u8 {
    // const zeroPad = try repeatZ(allocator, "0", (config.seed ^ (config.seed >> 3)) % 14);
    // defer allocator.free(zeroPad);
    // const plusPad = try repeatZ(allocator, "+", (config.seed ^ (config.seed >> 2)) % 3);
    // defer allocator.free(plusPad);
    // const tweakedCatalogId = try std.fmt.allocPrint(allocator, "{s}{s}{d}", .{ plusPad, zeroPad, config.catalogId });
    // defer allocator.free(tweakedCatalogId);
    // const urlBase = try std.fmt.allocPrint(allocator, templateUrlApex, .{config.tld});
    // defer allocator.free(urlBase);
    // return try std.fmt.allocPrint(allocator, templateUrl, .{ urlBase, config.page.offset, config.page.size, tweakedCatalogId, config.seed, config.seed });
    return try std.fmt.allocPrint(allocator, templateUrlGlobal, .{
        config.tld,
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

test "extractTotal" {
    // Test case 1: Valid total
    {
        const body = "{ \"total\": 12345 }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const total = fetch_result.extractTotal();
        try expect(total != null and total.? == 12345);
    }

    // Test case 2: Total missing
    {
        const body = "{ \"other\": 123 }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const total = fetch_result.extractTotal();
        try expect(total == null);
    }

    // Test case 3: Total with non-digit characters
    {
        const body = "{ \"total\": abc }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const total = fetch_result.extractTotal();
        try expect(total == null);
    }
}

test "extractReleaseDate" {

    // Test case 1: Valid releaseDate
    {
        const body = "{ \"releaseDate\": 67890 }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const releaseDate = fetch_result.extractReleaseDate();
        try expect(releaseDate != null and releaseDate.? == 67890);
    }

    // Test case 2: releaseDate missing
    {
        const body = "{ \"other\": 123 }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const releaseDate = fetch_result.extractReleaseDate();
        try expect(releaseDate == null);
    }
}

test "extractCatalogId" {

    // Test case 1: Valid catalogId
    {
        const body = "{ \"catalogId\": 54321 }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const catalogId = fetch_result.extractCatalogId();
        try expect(catalogId != null and catalogId.? == 54321);
    }

    // Test case 2: catalogId missing
    {
        const body = "{ \"other\": 123 }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const catalogId = fetch_result.extractCatalogId();
        try expect(catalogId == null);
    }
}

test "extractTitle" {

    // Test case 1: Valid title
    {
        const body = "{ \"title\": \"example title\" }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const title = fetch_result.extractTitle();
        try std.testing.expectEqualStrings("example title", title.?);
    }

    // Test case 2: title missing
    {
        const body = "{ \"other\": 123 }";
        var fetch_result = FetchResult{ .url = "", .body = body };
        const title = fetch_result.extractTitle();
        try expect(title == null);
    }
}
