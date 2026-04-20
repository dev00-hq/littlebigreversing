const std = @import("std");

pub const CursorState = enum {
    inside_record,
    at_terminator,
    after_record,
};

pub const CursorSplit = struct {
    text_before_cursor: []const u8,
    text_from_cursor: []const u8,
    cursor_state: CursorState,
    cursor_is_next_page_boundary: bool,
};

pub fn splitTextAtCursor(text: []const u8, cursor_offset: usize) CursorSplit {
    if (cursor_offset >= text.len) {
        return .{
            .text_before_cursor = text,
            .text_from_cursor = "",
            .cursor_state = if (cursor_offset == text.len) .at_terminator else .after_record,
            .cursor_is_next_page_boundary = false,
        };
    }

    return .{
        .text_before_cursor = text[0..cursor_offset],
        .text_from_cursor = text[cursor_offset..],
        .cursor_state = .inside_record,
        .cursor_is_next_page_boundary = text[cursor_offset..].len != 0,
    };
}

test "splitTextAtCursor treats in-record offsets as next-page boundaries" {
    const split = splitTextAtCursor("ABCD", 2);
    try std.testing.expectEqualStrings("AB", split.text_before_cursor);
    try std.testing.expectEqualStrings("CD", split.text_from_cursor);
    try std.testing.expectEqual(CursorState.inside_record, split.cursor_state);
    try std.testing.expect(split.cursor_is_next_page_boundary);
}

test "splitTextAtCursor treats the record end as a terminator" {
    const split = splitTextAtCursor("ABCD", 4);
    try std.testing.expectEqualStrings("ABCD", split.text_before_cursor);
    try std.testing.expectEqualStrings("", split.text_from_cursor);
    try std.testing.expectEqual(CursorState.at_terminator, split.cursor_state);
    try std.testing.expect(!split.cursor_is_next_page_boundary);
}
