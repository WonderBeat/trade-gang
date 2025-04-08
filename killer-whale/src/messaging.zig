const std = @import("std");
const protos = @import("proto/protos.pb.zig");
const protobuf = @import("protobuf");
const os = std.os;
const posix = std.posix;

pub fn send_announce(allocator: std.mem.Allocator, address: std.net.Address, tokens: *const []const []const u8, ts: i64, catalog: u16, title: *const []const u8) !usize {
    var array = std.ArrayList(protobuf.ManagedString).init(allocator);
    defer array.deinit();

    for (tokens.*) |token| {
        try array.append(protobuf.ManagedString.managed(token));
    }
    const managed_title = protobuf.ManagedString.managed(title.*[0..@min(title.len, 40)]);
    const announce = protos.Announcement{
        .ts = @intCast(ts), //
        .tokens = array,
        .catalog = catalog,
        .title = managed_title,
    };

    const tpe: u32 = posix.SOCK.DGRAM;
    const protocol = posix.IPPROTO.UDP;
    const socket = try posix.socket(posix.AF.INET, tpe, protocol);
    defer posix.close(socket);
    try std.posix.connect(socket, &address.any, address.getOsSockLen());

    const byteArray = try announce.encode(allocator);
    defer allocator.free(byteArray);

    const send_bytes = try posix.send(socket, byteArray, 0);
    return send_bytes;
}
