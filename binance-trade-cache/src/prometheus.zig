const std = @import("std");

const m = @import("metrics");

var metrics = m.initializeNoop(Metrics);

const Metrics = struct {
    processed: m.Counter(u32),
    restarts: m.Counter(u32),
    latency: m.Gauge(i64),
};

pub fn processed() void {
    metrics.processed.incr();
}

pub fn restarts() void {
    metrics.restarts.incr();
}

pub fn latency(value: i64) void {
    metrics.latency.set(value);
}

pub fn initializeMetrics(comptime opts: m.RegistryOpts) !void {
    metrics = .{
        .processed = m.Counter(u32).init("processed", .{}, opts),
        .restarts = m.Counter(u32).init("restarts", .{}, opts),
        .latency = m.Gauge(i64).init("latency", .{}, opts),
    };
}

// thread safe
pub fn writeMetrics(writer: *std.Io.Writer) !void {
    return m.write(&metrics, writer);
}

pub fn dumpToFile() !void {
    const file = try std.fs.cwd().createFile("metrics.prometheus", .{});
    defer file.close();
    var buffer: [500]u8 = undefined;
    var writer = file.writer(&buffer).interface;
    try writeMetrics(&writer);
}
