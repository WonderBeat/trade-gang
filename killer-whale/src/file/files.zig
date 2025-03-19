const std = @import("std");

pub fn write_file(filePath: []const u8, buffer: []const u8) !void {
    var file = try std.fs.createFileAbsolute(filePath, .{ .truncate = true });
    defer file.close();
    var bw = std.io.bufferedWriter(file.writer());
    _ = try bw.write(buffer);
    try bw.flush();
}
