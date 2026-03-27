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

    try std.testing.expectEqual(@as(usize, 4096), metadata.composition.grid.cells.len);
    try std.testing.expectEqual(@as(usize, 8145), metadata.composition.grid.spans.len);
    try std.testing.expectEqual(@as(usize, 5849), metadata.composition.grid.block_refs.len);
    try std.testing.expectEqual(@as(usize, 672), metadata.composition.grid.unique_offset_count);
    try std.testing.expectEqual(@as(usize, 2252), metadata.composition.grid.referenced_cell_count);
    try std.testing.expectEqual(@as(?background.GridBounds, .{
        .min_x = 0,
        .max_x = 63,
        .min_z = 12,
        .max_z = 63,
    }), metadata.composition.grid.reference_bounds);

    try std.testing.expectEqual(@as(usize, 219), metadata.composition.library.layouts.len);
    try std.testing.expectEqual(@as(usize, 1362), metadata.composition.library.layout_blocks.len);
    try std.testing.expectEqual(@as(usize, 45), metadata.composition.library.max_layout_block_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.composition.library.layouts[0].index);
    try std.testing.expectEqual(@as(u8, 1), metadata.composition.library.layouts[0].x);
    try std.testing.expectEqual(@as(u8, 8), metadata.composition.library.layouts[0].y);
    try std.testing.expectEqual(@as(u8, 1), metadata.composition.library.layouts[0].z);
    try std.testing.expectEqual(@as(usize, 45), metadata.composition.library.layouts[216].block_count);
    try std.testing.expectEqual(@as(u8, 3), metadata.composition.library.layouts[216].x);
    try std.testing.expectEqual(@as(u8, 5), metadata.composition.library.layouts[216].y);
    try std.testing.expectEqual(@as(u8, 3), metadata.composition.library.layouts[216].z);

    const first_referenced_cell = metadata.composition.grid.cells[12 * 64 + 59];
    try std.testing.expectEqual(@as(usize, 14), first_referenced_cell.non_empty_block_ref_count);
    try std.testing.expectEqual(@as(?usize, 1), first_referenced_cell.first_non_empty_block_ref_index);
    try std.testing.expectEqual(@as(?usize, 14), first_referenced_cell.last_non_empty_block_ref_index);

    const floor_block = metadata.composition.library.layout_blocks[metadata.composition.library.layouts[14].block_start];
    try std.testing.expectEqual(@as(u8, 1), floor_block.floorType());
    try std.testing.expectEqual(@as(u16, 667), floor_block.brick_index);

    try std.testing.expectEqual(@as(usize, 0), metadata.composition.fragments.fragments.len);
    try std.testing.expectEqual(@as(usize, 0), metadata.composition.fragments.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 0), metadata.composition.fragments.non_empty_cell_count);
    try std.testing.expectEqual(@as(u8, 0), metadata.composition.fragments.max_height);
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
    try std.testing.expect(std.mem.indexOf(u8, json, "\"referenced_cell_count\": 2252") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"layout_count\": 219") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fragment_count\": 0") != null);
}

test "real background 10 metadata keeps fragment ownership stable" {
    const allocator = std.testing.allocator;
    const target = try support.fixtureTargetById("interior-room-twinsens-house-background");
    const archive_path = try support.resolveBackgroundArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try background.loadBackgroundMetadata(allocator, archive_path, 10);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 10), metadata.entry_index);
    try std.testing.expectEqual(@as(usize, 10), metadata.remapped_cube_index);
    try std.testing.expectEqual(@as(usize, 11), metadata.gri_entry_index);
    try std.testing.expectEqual(@as(u8, 0), metadata.gri_header.my_grm);
    try std.testing.expectEqual(@as(usize, 149), metadata.grm_entry_index);
    try std.testing.expectEqual(@as(u8, 3), metadata.gri_header.my_bll);
    try std.testing.expectEqual(@as(usize, 182), metadata.bll_entry_index);
    try std.testing.expectEqual(@as(usize, 3573), metadata.composition.grid.referenced_cell_count);
    try std.testing.expectEqual(@as(usize, 203), metadata.composition.library.layouts.len);
    try std.testing.expectEqual(@as(usize, 42), metadata.composition.library.max_layout_block_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.composition.fragments.fragments.len);
    try std.testing.expectEqual(@as(usize, 208), metadata.composition.fragments.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 95), metadata.composition.fragments.non_empty_cell_count);
    try std.testing.expectEqual(@as(u8, 10), metadata.composition.fragments.max_height);

    const fragment = metadata.composition.fragments.fragments[0];
    try std.testing.expectEqual(@as(usize, 0), fragment.relative_index);
    try std.testing.expectEqual(@as(usize, 149), fragment.entry_index);
    try std.testing.expectEqual(@as(u8, 16), fragment.width);
    try std.testing.expectEqual(@as(u8, 10), fragment.height);
    try std.testing.expectEqual(@as(u8, 13), fragment.depth);
    try std.testing.expectEqual(@as(usize, 208), fragment.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 95), fragment.non_empty_cell_count);
    try std.testing.expectEqual(@as(?background.GridBounds, .{
        .min_x = 0,
        .max_x = 15,
        .min_z = 0,
        .max_z = 12,
    }), fragment.non_empty_bounds);
    try std.testing.expectEqual(@as(u8, 9), fragment.max_non_empty_column_height);
}
