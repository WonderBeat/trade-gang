const std = @import("std");
const ws = @import("websocket");
const zio = @import("zio");

pub const AsyncClient = ws.Client(AsyncStream);
const Allocator = std.mem.Allocator;
const posix = std.posix;

pub inline fn asyncClient(
    rt: *zio.Runtime,
    config: ws.ClientConfig,
) !AsyncClient {
    return try ws.Client(AsyncStream).initForStream(rt.allocator, config, try AsyncStream.init(rt, config));
}

pub const AsyncStream = struct {
    const StreamRef = struct {
        stream: zio.net.Stream,
        reader: zio.net.Stream.Reader,
        writer: zio.net.Stream.Writer,
        tls_client: ?std.crypto.tls.Client = null,
        buffer: []u8,
    };
    read_timeout: u64 = 4500,
    write_timeout: u64 = 4500,
    rt: *zio.Runtime,
    stream_ref: *StreamRef,

    pub fn init(
        rt: *zio.Runtime,
        config: ws.ClientConfig,
    ) !AsyncStream {
        const buffer: []u8 = try rt.allocator.alloc(u8, 128 * 1024);
        errdefer rt.allocator.free(buffer);
        const quarter = buffer.len / 4;

        // Split buffer into TCP and TLS buffers
        const tcp_read_buffer = buffer[0..quarter];
        const tcp_write_buffer = buffer[quarter .. 2 * quarter];
        const tls_read_buffer = buffer[2 * quarter .. 3 * quarter];
        const tls_write_buffer = buffer[3 * quarter .. 4 * quarter];

        var stream_ref = try rt.allocator.create(StreamRef);
        stream_ref.* = .{
            .stream = try zio.net.tcpConnectToHost(rt, config.host, config.port),
            .buffer = buffer,
            .tls_client = null,
            .reader = undefined,
            .writer = undefined,
        };
        errdefer {
            stream_ref.stream.close(rt);
            stream_ref.stream.shutdown(rt, .both) catch |err| std.log.err("Shutdown error: {}", .{err});
            rt.allocator.destroy(stream_ref);
        }

        stream_ref.reader = stream_ref.stream.reader(rt, tcp_read_buffer);
        stream_ref.writer = stream_ref.stream.writer(rt, tcp_write_buffer);

        if (config.tls) {
            std.log.debug("Initiating TLS handshake...", .{});

            stream_ref.tls_client = std.crypto.tls.Client.init(&stream_ref.reader.interface, &stream_ref.writer.interface, .{
                .host = .{ .explicit = config.host },
                .ca = .no_verification,
                .read_buffer = tls_read_buffer,
                .write_buffer = tls_write_buffer,
            }) catch |err| {
                std.log.err("TLS handshake failed: {}", .{err});
                stream_ref.stream.close(rt);
                rt.allocator.destroy(stream_ref);
                return error.TlsHandshakeFailed;
            };
        }

        return .{
            .rt = rt,
            .stream_ref = stream_ref,
        };
    }

    pub fn close(self: *AsyncStream) void {
        self.stream_ref.stream.close(self.rt);
        self.rt.allocator.free(self.stream_ref.buffer);
        self.rt.allocator.destroy(self.stream_ref);
    }

    const ReadError = error{
        ConnectionResetByPeer,
        BrokenPipe,
        NotOpenForReading,
        WouldBlock,
        ReadFailed,
        WriteFailed,
        EndOfStream,
    };

    inline fn streamReader(self: *AsyncStream) *std.Io.Reader {
        if (self.stream_ref.tls_client != null) {
            return &self.stream_ref.tls_client.?.reader;
        }
        return &self.stream_ref.reader.interface;
    }

    inline fn streamWriter(self: *AsyncStream) *std.Io.Writer {
        if (self.stream_ref.tls_client != null) {
            return &self.stream_ref.tls_client.?.writer;
        }
        return &self.stream_ref.writer.interface;
    }

    pub fn read(self: *AsyncStream, buf: []u8) ReadError!usize {
        var w: std.Io.Writer = .fixed(buf);
        const reader = self.streamReader();
        var timeout = zio.Timeout.init;
        defer timeout.clear(self.rt);
        timeout.set(self.rt, self.read_timeout * std.time.ns_per_ms);
        while (true) {
            const size = reader.stream(&w, .limited(buf.len)) catch |err| {
                if (self.stream_ref.tls_client) |tls| {
                    if (tls.read_err) |read_err| {
                        std.debug.print("TLS read error: {}\n", .{read_err});
                        return err;
                    }
                }
                if (self.stream_ref.reader.err) |stream_err| {
                    std.debug.print("Stream read error: {}\n", .{stream_err});
                }
                return err;
            };
            if (size > 0) {
                return size;
            }
        }
        unreachable;
    }

    pub fn writeAll(self: *AsyncStream, data: []const u8) !void {
        var writer = self.streamWriter();
        var timeout = zio.Timeout.init;
        defer timeout.clear(self.rt);
        timeout.set(self.rt, self.write_timeout * std.time.ns_per_ms);
        try writer.writeAll(data);
        writer.flush() catch |err| {
            return handleWriterError(self, err);
        };
        self.stream_ref.writer.interface.flush() catch |err| {
            return handleWriterError(self, err);
        };
    }

    fn handleWriterError(self: *AsyncStream, flush_err: anyerror) !void {
        if (self.stream_ref.writer.err) |stream_err| {
            std.debug.print("Stream Write error: {}\n", .{stream_err});
            return stream_err;
        }
        return flush_err;
    }

    pub fn writeTimeout(self: *AsyncStream, ms: u64) !void {
        self.write_timeout = ms;
    }

    pub fn readTimeout(self: *AsyncStream, ms: u64) !void {
        self.read_timeout = ms;
    }
};
