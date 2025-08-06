const simdjzon = @import("simdjzon");
const std = @import("std");
const expect = std.testing.expect;

test "at_pointer" {
    const input =
        \\{"a": {"b": [1,2,3]}}
    ;
    const allr = std.testing.allocator;
    var parser = try simdjzon.dom.Parser.initFixedBuffer(allr, input, .{});
    defer parser.deinit();
    try parser.parse();
    const b0 = try parser.element().at_pointer("/a/b/0");
    try std.testing.expectEqual(@as(i64, 1), try b0.get_int64());
}
