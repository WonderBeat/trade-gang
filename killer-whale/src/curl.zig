const std = @import("std");
const curl = @import("curl");

pub const Buffer = std.ArrayList(u8);

pub const Curl = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    ca_bundle: Buffer,
    easy: curl.Easy,
    headers: curl.Easy.Headers,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const ca_bundle = try curl.allocCABundle(allocator);
        errdefer ca_bundle.deinit();
        //const hostname = std.posix.getenv("HOSTNAME") orelse "UNDEF";
        const easy = try curl.Easy.init(allocator, .{
            .default_user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15) Gecko/20100101 Firefox/135.0", //
            .ca_bundle = ca_bundle,
            .default_timeout_ms = 20_000,
        });
        //try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_VERBOSE, @as(c_long, 1)));
        try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_ACCEPT_ENCODING, "gzip"));
        try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_TCP_KEEPALIVE, @as(c_long, 1)));
        try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_DNS_CACHE_TIMEOUT, @as(c_long, 3))); //seconds
        if (std.posix.getenv("COOKIE")) |cookie_available| {
            try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_COOKIE, cookie_available.ptr));
        }
        if (std.posix.getenv("insecure")) |_| {
            std.log.debug("Insecure mode", .{});
            try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_SSL_VERIFYHOST, @as(c_long, 0)));
            try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_SSL_VERIFYPEER, @as(c_long, 0)));
            try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_PROXY_SSL_VERIFYPEER, @as(c_long, 0)));
            try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_PROXY_SSL_VERIFYHOST, @as(c_long, 0)));
        }

        if (std.posix.getenv("socks_proxy")) |socks_proxy| {
            try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_PROXY, socks_proxy.ptr));
        }
        errdefer easy.deinit();
        //const user_agent = try std.fmt.allocPrint(allocator, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:135.0) Gecko/20100101 Firefox/135.0, {s}", .{hostname});
        //errdefer allocator.free(user_agent);
        const self = try allocator.create(Self);
        const headers = try self.easy.createHeaders();
        self.* = .{ .allocator = allocator, .ca_bundle = ca_bundle, .easy = easy, .headers = headers };
        try self.setup_headers(0);
        return self;
    }

    pub fn set_trim_body(self: *Self, size: u32) !void {
        try self.setup_headers(size);
    }

    fn setup_headers(self: *Self, size: u32) !void {
        self.headers.deinit();
        const headers = blk: {
            var h = try self.easy.createHeaders();
            errdefer h.deinit();
            //try h.add("Origin", "www.binance.com");
            try h.add("Accept", "text/html,application/json,application/xhtml+xml");
            //try h.add("User-Agent", "Firefox/135.0");
            //try h.add("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:135.0) Gecko/20100101 Firefox/135.0");
            try h.add("Accep-Language", "en-US,en;q=0.5");
            if (size > 0) {
                var buf: [20]u8 = undefined;
                const size_str = try std.fmt.bufPrint(&buf, "bytes=0-{d}", .{size});
                try h.add("Range", size_str);
            }
            //try h.add("User-Agent", user_agent);
            break :blk h;
        };
        errdefer headers.deinit();
        try self.easy.setHeaders(headers);
    }

    pub fn deinit(self: *Self) void {
        self.easy.deinit();
        self.headers.deinit();
        self.ca_bundle.deinit();
        //self.allocator.free(self.user_agent);
        self.allocator.destroy(self);
    }
};

fn checkCode(code: curl.libcurl.CURLcode) !void {
    if (code == curl.libcurl.CURLE_OK) {
        return;
    }
    return error.CurlCodeUnexpected;
}
