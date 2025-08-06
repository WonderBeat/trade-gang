const std = @import("std");
const testing = std.testing;
const expect = std.testing.expect;

pub const Pages = struct {
    pub const PageDecl = struct { size: u16, maxOffsetAvailable: u16 };
    pages: []const PageDecl,
    total: u32,

    pub fn init(pages: []const PageDecl) Pages {
        var offsetsSum: u32 = 0;
        for (pages) |page| {
            offsetsSum += page.maxOffsetAvailable;
        }
        std.debug.assert(offsetsSum > 0);
        return Pages{ .pages = pages, .total = offsetsSum };
    }

    pub const Page = struct { size: u16, offset: usize };
    pub fn atOffset(self: @This(), offset: usize) Page {
        var normalizedOffset = offset % self.total;
        for (self.pages) |page| {
            if (normalizedOffset >= page.maxOffsetAvailable) {
                normalizedOffset -= page.maxOffsetAvailable;
            } else {
                return Page{ .size = page.size, .offset = normalizedOffset + 1 };
            }
        }
        unreachable;
    }
};

test "Pages initialization" {
    const page_decls = [_]Pages.PageDecl{
        .{ .size = 100, .maxOffsetAvailable = 80 },
        .{ .size = 200, .maxOffsetAvailable = 150 },
        .{ .size = 300, .maxOffsetAvailable = 250 },
    };
    const pages = Pages.init(&page_decls);
    try testing.expectEqual(@as(u32, 480), pages.total);
}

test "Pages.atOffset basic functionality" {
    const page_decls = [_]Pages.PageDecl{
        .{ .size = 100, .maxOffsetAvailable = 80 },
        .{ .size = 200, .maxOffsetAvailable = 150 },
        .{ .size = 300, .maxOffsetAvailable = 250 },
    };

    const pages = Pages.init(&page_decls);

    // First page
    const page1 = pages.atOffset(50);
    try testing.expectEqual(@as(u16, 100), page1.size);
    try testing.expectEqual(@as(u16, 51), page1.offset);

    // Second page
    const page2 = pages.atOffset(100);
    try testing.expectEqual(@as(u16, 200), page2.size);
    try testing.expectEqual(@as(u16, 21), page2.offset);

    // Third page
    const page3 = pages.atOffset(300);
    try testing.expectEqual(@as(u16, 300), page3.size);
    try testing.expectEqual(@as(u16, 71), page3.offset);
}

test "Pages.atOffset wrapping behavior" {
    const page_decls = [_]Pages.PageDecl{
        .{ .size = 100, .maxOffsetAvailable = 80 },
        .{ .size = 200, .maxOffsetAvailable = 150 },
    };
    const pages = Pages.init(&page_decls);
    try testing.expectEqual(@as(u32, 230), pages.total);
    // Wrap around once
    const wrapped1 = pages.atOffset(250);
    try testing.expectEqual(@as(u16, 100), wrapped1.size);
    try testing.expectEqual(@as(u16, 21), wrapped1.offset);
    const wrapped2 = pages.atOffset(250 + 230 * 3);
    try testing.expectEqual(@as(u16, 100), wrapped2.size);
    try testing.expectEqual(@as(u16, 21), wrapped2.offset);
}

test "Pages with single page" {
    const page_decls = [_]Pages.PageDecl{
        .{ .size = 100, .maxOffsetAvailable = 80 },
    };
    const pages = Pages.init(&page_decls);
    try testing.expectEqual(@as(u32, 80), pages.total);
    const page = pages.atOffset(50);
    try testing.expectEqual(@as(u16, 100), page.size);
    try testing.expectEqual(@as(u16, 51), page.offset);
}
