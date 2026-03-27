const std = @import("std");
const background = @import("../../background.zig");
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

    var invalid_mode_payload = try allocator.alloc(u8, 34 + 8192 + 2);
    defer allocator.free(invalid_mode_payload);
    @memset(invalid_mode_payload, 0);
    invalid_mode_payload[0] = 1;
    invalid_mode_payload[1] = 2;
    for (0..4096) |index| {
        const byte_offset = 34 + (index * 2);
        std.mem.writeInt(u16, invalid_mode_payload[byte_offset .. byte_offset + 2][0..2], 8192, .little);
    }
    invalid_mode_payload[34 + 8192] = 1;
    invalid_mode_payload[34 + 8193] = 0xC0;
    try std.testing.expectError(error.UnsupportedGriColumnEncoding, parser.parseGriPayload(allocator, invalid_mode_payload));

    var truncated_column_payload = try allocator.alloc(u8, 34 + 8192 + 2);
    defer allocator.free(truncated_column_payload);
    @memset(truncated_column_payload, 0);
    truncated_column_payload[0] = 1;
    truncated_column_payload[1] = 2;
    for (0..4096) |index| {
        const byte_offset = 34 + (index * 2);
        std.mem.writeInt(u16, truncated_column_payload[byte_offset .. byte_offset + 2][0..2], 8192, .little);
    }
    truncated_column_payload[34 + 8192] = 1;
    truncated_column_payload[34 + 8193] = 0x40;
    try std.testing.expectError(error.TruncatedGriColumnPayload, parser.parseGriPayload(allocator, truncated_column_payload));
}

test "bll payload validates truncation and offset consistency" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.TruncatedBllTable, parser.parseBllPayload(allocator, &.{ 0x10, 0x00 }));

    const invalid_header = [_]u8{
        0x02, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
    };
    try std.testing.expectError(error.InvalidBllTableHeader, parser.parseBllPayload(allocator, &invalid_header));

    const invalid_offset = [_]u8{
        0x08, 0x00, 0x00, 0x00,
        0x04, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
    };
    try std.testing.expectError(error.InvalidBllBlockOffset, parser.parseBllPayload(allocator, &invalid_offset));

    const zero_dims = [_]u8{
        0x08, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x01,
    };
    try std.testing.expectError(error.InvalidBllLayoutDimensions, parser.parseBllPayload(allocator, &zero_dims));

    const truncated_layout = [_]u8{
        0x08, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
        0x01, 0x01, 0x01,
        0x01, 0x00,
    };
    try std.testing.expectError(error.TruncatedBllLayoutBlocks, parser.parseBllPayload(allocator, &truncated_layout));

    const valid_payload = [_]u8{
        0x04, 0x00, 0x00, 0x00,
        0x01, 0x01, 0x01,
        0x02, 0x31, 0x34, 0x12,
    };
    var parsed = try parser.parseBllPayload(allocator, &valid_payload);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), parsed.metadata.block_count);
    try std.testing.expectEqual(@as(usize, 1), parsed.library.layouts.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.library.layout_blocks.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.library.layouts[0].block_count);
    try std.testing.expectEqual(@as(u8, 2), parsed.library.layout_blocks[0].shape);
    try std.testing.expectEqual(@as(u8, 3), parsed.library.layout_blocks[0].floorType());
    try std.testing.expectEqual(@as(u8, 1), parsed.library.layout_blocks[0].soundId());
    try std.testing.expectEqual(@as(u16, 0x1234), parsed.library.layout_blocks[0].brick_index);
}

test "fragment payload validates truncation and keeps footprint summaries stable" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.TruncatedGrmFragment, parser.parseFragmentPayload(allocator, &.{ 0x01, 0x02 }, 0, 149));

    const truncated_payload = [_]u8{
        0x02, 0x02, 0x01,
        0x01, 0x00,
        0x00, 0x00,
        0x01, 0x00,
    };
    try std.testing.expectError(error.TruncatedGrmFragmentPayload, parser.parseFragmentPayload(allocator, &truncated_payload, 0, 149));

    const too_long_payload = [_]u8{
        0x01, 0x01, 0x01,
        0x01, 0x00,
        0xFF,
    };
    try std.testing.expectError(error.InvalidGrmFragmentSize, parser.parseFragmentPayload(allocator, &too_long_payload, 0, 149));

    const valid_payload = [_]u8{
        0x02, 0x02, 0x01,
        0x01, 0x00,
        0x00, 0x00,
        0x02, 0x03,
        0x02, 0x04,
    };
    var parsed = try parser.parseFragmentPayload(allocator, &valid_payload, 2, 151);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.relative_index);
    try std.testing.expectEqual(@as(usize, 151), parsed.entry_index);
    try std.testing.expectEqual(@as(u8, 2), parsed.width);
    try std.testing.expectEqual(@as(u8, 2), parsed.height);
    try std.testing.expectEqual(@as(u8, 1), parsed.depth);
    try std.testing.expectEqual(@as(usize, 2), parsed.cells.len);
    try std.testing.expectEqual(@as(usize, 4), parsed.block_refs.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 2), parsed.non_empty_cell_count);
    try std.testing.expectEqual(@as(?background.GridBounds, .{
        .min_x = 0,
        .max_x = 1,
        .min_z = 0,
        .max_z = 0,
    }), parsed.non_empty_bounds);
    try std.testing.expectEqual(@as(u8, 2), parsed.max_non_empty_column_height);
    try std.testing.expectEqual(@as(?usize, 0), parsed.cells[0].first_non_empty_block_ref_index);
    try std.testing.expectEqual(@as(?usize, 0), parsed.cells[0].last_non_empty_block_ref_index);
    try std.testing.expectEqual(@as(?usize, 2), parsed.cells[1].first_non_empty_block_ref_index);
    try std.testing.expectEqual(@as(?usize, 3), parsed.cells[1].last_non_empty_block_ref_index);
}

test "palette payload must match the main 256-color layout" {
    try std.testing.expectError(error.TruncatedPalettePayload, parser.parsePalettePayload(&.{ 0x00, 0x01, 0x02 }));

    var too_long = [_]u8{0} ** 769;
    try std.testing.expectError(error.TrailingPaletteBytes, parser.parsePalettePayload(&too_long));

    var payload = [_]u8{0} ** 768;
    payload[0] = 0x01;
    payload[1] = 0x02;
    payload[2] = 0x03;
    payload[765] = 0xAA;
    payload[766] = 0xBB;
    payload[767] = 0xCC;

    const palette = try parser.parsePalettePayload(&payload);
    try std.testing.expectEqual(background.BrickSwatchPixel{ .r = 0x01, .g = 0x02, .b = 0x03, .a = 255 }, palette[0]);
    try std.testing.expectEqual(background.BrickSwatchPixel{ .r = 0xAA, .g = 0xBB, .b = 0xCC, .a = 255 }, palette[255]);
}

test "brick payload decodes deterministic swatch previews from explicit and repeated lines" {
    const allocator = std.testing.allocator;

    var palette = [_]background.BrickSwatchPixel{.{ .r = 0, .g = 0, .b = 0, .a = 255 }} ** 256;
    palette[4] = .{ .r = 0x20, .g = 0x10, .b = 0x08, .a = 255 };
    palette[5] = .{ .r = 0x40, .g = 0x30, .b = 0x20, .a = 255 };
    palette[6] = .{ .r = 0x80, .g = 0x60, .b = 0x40, .a = 255 };

    try std.testing.expectError(error.TruncatedBrickHeader, parser.parseBrickPayload(allocator, &.{ 0x02, 0x02, 0x00 }, palette, 7, 203));

    const invalid_line = [_]u8{
        0x02, 0x01, 0x00, 0x00,
        0x01,
        0x42,
        0x04, 0x05, 0x06,
    };
    try std.testing.expectError(error.InvalidBrickLineWidth, parser.parseBrickPayload(allocator, &invalid_line, palette, 7, 203));

    const valid_payload = [_]u8{
        0x02, 0x02, 0x01, 0x02,
        0x01,
        0x41, 0x04, 0x05,
        0x02,
        0x00,
        0x80, 0x06,
    };
    const preview = try parser.parseBrickPayload(allocator, &valid_payload, palette, 7, 203);

    try std.testing.expectEqual(@as(u16, 7), preview.brick_index);
    try std.testing.expectEqual(@as(usize, 203), preview.entry_index);
    try std.testing.expectEqual(@as(u8, 2), preview.width);
    try std.testing.expectEqual(@as(u8, 2), preview.height);
    try std.testing.expectEqual(@as(u8, 1), preview.offset_x);
    try std.testing.expectEqual(@as(u8, 2), preview.offset_y);
    try std.testing.expectEqual(@as(usize, 3), preview.opaque_pixel_count);
    try std.testing.expectEqual(@as(usize, 3), preview.unique_color_count);
    try std.testing.expectEqual(background.BrickSwatchPixel{ .r = 0x20, .g = 0x10, .b = 0x08, .a = 255 }, preview.swatch[0]);
    try std.testing.expectEqual(background.BrickSwatchPixel{ .r = 0x40, .g = 0x30, .b = 0x20, .a = 255 }, preview.swatch[background.brick_preview_swatch_side - 1]);
    try std.testing.expectEqual(@as(u8, 0), preview.swatch[(background.brick_preview_swatch_pixel_count - background.brick_preview_swatch_side)].a);
    try std.testing.expectEqual(background.BrickSwatchPixel{ .r = 0x80, .g = 0x60, .b = 0x40, .a = 255 }, preview.swatch[background.brick_preview_swatch_pixel_count - 1]);
}
