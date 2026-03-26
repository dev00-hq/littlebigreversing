const std = @import("std");
const parser = @import("../parser.zig");

test "bkg header payload must match the exact struct size" {
    try std.testing.expectError(error.TruncatedBkgHeader, parser.parseBkgHeaderPayload(&.{ 0x01, 0x00 }));

    const too_long = [_]u8{
        0x01, 0x00, 0x95, 0x00, 0xB3, 0x00, 0xC5, 0x00,
        0xEF, 0x45, 0x7E, 0x00, 0x0F, 0x6A, 0x00, 0x00,
        0x54, 0x37, 0x00, 0x00, 0x6A, 0xE9, 0x05, 0x00,
        0x93, 0x52, 0x01, 0x00, 0xFF,
    };
    try std.testing.expectError(error.TrailingBkgHeaderBytes, parser.parseBkgHeaderPayload(&too_long));
}

test "tab all cube payload fails fast on malformed sizes or indices" {
    try std.testing.expectError(error.InvalidTabAllCubePayloadSize, parser.parseTabAllCubePayload(&.{0x01}, 0));
    try std.testing.expectError(error.InvalidBackgroundEntryIndex, parser.parseTabAllCubePayload(&.{ 0x01, 0x02 }, 1));
}

test "gri payload validates header and column-table shape" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.TruncatedGriHeader, parser.parseGriPayload(allocator, &.{ 0x00, 0x01 }));

    var too_short_column_table = try allocator.alloc(u8, 34 + 16);
    defer allocator.free(too_short_column_table);
    @memset(too_short_column_table, 0);
    too_short_column_table[0] = 1;
    too_short_column_table[1] = 2;
    try std.testing.expectError(error.TruncatedGriColumnTable, parser.parseGriPayload(allocator, too_short_column_table));

    var invalid_offset_payload = try allocator.alloc(u8, 34 + 8192 + 8);
    defer allocator.free(invalid_offset_payload);
    @memset(invalid_offset_payload, 0);
    invalid_offset_payload[0] = 1;
    invalid_offset_payload[1] = 2;
    for (0..4096) |index| {
        const byte_offset = 34 + (index * 2);
        std.mem.writeInt(u16, invalid_offset_payload[byte_offset .. byte_offset + 2][0..2], 32, .little);
    }
    try std.testing.expectError(error.InvalidGriColumnOffset, parser.parseGriPayload(allocator, invalid_offset_payload));
}

test "bll payload validates truncation and offset consistency" {
    try std.testing.expectError(error.TruncatedBllTable, parser.parseBllPayload(&.{ 0x10, 0x00 }));

    const invalid_header = [_]u8{
        0x02, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
    };
    try std.testing.expectError(error.InvalidBllTableHeader, parser.parseBllPayload(&invalid_header));

    const invalid_offset = [_]u8{
        0x08, 0x00, 0x00, 0x00,
        0x04, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
    };
    try std.testing.expectError(error.InvalidBllBlockOffset, parser.parseBllPayload(&invalid_offset));
}
