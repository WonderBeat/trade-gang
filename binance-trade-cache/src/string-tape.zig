const std = @import("std");

pub const StringTape = struct {
    buffer: []u8,
    position: usize,

    pub fn init(buffer: []u8) StringTape {
        return StringTape{
            .buffer = buffer,
            .position = 0,
        };
    }

    pub fn write(self: *StringTape, str: []const u8) ![]u8 {
        if (str.len > self.buffer.len) {
            return error.StringTooLong;
        }

        // If we're going to overflow, check if we can fit at the beginning
        if (self.position + str.len > self.buffer.len) {
            if (str.len > self.buffer.len) {
                return error.StringTooLong;
            }
            self.position = 0;
        }

        @memcpy(self.buffer[self.position .. self.position + str.len], str);

        const result = self.buffer[self.position .. self.position + str.len];
        self.position += str.len;

        return result;
    }

    pub fn reset(self: *StringTape) void {
        self.position = 0;
    }
};

test "StringTape basic functionality" {
    var buffer: [128]u8 = undefined;
    var tape = StringTape.init(buffer[0..]);

    const str1 = try tape.write("Hello, ");
    try std.testing.expectEqualStrings("Hello, ", str1);

    const str2 = try tape.write("World!");
    try std.testing.expectEqualStrings("World!", str2);

    // Test wrapping around
    tape.position = tape.buffer.len - 3; // Position near the end
    const str3 = try tape.write("ABC");
    try std.testing.expectEqualStrings("ABC", str3);

    // Reset and write again
    tape.reset();
    const str4 = try tape.write("Reset test");
    try std.testing.expectEqualStrings("Reset test", str4);
}

test "StringTape overflow behavior" {
    // Test when string is longer than the entire buffer
    var buffer: [10]u8 = undefined;
    var tape = StringTape.init(buffer[0..]);

    // Try to write a string longer than the buffer - should return error
    try std.testing.expectError(error.StringTooLong, tape.write("This string is too long for the buffer"));

    // Write something that fits
    const str1 = try tape.write("Hello");
    try std.testing.expectEqualStrings("Hello", str1);

    // Move position to near the end to test wraparound
    tape.position = 8; // Only 2 bytes left at the end (indices 8 and 9)

    // Write a 2-char string (should fit in the last 2 positions)
    const str2 = try tape.write("AB"); // This fits at positions 8,9
    try std.testing.expectEqualStrings("AB", str2);
    try std.testing.expect(tape.position == 10); // Position should now be 10 (after "AB")

    // Now try to write a string that won't fit, causing wraparound to beginning
    const str3 = try tape.write("C"); // Buffer is full, so this should wrap to beginning
    try std.testing.expectEqualStrings("C", str3);
    try std.testing.expect(tape.position == 1); // Position should now be 1 (after "C" at start)

    // Move to a position where a larger string will cause wrap-around
    tape.position = 9; // Only 1 byte left

    // Try to write something that won't fit at current position
    // "DEF" is 3 chars but only 1 position left, so it should wrap to beginning
    const str4 = try tape.write("DEF"); // This will wrap to beginning
    try std.testing.expectEqualStrings("DEF", str4);
    try std.testing.expect(tape.position == 3); // Position should now be 3 (after "DEF" at start)
}
