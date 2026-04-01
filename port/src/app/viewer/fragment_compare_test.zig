const std = @import("std");
const paths_mod = @import("../../foundation/paths.zig");
const state = @import("state.zig");
const fragment_compare = @import("fragment_compare.zig");

fn sumFragmentComparisonCounts(catalog: fragment_compare.FragmentComparisonCatalog) usize {
    return catalog.changed_count + catalog.exact_count + catalog.no_base_count;
}

fn panelContainsFocus(panel: fragment_compare.FragmentComparisonPanel, focus: fragment_compare.FragmentComparisonEntry) bool {
    for (panel.entries[0..panel.entry_count]) |entry| {
        if (entry.x == focus.x and entry.z == focus.z and entry.fragment_entry_index == focus.fragment_entry_index) {
            return true;
        }
    }
    return false;
}

test "viewer fragment brick delta detects changed base bricks" {
    const tiles = [_]state.CompositionTileSnapshot{
        .{ .x = 4, .z = 7, .total_height = 3, .stack_depth = 2, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 149 },
    };
    const cell_same = state.FragmentZoneCellSnapshot{ .x = 4, .z = 7, .has_non_empty = true, .stack_depth = 2, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 149 };
    const cell_changed = state.FragmentZoneCellSnapshot{ .x = 4, .z = 7, .has_non_empty = true, .stack_depth = 2, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 667 };
    const cell_missing = state.FragmentZoneCellSnapshot{ .x = 1, .z = 1, .has_non_empty = true, .stack_depth = 1, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 667 };
    const snapshot = state.RenderSnapshot{
        .grid_width = 8,
        .grid_depth = 8,
        .world_bounds = .{ .min_x = 0, .max_x = 1, .min_z = 0, .max_z = 1 },
        .hero_start = .{ .x = 0, .y = 0, .z = 0 },
        .objects = &.{},
        .zones = &.{},
        .tracks = &.{},
        .composition = .{ .occupied_cell_count = 1, .occupied_bounds = null, .floor_type_counts = [_]usize{0} ** 16, .max_total_height = 3, .max_stack_depth = 2, .height_grid = &.{}, .tiles = &tiles },
        .fragments = .{ .library = .{ .fragment_count = 0, .footprint_cell_count = 0, .non_empty_cell_count = 0, .max_height = 0 }, .zones = &.{} },
        .brick_previews = &.{},
    };

    try std.testing.expectEqual(fragment_compare.FragmentBrickDelta.same, fragment_compare.fragmentBrickDelta(snapshot, cell_same));
    try std.testing.expectEqual(fragment_compare.FragmentBrickDelta.changed, fragment_compare.fragmentBrickDelta(snapshot, cell_changed));
    try std.testing.expectEqual(fragment_compare.FragmentBrickDelta.no_base, fragment_compare.fragmentBrickDelta(snapshot, cell_missing));
}

test "viewer fragment comparison detail captures non-brick deltas for the selected cell" {
    const tile = state.CompositionTileSnapshot{
        .x = 4,
        .z = 7,
        .total_height = 3,
        .stack_depth = 4,
        .top_floor_type = 1,
        .top_shape = 1,
        .top_shape_class = .solid,
        .top_brick_index = 149,
    };
    const cell = state.FragmentZoneCellSnapshot{
        .x = 4,
        .z = 7,
        .has_non_empty = true,
        .stack_depth = 2,
        .top_floor_type = 3,
        .top_shape = 2,
        .top_shape_class = .single_stair,
        .top_brick_index = 149,
    };

    const detail = fragment_compare.buildFragmentComparisonDetail(tile, cell);
    try std.testing.expect(detail.base_present);
    try std.testing.expect(detail.brick_matches);
    try std.testing.expect(!detail.floor_type_matches);
    try std.testing.expect(!detail.shape_matches);
    try std.testing.expectEqual(@as(u8, 4), detail.base_stack_depth);
    try std.testing.expectEqual(@as(u8, 2), detail.fragment_stack_depth);
    try std.testing.expectEqual(@as(i16, -2), detail.stackDepthDelta());
    try std.testing.expectEqual(@as(u8, 3), detail.changedAspectCount());
    try std.testing.expect(!detail.isExactMatch());
    try std.testing.expectEqual(fragment_compare.FragmentComparisonDelta.changed, fragment_compare.fragmentComparisonDelta(detail));
}

test "viewer fragment comparison delta summary names the changed aspects" {
    var summary_buffer: [24]u8 = undefined;

    const changed = try fragment_compare.formatDeltaSummary(&summary_buffer, .{
        .base_present = true,
        .brick_matches = false,
        .floor_type_matches = false,
        .shape_matches = true,
        .base_stack_depth = 2,
        .fragment_stack_depth = 5,
    });
    try std.testing.expectEqualStrings("BRK FLR DEP", changed);

    const exact = try fragment_compare.formatDeltaSummary(&summary_buffer, .{
        .base_present = true,
        .brick_matches = true,
        .floor_type_matches = true,
        .shape_matches = true,
        .base_stack_depth = 2,
        .fragment_stack_depth = 2,
    });
    try std.testing.expectEqualStrings("EXACT", exact);

    const no_base = try fragment_compare.formatDeltaSummary(&summary_buffer, .{
        .base_present = false,
        .brick_matches = false,
        .floor_type_matches = false,
        .shape_matches = false,
        .base_stack_depth = 0,
        .fragment_stack_depth = 1,
    });
    try std.testing.expectEqualStrings("NO BASE", no_base);
}

test "viewer fragment comparison stack summary captures base and fragment depth" {
    var summary_buffer: [16]u8 = undefined;

    const changed = try fragment_compare.formatStackSummary(&summary_buffer, .{
        .base_present = true,
        .brick_matches = true,
        .floor_type_matches = true,
        .shape_matches = true,
        .base_stack_depth = 4,
        .fragment_stack_depth = 2,
    });
    try std.testing.expectEqualStrings("4/2", changed);

    const no_base = try fragment_compare.formatStackSummary(&summary_buffer, .{
        .base_present = false,
        .brick_matches = false,
        .floor_type_matches = false,
        .shape_matches = false,
        .base_stack_depth = 0,
        .fragment_stack_depth = 3,
    });
    try std.testing.expectEqualStrings("-/3", no_base);
}

test "viewer fragment comparison catalog prioritizes any delta ahead of exact matches" {
    const allocator = std.testing.allocator;
    const tiles = [_]state.CompositionTileSnapshot{
        .{ .x = 2, .z = 3, .total_height = 2, .stack_depth = 1, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 200 },
        .{ .x = 4, .z = 7, .total_height = 3, .stack_depth = 2, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 149 },
        .{ .x = 6, .z = 5, .total_height = 1, .stack_depth = 1, .top_floor_type = 8, .top_shape = 4, .top_shape_class = .single_stair, .top_brick_index = 330 },
    };
    var cells = [_]state.FragmentZoneCellSnapshot{
        .{ .x = 4, .z = 7, .has_non_empty = true, .stack_depth = 3, .top_floor_type = 3, .top_shape = 2, .top_shape_class = .single_stair, .top_brick_index = 667 },
        .{ .x = 2, .z = 3, .has_non_empty = true, .stack_depth = 1, .top_floor_type = 3, .top_shape = 2, .top_shape_class = .single_stair, .top_brick_index = 200 },
        .{ .x = 6, .z = 5, .has_non_empty = true, .stack_depth = 1, .top_floor_type = 8, .top_shape = 4, .top_shape_class = .single_stair, .top_brick_index = 330 },
        .{ .x = 1, .z = 1, .has_non_empty = true, .stack_depth = 1, .top_floor_type = 3, .top_shape = 2, .top_shape_class = .single_stair, .top_brick_index = 127 },
        .{ .x = 7, .z = 6, .has_non_empty = false, .stack_depth = 0, .top_floor_type = 0, .top_shape = 0, .top_shape_class = .open, .top_brick_index = 0 },
    };
    const zones = [_]state.FragmentZoneSnapshot{
        .{
            .zone_index = 5,
            .zone_num = 0,
            .grm_index = 0,
            .fragment_entry_index = 149,
            .initially_on = false,
            .y_min = 512,
            .y_max = 1024,
            .origin_x = 1,
            .origin_z = 1,
            .width = 7,
            .height = 3,
            .depth = 7,
            .footprint_cell_count = 5,
            .non_empty_cell_count = 4,
            .cells = cells[0..],
        },
    };
    const snapshot = state.RenderSnapshot{
        .grid_width = 8,
        .grid_depth = 8,
        .world_bounds = .{ .min_x = 0, .max_x = 1, .min_z = 0, .max_z = 1 },
        .hero_start = .{ .x = 0, .y = 0, .z = 0 },
        .objects = &.{},
        .zones = &.{},
        .tracks = &.{},
        .composition = .{ .occupied_cell_count = tiles.len, .occupied_bounds = null, .floor_type_counts = [_]usize{0} ** 16, .max_total_height = 3, .max_stack_depth = 2, .height_grid = &.{}, .tiles = &tiles },
        .fragments = .{ .library = .{ .fragment_count = 1, .footprint_cell_count = 4, .non_empty_cell_count = 3, .max_height = 3 }, .zones = &zones },
        .brick_previews = &.{},
    };

    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    const selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    const panel = fragment_compare.buildFragmentComparisonPanel(catalog, selection);
    try std.testing.expectEqual(@as(usize, 2), catalog.changed_count);
    try std.testing.expectEqual(@as(usize, 1), catalog.exact_count);
    try std.testing.expectEqual(@as(usize, 1), catalog.no_base_count);
    try std.testing.expectEqual(@as(usize, 4), sumFragmentComparisonCounts(catalog));
    try std.testing.expectEqual(@as(usize, 4), catalog.ranked_entries.len);
    try std.testing.expect(selection.focus != null);
    try std.testing.expectEqual(fragment_compare.FragmentComparisonDelta.changed, selection.focus.?.delta);
    try std.testing.expectEqual(@as(usize, 4), selection.focus.?.x);
    try std.testing.expectEqual(@as(usize, 7), selection.focus.?.z);
    try std.testing.expectEqual(@as(u8, 4), selection.focus.?.detail.changedAspectCount());
    try std.testing.expectEqual(fragment_compare.FragmentComparisonDelta.changed, catalog.ranked_entries[0].delta);
    try std.testing.expectEqual(@as(usize, 2), catalog.ranked_entries[1].x);
    try std.testing.expectEqual(@as(usize, 3), catalog.ranked_entries[1].z);
    try std.testing.expectEqual(fragment_compare.FragmentComparisonDelta.changed, catalog.ranked_entries[1].delta);
    try std.testing.expectEqual(fragment_compare.FragmentComparisonDelta.exact, catalog.ranked_entries[2].delta);
    try std.testing.expectEqual(fragment_compare.FragmentComparisonDelta.no_base, catalog.ranked_entries[3].delta);
    try std.testing.expectEqual(@as(usize, 4), panel.entry_count);
}

test "viewer fragment comparison selection can step ranked entries and fragment cells independently" {
    const allocator = std.testing.allocator;
    const tiles = [_]state.CompositionTileSnapshot{
        .{ .x = 2, .z = 3, .total_height = 2, .stack_depth = 1, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 200 },
        .{ .x = 4, .z = 7, .total_height = 3, .stack_depth = 2, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 149 },
        .{ .x = 6, .z = 5, .total_height = 1, .stack_depth = 1, .top_floor_type = 8, .top_shape = 4, .top_shape_class = .single_stair, .top_brick_index = 330 },
    };
    var cells = [_]state.FragmentZoneCellSnapshot{
        .{ .x = 4, .z = 7, .has_non_empty = true, .stack_depth = 3, .top_floor_type = 3, .top_shape = 2, .top_shape_class = .single_stair, .top_brick_index = 667 },
        .{ .x = 2, .z = 3, .has_non_empty = true, .stack_depth = 1, .top_floor_type = 3, .top_shape = 2, .top_shape_class = .single_stair, .top_brick_index = 200 },
        .{ .x = 6, .z = 5, .has_non_empty = true, .stack_depth = 1, .top_floor_type = 8, .top_shape = 4, .top_shape_class = .single_stair, .top_brick_index = 330 },
        .{ .x = 1, .z = 1, .has_non_empty = true, .stack_depth = 1, .top_floor_type = 3, .top_shape = 2, .top_shape_class = .single_stair, .top_brick_index = 127 },
    };
    const zones = [_]state.FragmentZoneSnapshot{
        .{
            .zone_index = 5,
            .zone_num = 0,
            .grm_index = 0,
            .fragment_entry_index = 149,
            .initially_on = false,
            .y_min = 512,
            .y_max = 1024,
            .origin_x = 1,
            .origin_z = 1,
            .width = 7,
            .height = 3,
            .depth = 7,
            .footprint_cell_count = 4,
            .non_empty_cell_count = 4,
            .cells = cells[0..],
        },
    };
    const snapshot = state.RenderSnapshot{
        .grid_width = 8,
        .grid_depth = 8,
        .world_bounds = .{ .min_x = 0, .max_x = 1, .min_z = 0, .max_z = 1 },
        .hero_start = .{ .x = 0, .y = 0, .z = 0 },
        .objects = &.{},
        .zones = &.{},
        .tracks = &.{},
        .composition = .{ .occupied_cell_count = tiles.len, .occupied_bounds = null, .floor_type_counts = [_]usize{0} ** 16, .max_total_height = 3, .max_stack_depth = 2, .height_grid = &.{}, .tiles = &tiles },
        .fragments = .{ .library = .{ .fragment_count = 1, .footprint_cell_count = 4, .non_empty_cell_count = 4, .max_height = 3 }, .zones = &zones },
        .brick_previews = &.{},
    };

    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    const initial = fragment_compare.initialFragmentComparisonSelection(catalog);
    const ranked_next = fragment_compare.stepRankedSelection(catalog, initial, 1);
    const cell_prev = fragment_compare.stepCellSelection(catalog, initial, -1);
    const cell_panel = fragment_compare.buildFragmentComparisonPanel(catalog, cell_prev);

    try std.testing.expect(initial.focus != null);
    try std.testing.expectEqual(@as(usize, 2), ranked_next.focus.?.x);
    try std.testing.expectEqual(@as(usize, 3), ranked_next.focus.?.z);
    try std.testing.expectEqual(@as(usize, 6), cell_prev.focus.?.x);
    try std.testing.expectEqual(@as(usize, 5), cell_prev.focus.?.z);
    try std.testing.expect(cell_panel.focus != null);
    try std.testing.expectEqual(cell_prev.focus.?.x, cell_panel.focus.?.x);
    try std.testing.expectEqual(cell_prev.focus.?.z, cell_panel.focus.?.z);
    try std.testing.expect(cell_panel.entry_count > 0);
    try std.testing.expect(panelContainsFocus(cell_panel, cell_prev.focus.?));
    try std.testing.expectEqual(cell_prev.focus.?.x, cell_panel.entries[0].x);
    try std.testing.expectEqual(cell_prev.focus.?.z, cell_panel.entries[0].z);
}

test "viewer fragment comparison panel pins the selected cell ahead of the ranked head" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 11, 10);
    defer room.deinit(allocator);

    const render = state.buildRenderSnapshot(room);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, render);
    defer catalog.deinit(allocator);

    var selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    try std.testing.expect(selection.focus != null);

    var steps: usize = 0;
    while (steps < catalog.cell_entries.len) : (steps += 1) {
        selection = fragment_compare.stepCellSelection(catalog, selection, 1);
        if (selection.ranked_index) |ranked_index| {
            if (ranked_index >= fragment_compare.max_fragment_comparison_entries) break;
        }
    }

    const focus = selection.focus.?;
    const ranked_index = selection.ranked_index.?;
    try std.testing.expect(ranked_index >= fragment_compare.max_fragment_comparison_entries);

    const panel = fragment_compare.buildFragmentComparisonPanel(catalog, selection);
    try std.testing.expectEqual(focus.x, panel.entries[0].x);
    try std.testing.expectEqual(focus.z, panel.entries[0].z);
    try std.testing.expectEqual(focus.fragment_entry_index, panel.entries[0].fragment_entry_index);

    var focus_count: usize = 0;
    for (panel.entries[0..panel.entry_count]) |entry| {
        if (entry.x == focus.x and entry.z == focus.z and entry.fragment_entry_index == focus.fragment_entry_index) {
            focus_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), focus_count);
}

test "viewer fragment comparison panel keeps the checked-in fragment pair inspectable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 11, 10);
    defer room.deinit(allocator);

    const render = state.buildRenderSnapshot(room);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, render);
    defer catalog.deinit(allocator);
    const selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    const cell_next = fragment_compare.stepCellSelection(catalog, selection, 1);
    const panel = fragment_compare.buildFragmentComparisonPanel(catalog, cell_next);
    try std.testing.expect(selection.focus != null);
    try std.testing.expectEqual(room.fragment_zones[0].non_empty_cell_count, sumFragmentComparisonCounts(catalog));
    try std.testing.expect(panel.entry_count > 0);
    try std.testing.expect(panel.entry_count <= fragment_compare.max_fragment_comparison_entries);
    try std.testing.expect(panel.focus.?.fragment_entry_index == room.fragment_zones[0].fragment_entry_index);
    try std.testing.expect(panel.focus.?.detail.base_present);
    try std.testing.expectEqual(cell_next.focus.?.x, panel.focus.?.x);
    try std.testing.expectEqual(cell_next.focus.?.z, panel.focus.?.z);
    try std.testing.expectEqual(panel.focus.?.x, panel.entries[0].x);
    try std.testing.expectEqual(panel.focus.?.z, panel.entries[0].z);
    try std.testing.expect(panel.focus.?.detail.changedAspectCount() > 0);
}
