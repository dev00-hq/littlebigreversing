const std = @import("std");
const paths_mod = @import("../../foundation/paths.zig");
const background_data = @import("../../game_data/background.zig");
const scene_data = @import("../../game_data/scene.zig");
const state = @import("state.zig");

fn sumFloorTypeCounts(counts: [16]usize) usize {
    var total: usize = 0;
    for (counts) |count| total += count;
    return total;
}

fn findCompositionTile(tiles: []const state.CompositionTileSnapshot, x: usize, z: usize) ?state.CompositionTileSnapshot {
    for (tiles) |tile| {
        if (tile.x == x and tile.z == z) return tile;
    }
    return null;
}

fn findFirstNonEmptyFragmentCell(cells: []const state.FragmentZoneCellSnapshot) ?state.FragmentZoneCellSnapshot {
    for (cells) |cell| {
        if (cell.has_non_empty) return cell;
    }
    return null;
}

test "viewer shape classifier stays aligned with the checked-in layout docs" {
    try std.testing.expectEqual(state.SurfaceShapeClass.open, state.classifySurfaceShape(0));
    try std.testing.expectEqual(state.SurfaceShapeClass.solid, state.classifySurfaceShape(1));
    try std.testing.expectEqual(state.SurfaceShapeClass.single_stair, state.classifySurfaceShape(2));
    try std.testing.expectEqual(state.SurfaceShapeClass.single_stair, state.classifySurfaceShape(5));
    try std.testing.expectEqual(state.SurfaceShapeClass.double_stair_corner, state.classifySurfaceShape(6));
    try std.testing.expectEqual(state.SurfaceShapeClass.double_stair_corner, state.classifySurfaceShape(9));
    try std.testing.expectEqual(state.SurfaceShapeClass.double_stair_peak, state.classifySurfaceShape(0x0A));
    try std.testing.expectEqual(state.SurfaceShapeClass.double_stair_peak, state.classifySurfaceShape(0x0D));
    try std.testing.expectEqual(state.SurfaceShapeClass.weird, state.classifySurfaceShape(0x0E));
}

test "viewer fragment zones project canonical cell coverage from scene bounds" {
    const allocator = std.testing.allocator;

    const layouts = try allocator.dupe(background_data.Layout, &.{
        .{ .index = 1, .start_offset = 0, .byte_length = 7, .x = 1, .y = 1, .z = 1, .block_start = 0, .block_count = 1 },
    });
    defer allocator.free(layouts);

    const layout_blocks = try allocator.dupe(background_data.LayoutBlock, &.{
        .{ .shape = 2, .sound_floor = 0x31, .brick_index = 123 },
    });
    defer allocator.free(layout_blocks);

    const library = background_data.LayoutLibrary{
        .layouts = layouts,
        .layout_blocks = layout_blocks,
        .max_layout_block_count = 1,
    };

    const fragment_cells = try allocator.dupe(background_data.FragmentCell, &.{
        .{ .x = 0, .z = 0, .block_ref_start = 0, .block_ref_count = 1, .non_empty_block_ref_count = 1, .first_non_empty_block_ref_index = 0, .last_non_empty_block_ref_index = 0 },
        .{ .x = 1, .z = 0, .block_ref_start = 1, .block_ref_count = 1, .non_empty_block_ref_count = 0, .first_non_empty_block_ref_index = null, .last_non_empty_block_ref_index = null },
    });
    const fragment_block_refs = try allocator.dupe(background_data.ColumnBlockRef, &.{
        .{ .layout_index = 1, .layout_block_index = 0 },
        .{ .layout_index = 0, .layout_block_index = 0 },
    });

    var fragments = background_data.FragmentLibrary{
        .fragments = try allocator.dupe(background_data.Fragment, &.{
            .{
                .relative_index = 0,
                .entry_index = 149,
                .width = 2,
                .height = 1,
                .depth = 1,
                .cells = fragment_cells,
                .block_refs = fragment_block_refs,
                .footprint_cell_count = 2,
                .non_empty_cell_count = 1,
                .non_empty_bounds = .{ .min_x = 0, .max_x = 0, .min_z = 0, .max_z = 0 },
                .max_non_empty_column_height = 1,
            },
        }),
        .footprint_cell_count = 2,
        .non_empty_cell_count = 1,
        .max_height = 1,
    };
    defer fragments.deinit(allocator);

    const zones = [_]scene_data.SceneZone{
        .{
            .x0 = 0,
            .y0 = 0,
            .z0 = 512,
            .x1 = 512,
            .y1 = 0,
            .z1 = 512,
            .raw_info = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
            .zone_type = .grm,
            .num = 7,
            .semantics = .{ .grm = .{ .grm_index = 0, .initially_on = true } },
        },
    };

    const projected = try state.buildFragmentZoneSnapshots(allocator, &zones, fragments, library);
    defer {
        for (projected) |zone| zone.deinit(allocator);
        allocator.free(projected);
    }

    try std.testing.expectEqual(@as(usize, 1), projected.len);
    try std.testing.expectEqual(@as(usize, 0), projected[0].origin_x);
    try std.testing.expectEqual(@as(usize, 1), projected[0].origin_z);
    try std.testing.expectEqual(@as(usize, 2), projected[0].width);
    try std.testing.expectEqual(@as(usize, 1), projected[0].depth);
    try std.testing.expectEqual(@as(usize, 2), projected[0].cells.len);
    try std.testing.expectEqual(state.FragmentZoneCellSnapshot{
        .x = 0,
        .z = 1,
        .has_non_empty = true,
        .stack_depth = 1,
        .top_floor_type = 3,
        .top_shape = 2,
        .top_shape_class = .single_stair,
        .top_brick_index = 123,
    }, projected[0].cells[0]);
    try std.testing.expectEqual(state.FragmentZoneCellSnapshot{
        .x = 1,
        .z = 1,
        .has_non_empty = false,
        .stack_depth = 0,
        .top_floor_type = 0,
        .top_shape = 0,
        .top_shape_class = .open,
        .top_brick_index = 0,
    }, projected[0].cells[1]);
}

test "viewer room snapshot keeps the canonical interior pair stable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(?usize, 0), room.scene.classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", room.scene.scene_kind);
    try std.testing.expectEqual(@as(i16, 9724), room.scene.hero_start.x);
    try std.testing.expectEqual(@as(i16, 1024), room.scene.hero_start.y);
    try std.testing.expectEqual(@as(i16, 782), room.scene.hero_start.z);
    try std.testing.expectEqual(@as(usize, 9), room.scene.object_count);
    try std.testing.expectEqual(@as(usize, 10), room.scene.zone_count);
    try std.testing.expectEqual(@as(usize, 4), room.scene.track_count);
    try std.testing.expectEqual(@as(usize, 8), room.scene.objects.len);
    try std.testing.expectEqual(@as(usize, 10), room.scene.zones.len);
    try std.testing.expectEqual(@as(usize, 4), room.scene.tracks.len);
    try std.testing.expectEqual(@as(usize, 1), room.scene.objects[0].index);
    try std.testing.expectEqual(@as(i32, 0), room.scene.objects[0].x);
    try std.testing.expectEqual(@as(i32, 0), room.scene.objects[0].z);
    try std.testing.expectEqual(scene_data.ZoneType.change_cube, room.scene.zones[0].kind);
    try std.testing.expectEqual(@as(i32, 9728), room.scene.zones[0].x_min);
    try std.testing.expectEqual(@as(i32, 10239), room.scene.zones[0].x_max);
    try std.testing.expectEqual(@as(i32, 512), room.scene.zones[0].z_min);
    try std.testing.expectEqual(@as(i32, 1535), room.scene.zones[0].z_max);
    try std.testing.expectEqual(@as(usize, 0), room.scene.tracks[0].index);
    try std.testing.expectEqual(@as(i32, 512), room.scene.tracks[0].x);
    try std.testing.expectEqual(@as(i32, 2432), room.scene.tracks[0].z);

    try std.testing.expectEqual(@as(usize, 2), room.background.entry_index);
    try std.testing.expectEqual(@as(usize, 2), room.background.linkage.remapped_cube_index);
    try std.testing.expectEqual(@as(usize, 3), room.background.linkage.gri_entry_index);
    try std.testing.expectEqual(@as(u8, 0), room.background.linkage.gri_my_grm);
    try std.testing.expectEqual(@as(usize, 149), room.background.linkage.grm_entry_index);
    try std.testing.expectEqual(@as(u8, 1), room.background.linkage.gri_my_bll);
    try std.testing.expectEqual(@as(usize, 180), room.background.linkage.bll_entry_index);
    try std.testing.expectEqual(@as(usize, 105), room.background.used_block_ids.len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 7 }, room.background.used_block_ids[0..6]);
    try std.testing.expectEqual(@as(usize, 64), room.background.column_table.width);
    try std.testing.expectEqual(@as(usize, 64), room.background.column_table.depth);
    try std.testing.expectEqual(@as(usize, 4096), room.background.column_table.offset_count);
    try std.testing.expectEqual(@as(usize, 8192), room.background.column_table.table_byte_length);
    try std.testing.expect(room.background.column_table.data_byte_length > 0);
    try std.testing.expectEqual(@as(usize, 2252), room.background.composition.occupied_cell_count);
    try std.testing.expectEqual(@as(?state.CompositionBoundsSnapshot, .{ .min_x = 0, .max_x = 63, .min_z = 12, .max_z = 63 }), room.background.composition.occupied_bounds);
    try std.testing.expectEqual(@as(usize, 2252), sumFloorTypeCounts(room.background.composition.floor_type_counts));
    try std.testing.expect(room.background.composition.floor_type_counts[1] > 0);
    try std.testing.expectEqual(@as(usize, 4096), room.background.composition.height_grid.len);
    try std.testing.expect(room.background.composition.max_total_height >= room.background.composition.max_stack_depth);
    try std.testing.expectEqual(@as(usize, 2252), room.background.composition.tiles.len);
    try std.testing.expectEqual(@as(usize, 0), room.background.fragments.fragment_count);
    try std.testing.expectEqual(@as(usize, 0), room.background.fragments.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 0), room.background.fragments.non_empty_cell_count);
    try std.testing.expectEqual(@as(u8, 0), room.background.fragments.max_height);
    try std.testing.expect(room.background.bricks.previews.len > 0);
    try std.testing.expectEqual(@as(usize, 0), room.fragment_zones.len);

    const first_tile = room.background.composition.tiles[0];
    try std.testing.expectEqual(@as(usize, 59), first_tile.x);
    try std.testing.expectEqual(@as(usize, 12), first_tile.z);
    try std.testing.expectEqual(@as(u8, 14), first_tile.stack_depth);
    try std.testing.expectEqual(@as(u8, 0), first_tile.top_floor_type);
    try std.testing.expectEqual(@as(u8, 1), first_tile.top_shape);
    try std.testing.expectEqual(state.SurfaceShapeClass.solid, first_tile.top_shape_class);
    try std.testing.expect(first_tile.top_brick_index > 0);
    try std.testing.expect(room.background.composition.height_grid[12 * 64 + 59] >= first_tile.stack_depth);

    const water_tile = findCompositionTile(room.background.composition.tiles, 60, 13).?;
    try std.testing.expectEqual(@as(u8, 1), water_tile.stack_depth);
    try std.testing.expectEqual(@as(u8, 1), water_tile.top_floor_type);
    try std.testing.expect(water_tile.top_brick_index > 0);
}

test "viewer room snapshot projects the checked-in fragment-bearing interior pair" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 11, 10);
    defer room.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 11), room.scene.entry_index);
    try std.testing.expectEqual(@as(?usize, 9), room.scene.classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", room.scene.scene_kind);

    try std.testing.expectEqual(@as(usize, 10), room.background.entry_index);
    try std.testing.expectEqual(@as(usize, 10), room.background.linkage.remapped_cube_index);
    try std.testing.expectEqual(@as(usize, 11), room.background.linkage.gri_entry_index);
    try std.testing.expectEqual(@as(u8, 0), room.background.linkage.gri_my_grm);
    try std.testing.expectEqual(@as(usize, 149), room.background.linkage.grm_entry_index);
    try std.testing.expectEqual(@as(usize, 1), room.background.fragments.fragment_count);
    try std.testing.expectEqual(@as(usize, 208), room.background.fragments.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 95), room.background.fragments.non_empty_cell_count);
    try std.testing.expectEqual(@as(u8, 10), room.background.fragments.max_height);
    try std.testing.expect(room.background.bricks.previews.len > 0);

    try std.testing.expectEqual(@as(usize, 1), room.fragment_zones.len);
    const fragment_zone = room.fragment_zones[0];
    try std.testing.expectEqual(@as(usize, 5), fragment_zone.zone_index);
    try std.testing.expectEqual(@as(i16, 0), fragment_zone.zone_num);
    try std.testing.expectEqual(@as(usize, 0), fragment_zone.grm_index);
    try std.testing.expectEqual(@as(usize, 149), fragment_zone.fragment_entry_index);
    try std.testing.expectEqual(false, fragment_zone.initially_on);
    try std.testing.expectEqual(@as(usize, 9), fragment_zone.origin_x);
    try std.testing.expectEqual(@as(usize, 17), fragment_zone.origin_z);
    try std.testing.expectEqual(@as(usize, 16), fragment_zone.width);
    try std.testing.expectEqual(@as(u8, 10), fragment_zone.height);
    try std.testing.expectEqual(@as(usize, 13), fragment_zone.depth);
    try std.testing.expectEqual(@as(usize, 208), fragment_zone.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 95), fragment_zone.non_empty_cell_count);
    try std.testing.expectEqual(@as(usize, 208), fragment_zone.cells.len);

    const first_non_empty_fragment_cell = findFirstNonEmptyFragmentCell(fragment_zone.cells).?;
    try std.testing.expect(first_non_empty_fragment_cell.top_brick_index > 0);
    try std.testing.expectEqual(@as(u16, 127), fragment_zone.cells[0].top_brick_index);
}

test "viewer render snapshot derives a deterministic schematic from the canonical room" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    const render = state.buildRenderSnapshot(room);
    try std.testing.expectEqual(@as(usize, 64), render.grid_width);
    try std.testing.expectEqual(@as(usize, 64), render.grid_depth);
    try std.testing.expectEqual(@as(i32, 0), render.world_bounds.min_x);
    try std.testing.expectEqual(@as(i32, 10239), render.world_bounds.max_x);
    try std.testing.expectEqual(@as(i32, 0), render.world_bounds.min_z);
    try std.testing.expectEqual(@as(i32, 11264), render.world_bounds.max_z);
    try std.testing.expectEqual(@as(i32, 9724), render.hero_start.x);
    try std.testing.expectEqual(@as(usize, 8), render.objects.len);
    try std.testing.expectEqual(@as(usize, 10), render.zones.len);
    try std.testing.expectEqual(@as(usize, 4), render.tracks.len);
    try std.testing.expectEqual(@as(usize, 2252), render.composition.occupied_cell_count);
    try std.testing.expectEqual(@as(usize, 2252), sumFloorTypeCounts(render.composition.floor_type_counts));
    try std.testing.expect(render.composition.floor_type_counts[1] > 0);
    try std.testing.expectEqual(@as(usize, 4096), render.composition.height_grid.len);
    try std.testing.expect(render.composition.max_total_height >= render.composition.max_stack_depth);
    try std.testing.expectEqual(@as(usize, 0), render.fragments.library.fragment_count);
    try std.testing.expectEqual(@as(usize, 0), render.fragments.library.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 0), render.fragments.library.non_empty_cell_count);
    try std.testing.expectEqual(@as(u8, 0), render.fragments.library.max_height);
    try std.testing.expectEqual(@as(usize, 0), render.fragments.zones.len);
    try std.testing.expect(render.brick_previews.len > 0);
    try std.testing.expectEqual(@as(usize, 2), render.metadata.scene_entry_index);
    try std.testing.expectEqual(@as(usize, 2), render.metadata.background_entry_index);
    try std.testing.expectEqual(@as(?usize, 0), render.metadata.classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", render.metadata.scene_kind);
    try std.testing.expectEqual(@as(usize, 8), render.metadata.object_count);
    try std.testing.expectEqual(@as(usize, 10), render.metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 4), render.metadata.track_count);
    try std.testing.expectEqual(@as(usize, 0), render.metadata.fragment_zone_count);
    try std.testing.expectEqual(@as(usize, 0), render.metadata.owned_fragment_count);
}

test "viewer room snapshot rejects exterior scene entries" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(error.ViewerSceneMustBeInterior, state.loadRoomSnapshot(allocator, resolved, 44, 2));
}
