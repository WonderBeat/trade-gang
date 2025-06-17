const std = @import("std");
const curl = @import("curl");
const proxy = @import("proxy-manager.zig");

pub const Buffer = std.ArrayList(u8);

pub const Curl = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    ca_bundle: Buffer,
    easy: curl.Easy,
    headers: curl.Easy.Headers,
    proxyManager: proxy.ProxyManager,
    proxyDownloadUrl: ?[:0]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const ca_bundle = try curl.allocCABundle(allocator);
        errdefer ca_bundle.deinit();
        //const hostname = std.posix.getenv("HOSTNAME") orelse "UNDEF";
        const easy = try curl.Easy.init(allocator, .{
            .default_user_agent = "Mozilla/5.0 Firefox/135.0", //
            .ca_bundle = ca_bundle,
            .default_timeout_ms = 3_100,
        });
        //try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_VERBOSE, @as(c_long, 1)));
        try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_ACCEPT_ENCODING, "")); // accept all possible by curl
        try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_TCP_KEEPALIVE, @as(c_long, 1)));
        try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_TCP_KEEPIDLE, @as(c_long, 6)));
        try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_DNS_CACHE_TIMEOUT, @as(c_long, 30))); //seconds
        if (std.posix.getenv("DNS_SERVERS")) |dns| {
            try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_DNS_SERVERS, dns.ptr));
        }
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
        self.* = .{
            .allocator = allocator,
            .ca_bundle = ca_bundle,
            .easy = easy,
            .headers = headers,
            .proxyManager = proxy.ProxyManager.init(allocator),
        };
        try self.setup_headers(0, 0);
        return self;
    }

    pub fn set_proxy(self: *Self, proxyAddr: [:0]const u8) !void {
        try checkCode(curl.libcurl.curl_easy_setopt(self.easy.handle, curl.libcurl.CURLOPT_PROXY, proxyAddr.ptr));
    }

    pub fn set_trim_body(self: *Self, trim_from: u32, trim_to: u32) !void {
        try self.setup_headers(trim_from, trim_to);
    }

    fn setup_headers(self: *Self, trim_from: u32, trim_to: u32) !void {
        self.headers.deinit();
        const headers = blk: {
            var h = try self.easy.createHeaders();
            errdefer h.deinit();
            try h.add("Host", "www.binance.com:@31337");
            try h.add("Accept", "*/*");
            //try h.add("Proxy-Connection", "keep-alive");
            //try h.add("lang", "en");
            //try h.add("Accep-Language", "en-US,en;q=0.5");
            if (trim_to > 0) {
                var buf: [20]u8 = undefined;
                const size_str = try std.fmt.bufPrint(&buf, "bytes={d}-{d}", .{ trim_from, trim_to });
                try h.add("Range", size_str);
            }
            break :blk h;
        };
        errdefer headers.deinit();
        try self.easy.setHeaders(headers);
    }

    pub fn deinit(self: *Self) void {
        self.easy.deinit();
        self.headers.deinit();
        self.ca_bundle.deinit();
        self.proxyManager.deinit();
        self.allocator.destroy(self);
    }

    pub fn setProxyDownloadUrl(self: *Self, url: [:0]const u8) void {
        self.proxyDownloadUrl = url;
    }

    pub fn dropCurrentProxy(self: *Self) !usize {
        if (!self.proxyManager.isEmpty()) {
            self.proxyManager.dropCurrent();
            if (self.proxyManager.getCurrentProxy()) |url| {
                try self.set_proxy(url);
            }
        }
        return self.proxyManager.size();
    }

    pub fn exchangeProxy(self: *Self) !void {
        if (self.proxyManager.size() < 5) {
            if (self.proxyDownloadUrl) |url| {
                const loadedCount = try self.proxyManager.loadFromUrl(url);
                if (loadedCount == 0) {
                    return error.ProxyLoadError;
                }
                std.log.debug("{d} proxies loaded", .{self.proxyManager.size()});
            }
        }
        if (self.proxyManager.getNextProxy()) |proxy_url| {
            try self.set_proxy(proxy_url);
        }
    }

    pub fn latest_query_metrics(self: *Self) ?struct { pretransfer_time: u32, total_time: u32 } {
        var pretransfer: curl.libcurl.curl_off_t = 0;
        var res = curl.libcurl.curl_easy_getinfo(self.easy.handle, curl.libcurl.CURLINFO_PRETRANSFER_TIME_T, &pretransfer);
        if (res != curl.libcurl.CURLE_OK) {
            return null;
        }
        var total_time: curl.libcurl.curl_off_t = 0;
        res = curl.libcurl.curl_easy_getinfo(self.easy.handle, curl.libcurl.CURLINFO_TOTAL_TIME_T, &total_time);
        if (res != curl.libcurl.CURLE_OK) {
            return null;
        }
        return .{ .pretransfer_time = @intCast(@divFloor(pretransfer, @as(c_long, 1000))), .total_time = @intCast(@divFloor(total_time, @as(c_long, 1000))) };
    }
};

pub fn get(allocator: std.mem.Allocator, client: *const curl.Easy, url: [:0]const u8) !curl.Easy.Response {
    var buf = Buffer.init(allocator);
    try client.setWritefunction(curl.bufferWriteCallback);
    try client.setWritedata(&buf);
    try client.setUrl(url);
    var resp = try perform(allocator, client);
    resp.body = buf;
    return resp;
}

pub fn perform(allocator: std.mem.Allocator, client: *const curl.Easy) !curl.Easy.Response {
    try client.setCommonOpts();
    var status_code: c_long = 0;
    var code = curl.libcurl.curl_easy_perform(client.handle);
    if (code != curl.libcurl.CURLE_OK) {
        std.log.debug("curl err code:{d}, msg:{s}\n", .{ code, curl.libcurl.curl_easy_strerror(code) });
        try decodeError(code);
    }

    code = curl.libcurl.curl_easy_getinfo(client.handle, curl.libcurl.CURLINFO_RESPONSE_CODE, &status_code);
    if (code != curl.libcurl.CURLE_OK) {
        std.log.debug("curl err code:{d}, msg:{s}", .{ code, curl.libcurl.curl_easy_strerror(code) });
        try decodeError(code);
    }

    return .{
        .status_code = @intCast(status_code),
        .handle = client.handle,
        .body = null,
        .allocator = allocator,
    };
}

fn checkCode(code: curl.libcurl.CURLcode) !void {
    if (code == curl.libcurl.CURLE_OK) {
        return;
    }
    return error.CurlCodeUnexpected;
}

pub const CurlError = error{
    UnsupportedProtocol,
    FailedInitialization,
    URLMalformat,
    NotBuiltIn,
    CouldntResolveProxy,
    CouldntResolveHost,
    CouldntConnect,
    WeirdServerReply,
    RemoteAccessDenied,
    FtpAcceptFailed,
    FtpWeirdPassReply,
    FtpAcceptTimeout,
    FtpWeirdPasvReply,
    FtpWeird227Format,
    FtpCantGetHost,
    HTTP2,
    FtpCouldntSetType,
    PartialFile,
    FtpCouldntRetrFile,
    QuoteError,
    HTTPReturnedError,
    WriteError,
    UploadFailed,
    ReadError,
    OutOfMemory,
    OperationTimedout,
    FtpPortFailed,
    FtpCouldntUseRest,
    RangeError,
    SSLConnectError,
    BadDownloadResume,
    FileCouldntReadFile,
    LdapCannotBind,
    LdapSearchFailed,
    AbortedByCallback,
    BadFunctionArgument,
    InterfaceFailed,
    TooManyRedirects,
    UnknownOption,
    SetoptOptionSyntax,
    GotNothing,
    SSLEngineNotFound,
    SSLEngineSetFailed,
    SendError,
    RecvError,
    SSLCertProblem,
    SSLCipher,
    PeerFailedVerification,
    BadContentEncoding,
    FilesizeExceeded,
    UseSSLFailed,
    SendFailRewind,
    SSLEngineInitFailed,
    LoginDenied,
    TftpNotFound,
    TftpPerm,
    RemoteDiskFull,
    TftpIllegal,
    TftpUnknownId,
    RemoteFileExists,
    TftpNoSuchUser,
    SSLCacertBadfile,
    RemoteFileNotFound,
    SSH,
    SSLShutdownFailed,
    Again,
    SSLCrlBadfile,
    SSLIssuerError,
    FtpPretFailed,
    RtspCseqError,
    RtspSessionError,
    FtpBadFileList,
    ChunkFailed,
    NoConnectionAvailable,
    SSLPinnedPubkeynotmatch,
    SSLInvalidCertstatus,
    HTTP2Stream,
    RecursiveApiCall,
    AuthError,
    HTTP3,
    QuicConnectError,
    Proxy,
    SSLClientCert,
    UnrecoverablePoll,
    TooLarge,
    ECHRequired,
};

pub fn decodeError(code: u32) !void {
    return switch (code) {
        0 => @panic("CURLE_OK should not be passed to decodeError"),
        1 => CurlError.UnsupportedProtocol,
        2 => CurlError.FailedInitialization,
        3 => CurlError.URLMalformat,
        4 => CurlError.NotBuiltIn,
        5 => CurlError.CouldntResolveProxy,
        6 => CurlError.CouldntResolveHost,
        7 => CurlError.CouldntConnect,
        8 => CurlError.WeirdServerReply,
        9 => CurlError.RemoteAccessDenied,
        10 => CurlError.FtpAcceptFailed,
        11 => CurlError.FtpWeirdPassReply,
        12 => CurlError.FtpAcceptTimeout,
        13 => CurlError.FtpWeirdPasvReply,
        14 => CurlError.FtpWeird227Format,
        15 => CurlError.FtpCantGetHost,
        16 => CurlError.HTTP2,
        17 => CurlError.FtpCouldntSetType,
        18 => CurlError.PartialFile,
        19 => CurlError.FtpCouldntRetrFile,
        21 => CurlError.QuoteError,
        22 => CurlError.HTTPReturnedError,
        23 => CurlError.WriteError,
        25 => CurlError.UploadFailed,
        26 => CurlError.ReadError,
        27 => CurlError.OutOfMemory,
        28 => CurlError.OperationTimedout,
        30 => CurlError.FtpPortFailed,
        31 => CurlError.FtpCouldntUseRest,
        33 => CurlError.RangeError,
        35 => CurlError.SSLConnectError,
        36 => CurlError.BadDownloadResume,
        37 => CurlError.FileCouldntReadFile,
        38 => CurlError.LdapCannotBind,
        39 => CurlError.LdapSearchFailed,
        42 => CurlError.AbortedByCallback,
        43 => CurlError.BadFunctionArgument,
        45 => CurlError.InterfaceFailed,
        47 => CurlError.TooManyRedirects,
        48 => CurlError.UnknownOption,
        49 => CurlError.SetoptOptionSyntax,
        52 => CurlError.GotNothing,
        53 => CurlError.SSLEngineNotFound,
        54 => CurlError.SSLEngineSetFailed,
        55 => CurlError.SendError,
        56 => CurlError.RecvError,
        58 => CurlError.SSLCertProblem,
        59 => CurlError.SSLCipher,
        60 => CurlError.PeerFailedVerification,
        61 => CurlError.BadContentEncoding,
        63 => CurlError.FilesizeExceeded,
        64 => CurlError.UseSSLFailed,
        65 => CurlError.SendFailRewind,
        66 => CurlError.SSLEngineInitFailed,
        67 => CurlError.LoginDenied,
        68 => CurlError.TftpNotFound,
        69 => CurlError.TftpPerm,
        70 => CurlError.RemoteDiskFull,
        71 => CurlError.TftpIllegal,
        72 => CurlError.TftpUnknownId,
        73 => CurlError.RemoteFileExists,
        74 => CurlError.TftpNoSuchUser,
        77 => CurlError.SSLCacertBadfile,
        78 => CurlError.RemoteFileNotFound,
        79 => CurlError.SSH,
        80 => CurlError.SSLShutdownFailed,
        81 => CurlError.Again,
        82 => CurlError.SSLCrlBadfile,
        83 => CurlError.SSLIssuerError,
        84 => CurlError.FtpPretFailed,
        85 => CurlError.RtspCseqError,
        86 => CurlError.RtspSessionError,
        87 => CurlError.FtpBadFileList,
        88 => CurlError.ChunkFailed,
        89 => CurlError.NoConnectionAvailable,
        90 => CurlError.SSLPinnedPubkeynotmatch,
        91 => CurlError.SSLInvalidCertstatus,
        92 => CurlError.HTTP2Stream,
        93 => CurlError.RecursiveApiCall,
        94 => CurlError.AuthError,
        95 => CurlError.HTTP3,
        96 => CurlError.QuicConnectError,
        97 => CurlError.Proxy,
        98 => CurlError.SSLClientCert,
        99 => CurlError.UnrecoverablePoll,
        100 => CurlError.TooLarge,
        101 => CurlError.ECHRequired,
        else => return error.UnexpectedError,
    };
}
