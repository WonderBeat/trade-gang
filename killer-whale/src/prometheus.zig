const std = @import("std");

const m = @import("metrics");

var metrics = m.initializeNoop(Metrics);

const Metrics = struct {
    hits: m.Counter(u32),
    errors: m.Counter(u32),
    latest: m.Gauge(u32),
    latency: Latency,
    timeout: m.Counter(u32),
    sslError: m.Counter(u32),

    const Latency = m.Histogram(u16, &.{ 100, 200, 400, 600, 800, 1000, 1500, 3000 });
};

pub fn hit() void {
    metrics.hits.incr();
}

pub fn timeout() void {
    metrics.timeout.incr();
}

pub fn sslError() void {
    metrics.sslError.incr();
}

pub fn err() void {
    metrics.errors.incr();
}

pub fn latest(value: u32) void {
    metrics.latest.set(value);
}

pub fn latency(value: u16) void {
    metrics.latency.observe(value);
}

pub fn initializeMetrics(comptime opts: m.RegistryOpts) !void {
    metrics = .{
        .hits = m.Counter(u32).init("hits", .{}, opts),
        .errors = m.Counter(u32).init("errors", .{}, opts),
        .timeout = m.Counter(u32).init("timeout", .{}, opts),
        .sslError = m.Counter(u32).init("ssl_err", .{}, opts),
        .latest = m.Gauge(u32).init("latest", .{}, opts),
        .latency = Metrics.Latency.init("latency", .{}, opts),
    };
}

// thread safe
pub fn writeMetrics(writer: anytype) !void {
    return m.write(&metrics, writer);
}
