const std = @import("std");
const protos = @import("proto/protos.pb.zig");
const protobuf = @import("protobuf");
const os = std.os;
const posix = std.posix;
const bin = @import("binance.zig");
const parse = @import("parsers.zig");

pub fn sendAnnounce(allocator: std.mem.Allocator, address: std.net.Address, announce: *const bin.Announce) !usize {
    const coins = try parse.extractCoins(allocator, announce.title);
    defer allocator.free(coins);
    const isImportant = parse.isAnnounceImportant(announce.title) >= 3;
    var array = std.ArrayList(protobuf.ManagedString).init(allocator);
    defer array.deinit();
    for (coins) |token| {
        try array.append(protobuf.ManagedString.managed(token));
    }
    const managed_title = protobuf.ManagedString.managed(announce.title);
    const announceProto = protos.Announcement{
        .ts = @intCast(announce.releaseDate), //
        .tokens = array,
        .catalog = announce.catalogId,
        .title = managed_title,
        .call_to_action = isImportant,
    };

    const tpe: u32 = posix.SOCK.DGRAM;
    const protocol = posix.IPPROTO.UDP;
    const socket = try posix.socket(posix.AF.INET, tpe, protocol);
    defer posix.close(socket);
    try std.posix.connect(socket, &address.any, address.getOsSockLen());

    const byteArray = try announceProto.encode(allocator);
    std.debug.assert(byteArray.len < 1300);
    defer allocator.free(byteArray);

    const send_bytes = try posix.send(socket, byteArray, 0);
    return send_bytes;
}
