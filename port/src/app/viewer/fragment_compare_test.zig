const std = @import("std");
const paths_mod = @import("../../foundation/paths.zig");
const state = @import("state.zig");
const fragment_compare = @import("fragment_compare.zig");

fn sumFragmentComparisonCounts(panel: fragment_compare.FragmentComparisonPanel) usize {
    return panel.changed_count + panel.same_count + panel.no_base_count;
}

test "viewer fragment brick delta detects changed base bricks" {
    const tiles = [_]state.CompositionTileSnapshot{
        .{ .x = 4, .z = 7, .total_height = 3, .stack_depth = 2, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 149 },
    };
    const cell_same = state.FragmentZoneCellSnapshot{ .x = 4, .z = 7, .has_non_empty = true, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 149 };
    const cell_changed = state.FragmentZoneCellSnapshot{ .x = 4, .z = 7, .has_non_empty = true, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 667 };
    const cell_missing = state.FragmentZoneCellSnapshot{ .x = 1, .z = 1, .has_non_empty = true, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 667 };
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

test "viewer fragment comparison panel prioritizes changed cells and counts non-empty deltas" {
    const tiles = [_]state.CompositionTileSnapshot{
        .{ .x = 2, .z = 3, .total_height = 2, .stack_depth = 1, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 200 },
        .{ .x = 4, .z = 7, .total_height = 3, .stack_depth = 2, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 149 },
    };
    var cells = [_]state.FragmentZoneCellSnapshot{
        .{ .x = 4, .z = 7, .has_non_empty = true, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 667 },
        .{ .x = 2, .z = 3, .has_non_empty = true, .top_floor_type = 1, .top_shape = 1, .top_shape_class = .solid, .top_brick_index = 200 },
        .{ .x = 1, .z = 1, .has_non_empty = true, .top_floor_type = 3, .top_shape = 2, .top_shape_class = .single_stair, .top_brick_index = 127 },
        .{ .x = 6, .z = 6, .has_non_empty = false, .top_floor_type = 0, .top_shape = 0, .top_shape_class = .open, .top_brick_index = 0 },
    };
    const zones = [_]state.FragmentZoneSnapshot{
        .{
            .zone_index = 5,
            .zone_num = 0,
            .grm_index = 0,
            .fragment_entry_index = 149,
            .initially_on = false,
            .origin_x = 1,
            .origin_z = 1,
            .width = 6,
            .height = 3,
            .depth = 7,
            .footprint_cell_count = 4,
            .non_empty_cell_count = 3,
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

    const panel = fragment_compare.buildFragmentComparisonPanel(snapshot);
    try std.testing.expectEqual(@as(usize, 1), panel.changed_count);
    try std.testing.expectEqual(@as(usize, 1), panel.same_count);
    try std.testing.expectEqual(@as(usize, 1), panel.no_base_count);
    try std.testing.expectEqual(@as(usize, 3), sumFragmentComparisonCounts(panel));
    try std.testing.expectEqual(@as(usize, 3), panel.entry_count);
    try std.testing.expect(panel.focus != null);
    try std.testing.expectEqual(fragment_compare.FragmentBrickDelta.changed, panel.focus.?.delta);
    try std.testing.expectEqual(@as(usize, 4), panel.focus.?.x);
    try std.testing.expectEqual(@as(usize, 7), panel.focus.?.z);
    try std.testing.expectEqual(fragment_compare.FragmentBrickDelta.changed, panel.entries[0].delta);
    try std.testing.expectEqual(fragment_compare.FragmentBrickDelta.same, panel.entries[1].delta);
    try std.testing.expectEqual(fragment_compare.FragmentBrickDelta.no_base, panel.entries[2].delta);
}

test "viewer fragment comparison panel keeps the checked-in fragment pair inspectable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 11, 10);
    defer room.deinit(allocator);

    const render = state.buildRenderSnapshot(room);
    const panel = fragment_compare.buildFragmentComparisonPanel(render);
    try std.testing.expect(panel.focus != null);
    try std.testing.expectEqual(room.fragment_zones[0].non_empty_cell_count, sumFragmentComparisonCounts(panel));
    try std.testing.expect(panel.entry_count > 0);
    try std.testing.expect(panel.entry_count <= fragment_compare.max_fragment_comparison_entries);
    try std.testing.expect(panel.focus.?.fragment_entry_index == room.fragment_zones[0].fragment_entry_index);
}
