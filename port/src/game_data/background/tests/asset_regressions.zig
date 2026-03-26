const std = @import("std");
const background = @import("../../background.zig");
const support = @import("support.zig");

test "real background 2 metadata matches the canonical interior linkage" {
    const allocator = std.testing.allocator;
    const target = try support.fixtureTargetById("interior-room-twinsens-house-background");
    const archive_path = try support.resolveBackgroundArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try background.loadBackgroundMetadata(allocator, archive_path, target.entry_index);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), metadata.entry_index);
    try std.testing.expectEqual(@as(usize, 0), metadata.header_entry_index);
    try std.testing.expectEqual(@as(u32, 28), metadata.header_compressed_header.size_file);
    try std.testing.expectEqual(@as(u32, 28), metadata.header_compressed_header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 0), metadata.header_compressed_header.compress_method);

    try std.testing.expectEqual(@as(u16, 1), metadata.bkg_header.gri_start);
    try std.testing.expectEqual(@as(u16, 149), metadata.bkg_header.grm_start);
    try std.testing.expectEqual(@as(u16, 179), metadata.bkg_header.bll_start);
    try std.testing.expectEqual(@as(u16, 197), metadata.bkg_header.brk_start);
    try std.testing.expectEqual(@as(u16, 17903), metadata.bkg_header.max_brk);
    try std.testing.expectEqual(@as(u16, 126), metadata.bkg_header.forbiden_brick);
    try std.testing.expectEqual(@as(u32, 27151), metadata.bkg_header.max_size_gri);
    try std.testing.expectEqual(@as(u32, 14164), metadata.bkg_header.max_size_bll);
    try std.testing.expectEqual(@as(u32, 387434), metadata.bkg_header.max_size_brick_cube);
    try std.testing.expectEqual(@as(u32, 86675), metadata.bkg_header.max_size_mask_brick_cube);

    try std.testing.expectEqual(@as(usize, 18100), metadata.tab_all_cube_entry_index);
    try std.testing.expectEqual(@as(u32, 512), metadata.tab_all_cube_compressed_header.size_file);
    try std.testing.expectEqual(@as(u16, 0), metadata.tab_all_cube_compressed_header.compress_method);
    try std.testing.expectEqual(@as(usize, 256), metadata.tab_all_cube_entry_count);
    try std.testing.expectEqual(@as(u8, 1), metadata.tab_all_cube.type_id);
    try std.testing.expectEqual(@as(u8, 2), metadata.tab_all_cube.num);
    try std.testing.expectEqual(@as(usize, 2), metadata.remapped_cube_index);

    try std.testing.expectEqual(@as(usize, 3), metadata.gri_entry_index);
    try std.testing.expectEqual(@as(u32, 17978), metadata.gri_compressed_header.size_file);
    try std.testing.expectEqual(@as(u32, 8332), metadata.gri_compressed_header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 1), metadata.gri_compressed_header.compress_method);
    try std.testing.expectEqual(@as(u8, 1), metadata.gri_header.my_bll);
    try std.testing.expectEqual(@as(u8, 0), metadata.gri_header.my_grm);
    try std.testing.expectEqual(@as(usize, 64), metadata.column_table.width);
    try std.testing.expectEqual(@as(usize, 64), metadata.column_table.depth);
    try std.testing.expectEqual(@as(usize, 4096), metadata.column_table.offset_count);
    try std.testing.expectEqual(@as(usize, 8192), metadata.column_table.table_byte_length);
    try std.testing.expect(metadata.column_table.data_byte_length > 0);
    try std.testing.expect(metadata.column_table.min_offset >= metadata.column_table.table_byte_length);
    try std.testing.expect(metadata.column_table.max_offset < metadata.column_table.table_byte_length + metadata.column_table.data_byte_length);
    try std.testing.expectEqual(@as(usize, 105), metadata.used_blocks.used_block_ids.len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 7 }, metadata.used_blocks.used_block_ids[0..6]);

    try std.testing.expectEqual(@as(usize, 149), metadata.grm_entry_index);
    try std.testing.expectEqual(@as(usize, 180), metadata.bll_entry_index);
    try std.testing.expectEqual(@as(u32, 6981), metadata.bll_compressed_header.size_file);
    try std.testing.expectEqual(@as(u32, 5039), metadata.bll_compressed_header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 1), metadata.bll_compressed_header.compress_method);
    try std.testing.expectEqual(@as(usize, 219), metadata.bll.block_count);
    try std.testing.expectEqual(@as(u32, 876), metadata.bll.table_byte_length);
    try std.testing.expectEqual(@as(u32, 876), metadata.bll.first_block_offset);
    try std.testing.expectEqual(@as(u32, 6962), metadata.bll.last_block_offset);
}

test "background metadata json keeps linkage and table summaries stable" {
    const allocator = std.testing.allocator;
    const target = try support.fixtureTargetById("interior-room-twinsens-house-background");
    const archive_path = try support.resolveBackgroundArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try background.loadBackgroundMetadata(allocator, archive_path, target.entry_index);
    defer metadata.deinit(allocator);

    const json = try support.stringifyJsonAlloc(allocator, metadata);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"tab_all_cube_entry_index\": 18100") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"remapped_cube_index\": 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"gri_entry_index\": 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bll_entry_index\": 180") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"width\": 64") != null);
}
