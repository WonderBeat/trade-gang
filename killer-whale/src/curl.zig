const std = @import("std");
const curl = @import("curl");
const buildConfig = @import("config");
const proxy = @import("proxy-manager.zig");
const c = @cImport({
    @cInclude("stdlib.h");
});

pub const Buffer = std.ArrayList(u8);

pub const Curl = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    ca_bundle: Buffer,
    easy: curl.Easy,
    headers: curl.Easy.Headers,
    proxyManager: proxy.ProxyManager,
    proxyDownloadUrl: ?[:0]const u8 = null,
    receiveBuffer: Buffer,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const ca_bundle = try curl.allocCABundle(allocator);
        errdefer ca_bundle.deinit();
        const timeout = try std.fmt.parseInt(u32, std.posix.getenv("QUERY_TIMEOUT") orelse "2000", 0);
        const easy = try curl.Easy.init(allocator, .{
            .default_user_agent = "Mozilla/5.0 Firefox/135.0", //
            .ca_bundle = ca_bundle,
            .default_timeout_ms = timeout,
        });
        if (buildConfig.verbose) {
            try checkCode(curl.libcurl.curl_easy_setopt(easy.handle, curl.libcurl.CURLOPT_VERBOSE, @as(c_long, 1)));
        }
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
            .receiveBuffer = try Buffer.initCapacity(self.allocator, 12000),
        };
        if (std.posix.getenv("socks_proxy")) |socks_proxy| {
            try self.setProxy(socks_proxy);
        }
        try self.initHeaders(.{});
        return self;
    }

    pub fn setProxy(self: *Self, proxyAddr: [:0]const u8) !void {
        try checkCode(curl.libcurl.curl_easy_setopt(self.easy.handle, curl.libcurl.CURLOPT_PROXY, proxyAddr.ptr));
    }

    pub fn initHeaders(self: *Self, options: struct {
        trimFrom: ?usize = null,
        trimTo: ?usize = null,
        etag: ?[]const u8 = null,
    }) !void {
        self.headers.deinit();
        self.headers = try self.easy.createHeaders();
        errdefer self.headers.deinit();
        try self.headers.add("Authorization", "Basic dXN");
        try self.headers.add("Accept", "*/*");
        try self.headers.add("Accep-Language", "en-US,en;q=0.1");
        if (options.trimFrom) |from| {
            if (options.trimTo) |to| {
                try self.setTrimBody(from, to);
            }
        }
        if (options.etag) |etag| {
            try self.setEtag(etag);
        }
        try self.easy.setHeaders(self.headers);
    }

    fn setTrimBody(self: *Self, trim_from: usize, trim_to: usize) !void {
        var buf: [20]u8 = undefined;
        const size_str = try std.fmt.bufPrint(&buf, "bytes={d}-{d}", .{ trim_from, trim_to });
        try self.headers.add("Range", size_str);
    }

    fn setEtag(self: *Self, etag: []const u8) !void {
        try self.headers.add("If-None-Match", etag);
    }

    pub fn deinit(self: *Self) void {
        self.easy.deinit();
        self.headers.deinit();
        self.ca_bundle.deinit();
        self.proxyManager.deinit();
        self.receiveBuffer.deinit();
        self.allocator.destroy(self);
    }

    pub fn setProxyDownloadUrl(self: *Self, url: [:0]const u8) void {
        self.proxyDownloadUrl = url;
    }

    pub fn dropCurrentProxy(self: *Self) !usize {
        if (!self.proxyManager.isEmpty()) {
            self.proxyManager.dropCurrent();
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
            try self.setProxy(proxy_url);
            std.log.debug("Proxy changed to {s}", .{proxy_url});
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
        return .{
            .pretransfer_time = @intCast(@divFloor(pretransfer, @as(c_long, 1000))),
            .total_time = @intCast(@divFloor(total_time, @as(c_long, 1000))),
        };
    }

    // resp is valid till next request
    // do not deinit response
    pub fn get(
        self: *Self,
        url: [:0]const u8,
        //        func: *const fn (*Buffer) i32,
    ) !curl.Easy.Response {
        self.receiveBuffer.clearRetainingCapacity();
        const client = &self.easy;
        try client.setWritefunction(curl.bufferWriteCallback);
        try client.setWritedata(&self.receiveBuffer);
        try client.setUrl(url);
        var resp = try perform(self.allocator, client);
        resp.body = self.receiveBuffer;
        return resp;
    }
};

// default perform function has no debug info
pub fn get(allocator: std.mem.Allocator, client: *const curl.Easy, url: [:0]const u8) !curl.Easy.Response {
    var buf = try Buffer.initCapacity(allocator, 7000);
    try client.setWritefunction(curl.bufferWriteCallback);
    try client.setWritedata(&buf);
    try client.setUrl(url);
    var resp = try perform(allocator, client);
    resp.body = buf;
    return resp;
}

fn perform(allocator: std.mem.Allocator, client: *const curl.Easy) !curl.Easy.Response {
    try client.setCommonOpts();
    var status_code: c_long = 0;
    var code = curl.libcurl.curl_easy_perform(client.handle);
    if (code != curl.libcurl.CURLE_OK) {
        std.log.debug("curl err code:{d}, msg:{s}", .{ code, curl.libcurl.curl_easy_strerror(code) });
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

//result lifespan is the same as curl body buffer
pub fn resolveIpLocation(httpClient: *Curl, proxyUrl: [:0]const u8) ![]const u8 {
    var ip: []const u8 = undefined;

    // Handle case with protocol prefix (e.g., socks5://)
    if (std.mem.indexOf(u8, proxyUrl, "://")) |proto_end| {
        const after_protocol = proxyUrl[proto_end + 3 ..];
        if (std.mem.indexOf(u8, after_protocol, "@")) |auth_end| {
            ip = after_protocol[auth_end + 1 ..];
        } else {
            ip = after_protocol;
        }
    } else {
        // Handle simple format (ip:port)
        ip = proxyUrl;
    }

    // Remove port if present
    if (std.mem.indexOf(u8, ip, ":")) |port_start| {
        ip = ip[0..port_start];
    }

    if (ip.len == 0) {
        return error.InvalidProxyFormat;
    }
    var buffer: [100]u8 = undefined;

    // Construct ipinfo.io URL
    const url = try std.fmt.bufPrintZ(&buffer, "https://ipinfo.io/{s}/city", .{ip});
    const response = try httpClient.get(url);
    const bodyBuffer = response.body orelse return error.NoBody;
    if (bodyBuffer.capacity == 0) {
        return error.NoBody;
    }
    return bodyBuffer.items;
}
