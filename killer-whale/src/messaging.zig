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
    // var array = std.ArrayList([]const u8).initCapacity(allocator, 5);
    // defer array.deinit(allocator);
    const array = std.ArrayList([]const u8).fromOwnedSlice(coins[0..]);
    // for (coins) |token| {
    //     try array.append(allocator, token);
    // }
    const announceProto = protos.Announcement{
        .ts = @intCast(announce.releaseDate), //
        .tokens = array,
        .catalog = announce.catalogId,
        .title = announce.title,
        .call_to_action = isImportant,
    };

    const tpe: u32 = posix.SOCK.DGRAM;
    const protocol = posix.IPPROTO.UDP;
    const socket = try posix.socket(posix.AF.INET, tpe, protocol);
    defer posix.close(socket);
    try std.posix.connect(socket, &address.any, address.getOsSockLen());

    var writer = try std.Io.Writer.Allocating.initCapacity(allocator, 500);
    errdefer writer.deinit();
    try announceProto.encode(&writer.writer, allocator);
    var byteArray = writer.toArrayList();
    defer byteArray.deinit(allocator);
    std.debug.assert(byteArray.items.len < 1300);

    const send_bytes = try posix.send(socket, byteArray.items, 0);
    return send_bytes;
}
