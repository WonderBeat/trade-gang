const std = @import("std");
const builtin = @import("builtin");

pub fn partitionArray(comptime T: type, arr: []const T, partitions: usize, allocator: std.mem.Allocator) ![]([]const T) {
    if (partitions == 0 or arr.len == 0) return &[_][]const T{};
    const result = try allocator.alloc([]const T, partitions);
    const base_size = arr.len / partitions;
    const remainder = arr.len % partitions;
    var start: usize = 0;
    for (result, 0..) |*slice, i| {
        const extra: usize = if (i < remainder) 1 else 0;
        const size = base_size + extra;
        slice.* = arr[start .. start + size];
        start += size;
    }
    return result;
}

test "partitionArray partitions array correctly" {
    const allocator = std.testing.allocator;
    const arr = [_]u32{ 1, 2, 3, 4, 5, 6, 7 };
    const partitions = 3;
    const slices = try partitionArray(u32, &arr, partitions, allocator);
    defer allocator.free(slices);

    try std.testing.expectEqual(@as(usize, partitions), slices.len);
    try std.testing.expectEqualSlices(u32, slices[0], &[_]u32{ 1, 2, 3 });
    try std.testing.expectEqualSlices(u32, slices[1], &[_]u32{ 4, 5 });
    try std.testing.expectEqualSlices(u32, slices[2], &[_]u32{ 6, 7 });
}
