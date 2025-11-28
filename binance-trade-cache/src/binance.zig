const std = @import("std");
const builtin = @import("builtin");
const simdjzon = @import("simdjzon");
const storage = @import("storage.zig");

const endpoint = "https://eapi.binance.com";
const futures_endpoint = "https://fapi.binance.com";
const spot_endpoint = "https://api2.binance.com";

pub const futures_exchange_info_url = std.fmt.comptimePrint("{s}/fapi/v1/exchangeInfo", .{futures_endpoint});
pub const spot_exchange_info_url = std.fmt.comptimePrint("{s}/api/v3/exchangeInfo", .{spot_endpoint});

pub fn extractDataSectionFromJson(json_str: []const u8) ![]const u8 {
    const data_key_start = std.mem.indexOf(u8, json_str, "\"data\":") orelse return error.DataKeyNotFound;
    var brace_pos: usize = data_key_start + 7; // Skip past "\"data\":"
    // find {
    while (brace_pos < json_str.len and (json_str[brace_pos] == ' ' or json_str[brace_pos] == '\t' or json_str[brace_pos] == '\n' or json_str[brace_pos] == '\r')) : (brace_pos += 1) {}
    if (brace_pos >= json_str.len or json_str[brace_pos] != '{') {
        return error.DataObjectNotFound;
    }
    const data_start = brace_pos;
    var brace_count: usize = 1;
    var pos = data_start + 1;
    var in_string = false;
    var escape_next = false;
    while (pos < json_str.len and brace_count > 0) {
        const char = json_str[pos];

        if (escape_next) {
            escape_next = false;
            pos += 1;
            continue;
        }

        if (char == '\\') {
            escape_next = true;
            pos += 1;
            continue;
        }

        if (char == '"') {
            in_string = !in_string;
            pos += 1;
            continue;
        }

        if (!in_string) {
            if (char == '{') {
                brace_count += 1;
            } else if (char == '}') {
                brace_count -= 1;
                if (brace_count == 0) {
                    return json_str[data_start .. pos + 1];
                }
            }
        }

        pos += 1;
    }
    return error.UnmatchedBraces;
}

pub fn buildCombinedStreamUrlParams(
    allocator: std.mem.Allocator,
    pairs: []const storage.Pair,
    opts: struct {
        prefix: []const u8 = "/stream?streams=",
        stream_type: []const u8 = "@aggTrade",
    },
) ![]u8 {
    var stream_path = try std.ArrayList(u8).initCapacity(allocator, 8 * pairs.len);
    defer stream_path.deinit(allocator);

    try stream_path.appendSlice(allocator, opts.prefix);

    for (pairs, 0..) |pair, i| {
        const lowercase_pair = try std.ascii.allocLowerString(allocator, pair.name);
        defer allocator.free(lowercase_pair);

        try stream_path.appendSlice(allocator, lowercase_pair);
        try stream_path.appendSlice(allocator, opts.stream_type);

        if (i < pairs.len - 1) {
            try stream_path.append(allocator, '/');
        }
    }
    return stream_path.toOwnedSlice(allocator);
}

// Performs an HTTP GET request to the specified URL and returns the response body as caller owned memory
pub fn httpGetBody(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var redirect_buf: [256]u8 = undefined;
    var decompress_buf: [80000]u8 = undefined;
    var writer = std.Io.Writer.Allocating.init(allocator);
    const result = try client.fetch(.{ .method = .GET, .location = .{ .url = url }, .decompress_buffer = &decompress_buf, .keep_alive = false, .redirect_buffer = &redirect_buf, .response_writer = &writer.writer });
    if (result.status != .ok) {
        std.debug.print("Unexpected status: {d}\n", .{result.status});
        return error.UnexpectedStatus;
    }
    return try writer.toOwnedSlice();
    // var jsonReader = std.json.Reader.init(allocator, body);
    // defer jsonReader.deinit();

    // std.json.parseFromSlice(comptime T: type, allocator: Allocator, s: []const u8, options: ParseOptions)
    // const parsed: std.json.Parsed(std.json.Value) = try std.json.parseFromTokenSource(std.json.Value, allocator, &jsonReader, .{});
    // return parsed;
}

pub fn findSymbolsForTradeTracking(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    const future_exchange_inf = try httpGetBody(allocator, futures_exchange_info_url);
    defer allocator.free(future_exchange_inf);
    var future_pairs = try extractAlivePairs(allocator, future_exchange_inf);
    defer {
        for (future_pairs.items) |pair| {
            allocator.free(pair);
        }
        future_pairs.deinit(allocator);
    }
    var futures_pairs_to_track = try filterBlacklistedPairs(allocator, future_pairs.items);
    defer {
        for (futures_pairs_to_track.items) |pair| {
            allocator.free(pair);
        }
        futures_pairs_to_track.deinit(allocator);
    }
    const spot_exchange_inf = try httpGetBody(allocator, spot_exchange_info_url);
    defer allocator.free(spot_exchange_inf);
    var spot_pairs = try extractAlivePairs(allocator, spot_exchange_inf);
    defer {
        for (spot_pairs.items) |pair| {
            allocator.free(pair);
        }
        spot_pairs.deinit(allocator);
    }
    var spot_pairs_to_track = try filterBlacklistedPairs(allocator, spot_pairs.items);
    defer {
        for (spot_pairs_to_track.items) |pair| {
            allocator.free(pair);
        }
        spot_pairs_to_track.deinit(allocator);
    }
    const crossing_pairs = try intersectPairs(allocator, futures_pairs_to_track.items, spot_pairs_to_track.items);
    std.log.debug("Tracking {d} futures pairs and {d} spot pairs. Intersection {d}", .{ futures_pairs_to_track.items.len, spot_pairs_to_track.items.len, crossing_pairs.items.len });
    return crossing_pairs;
}

const Symbol = struct {
    symbol: []const u8,
    status: []const u8,
};

// Extracts trading pairs of alive futures from the given exchange info JSON. Caller owns result memory.
pub fn extractAlivePairs(allocator: std.mem.Allocator, exchange_info_json: []const u8) !std.ArrayList([]const u8) {
    var parser = try simdjzon.dom.Parser.initFixedBuffer(allocator, exchange_info_json, .{});
    defer parser.deinit();
    try parser.parse();
    var symbols: []Symbol = undefined;
    try (try parser.element().at_pointer("/symbols")).get_alloc(allocator, &symbols);
    defer allocator.free(symbols);

    var alive_symbols = try std.ArrayList([]const u8).initCapacity(allocator, 200);
    errdefer alive_symbols.deinit(allocator);

    for (symbols) |symbol_value| {
        if (std.mem.eql(u8, symbol_value.status, "TRADING")) {
            try alive_symbols.append(allocator, try allocator.dupe(u8, symbol_value.symbol));
        }
    }

    return alive_symbols;
}

const BlackListedPairs = [_][]const u8{
    "BTCUSDT",
    "ETHUSDT",
    "BCHUSDT",
    "ETCUSDT",
    "BNBUSDT",
    "XRPUSDT",
    "ADAUSDT",
    "DOGEUSDT",
    "DOTUSDT",
    "MATICUSDT",
    "SOLUSDT",
    "LTCUSDT",
    "TRXUSDT",
    "AVAXUSDT",
};

pub fn filterBlacklistedPairs(
    allocator: std.mem.Allocator,
    pairs: []const []const u8,
) !std.ArrayList([]const u8) {
    var filtered = try std.ArrayList([]const u8).initCapacity(allocator, pairs.len);
    errdefer filtered.deinit(allocator);

    for (pairs) |pair| {
        var is_blacklisted = false;
        for (BlackListedPairs) |blacklisted| {
            for (pair) |c| {
                if (!std.ascii.isAlphanumeric(c)) {
                    is_blacklisted = true;
                    break;
                }
            }
            if (std.mem.eql(u8, pair, blacklisted) or !std.mem.containsAtLeast(u8, pair, 1, "USDT")) {
                is_blacklisted = true;
                break;
            }
        }
        if (!is_blacklisted) {
            try filtered.append(allocator, try allocator.dupe(u8, pair));
        }
    }

    return filtered;
}

pub fn intersectPairs(
    allocator: std.mem.Allocator,
    pairs_a: []const []const u8,
    pairs_b: []const []const u8,
) !std.ArrayList([]const u8) {
    var result = try std.ArrayList([]const u8).initCapacity(allocator, @min(pairs_a.len, pairs_b.len));
    errdefer result.deinit(allocator);

    for (pairs_a) |pair_a| {
        for (pairs_b) |pair_b| {
            if (std.mem.eql(u8, pair_a, pair_b)) {
                try result.append(allocator, try allocator.dupe(u8, pair_a));
                break;
            }
        }
    }

    return result;
}

// Extracts the timestamp from aggregate trade message JSON using string tools, dividing by 1000 to convert from milliseconds to seconds
pub fn extractTimestampFromAggTrade(agg_trade_json: []const u8) !u64 {
    const event_time_start = std.mem.indexOf(u8, agg_trade_json, "\"E\":") orelse return error.TimestampNotFound;
    const after_colon = event_time_start + 4; // Skip past "\"E\":"
    var pos = after_colon;
    while (pos < agg_trade_json.len and
        agg_trade_json[pos] >= '0' and
        agg_trade_json[pos] <= '9') : (pos += 1)
    {}
    const timestamp_str = agg_trade_json[after_colon..pos];
    const event_time = try std.fmt.parseInt(u64, timestamp_str, 10);
    return event_time / 1000;
}

// Extracts the symbol/pair name from aggregate trade message JSON
pub fn extractSymbol(agg_trade_json: []const u8) ![]const u8 {
    const symbol_start = std.mem.indexOf(u8, agg_trade_json, "\"s\":") orelse return error.SymbolNotFound;
    const after_colon = symbol_start + 4; // Skip past "\"s\":"
    const after_opening_quote = if (agg_trade_json[after_colon] == '"') after_colon + 1 else after_colon;
    var pos = after_opening_quote;
    while (pos < agg_trade_json.len and agg_trade_json[pos] != '"') : (pos += 1) {}
    const symbol = agg_trade_json[after_opening_quote..pos];
    return symbol;
}

test "filterBlacklistedPairs filters out blacklisted pairs" {
    const allocator = std.testing.allocator;

    const input_pairs = [_][]const u8{
        "BTCUSDT",
        "ETHUSDT",
        "BNBUSDT", // blacklisted
        "SOLUSDT", // blacklisted
        "LINKUSDT",
        "DOGEUSDT", // blacklisted
        "AVAXUSDT", // blacklisted
        "UNIUSDT",
    };

    const expected_pairs = [_][]const u8{
        "LINKUSDT",
        "UNIUSDT",
    };

    var filtered = try filterBlacklistedPairs(allocator, &input_pairs);
    defer {
        for (filtered.items) |item| {
            allocator.free(item);
        }
        filtered.deinit(allocator);
    }

    try std.testing.expectEqual(expected_pairs.len, filtered.items.len);

    for (filtered.items, expected_pairs) |actual, expected| {
        try std.testing.expect(std.mem.eql(u8, actual, expected));
    }
}

test "extractTimestampFromAggTrade extracts timestamp correctly" {
    const agg_trade_json =
        \\{"e":"aggTrade","E":1763027967056,"a":771070850,"s":"BNBUSDT","p":"960.500","q":"1.57","f":1930698045,"l":1930698047,"T":1763027966904,"m":false}
    ;

    const expected_timestamp = 1763027967; // 1763027967056 / 1000

    const extracted_timestamp = try extractTimestampFromAggTrade(agg_trade_json);
    try std.testing.expectEqual(expected_timestamp, extracted_timestamp);
}

test "extractSymbolFromAggTrade extracts symbol correctly" {
    const agg_trade_json =
        \\{"e":"aggTrade","E":1763027967056,"a":771070850,"s":"BNBUSDT","p":"960.500","q":"1.57","f":1930698045,"l":1930698047,"T":1763027966904,"m":false}
    ;

    const expected_symbol = "BNBUSDT";

    const extracted_symbol = try extractSymbol(agg_trade_json);
    try std.testing.expect(std.mem.eql(u8, expected_symbol, extracted_symbol));
}

test "intersectPairs returns intersection of two pair lists" {
    const allocator = std.testing.allocator;

    const pairs_a = [_][]const u8{
        "BTCUSDT",
        "ETHUSDT",
        "BNBUSDT",
        "SOLUSDT",
        "LINKUSDT",
        "UNIUSDT",
    };

    const pairs_b = [_][]const u8{
        "ETHUSDT",
        "SOLUSDT",
        "LINKUSDT",
        "DOGEUSDT",
        "UNIUSDT",
    };

    const expected = [_][]const u8{
        "ETHUSDT",
        "SOLUSDT",
        "LINKUSDT",
        "UNIUSDT",
    };

    var intersection = try intersectPairs(allocator, &pairs_a, &pairs_b);
    defer {
        for (intersection.items) |item| {
            allocator.free(item);
        }
        intersection.deinit(allocator);
    }

    try std.testing.expectEqual(expected.len, intersection.items.len);

    for (intersection.items, expected) |actual, exp| {
        try std.testing.expect(std.mem.eql(u8, actual, exp));
    }
}

test "extractDataFromJson extracts data object correctly" {
    const json_str = "{\"stream\":\"kiteusdt@trade\",\"data\":{\"e\":\"trade\",\"E\":1764079443353,\"T\":1764079443353,\"s\":\"KITEUSDT\",\"t\":57635348,\"p\":\"0.1006800\",\"q\":\"55\",\"X\":\"MARKET\",\"m\":true}}";

    const expected_data = "{\"e\":\"trade\",\"E\":1764079443353,\"T\":1764079443353,\"s\":\"KITEUSDT\",\"t\":57635348,\"p\":\"0.1006800\",\"q\":\"55\",\"X\":\"MARKET\",\"m\":true}";

    const extracted_data = try extractDataSectionFromJson(json_str);
    try std.testing.expect(std.mem.eql(u8, expected_data, extracted_data));
}

test "extractDataFromJson handles nested objects" {
    const json_str = "{\"stream\":\"btcusdt@trade\",\"data\":{\"e\":\"trade\",\"E\":1234567890,\"s\":\"BTCUSDT\",\"p\":\"50000.00\",\"trader\":{\"id\":123,\"name\":\"test\"},\"m\":false}}";

    const expected_data = "{\"e\":\"trade\",\"E\":1234567890,\"s\":\"BTCUSDT\",\"p\":\"50000.00\",\"trader\":{\"id\":123,\"name\":\"test\"},\"m\":false}";

    const extracted_data = try extractDataSectionFromJson(json_str);
    try std.testing.expect(std.mem.eql(u8, expected_data, extracted_data));
}
