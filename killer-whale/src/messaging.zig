const std = @import("std");
const protos = @import("proto/protos.pb.zig");
const protobuf = @import("protobuf");
const os = std.os;
const posix = std.posix;

const port = 6969;

pub fn send_announce(allocator: std.mem.Allocator, address: std.net.Address, tokens: *const []const []const u8) !usize {
    var array = std.ArrayList(protobuf.ManagedString).init(allocator);
    defer array.deinit();

    for (tokens.*) |token| {
        try array.append(protobuf.ManagedString.managed(token));
    }
    const announce = protos.Announcement{
        .ts = @intCast(std.time.timestamp()), //
        .tokens = array,
    };

    const tpe: u32 = posix.SOCK.DGRAM;
    const protocol = posix.IPPROTO.UDP;
    const socket = try posix.socket(posix.AF.INET, tpe, protocol);
    defer posix.close(socket);
    try std.posix.connect(socket, &address.any, address.getOsSockLen());

    const byteArray = try announce.encode(allocator);
    defer allocator.free(byteArray);

    const send_bytes = try posix.send(socket, byteArray, 0);

    std.log.debug("Sent {d} bytes to {}", .{ send_bytes, address });
    return send_bytes;
}
