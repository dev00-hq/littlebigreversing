const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const paths_mod = @import("../../foundation/paths.zig");
const state = @import("state.zig");
const layout = @import("layout.zig");

test "viewer fragment debug layout reserves a deterministic comparison panel" {
    const debug_layout = layout.computeDebugLayout(960, 540, 64, 64, true);
    try std.testing.expectEqual(sdl.Rect{ .x = 24, .y = 24, .w = 912, .h = 492 }, debug_layout.frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 127, .y = 42, .w = 456, .h = 456 }, debug_layout.schematic_frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 137, .y = 52, .w = 436, .h = 436 }, debug_layout.schematic);
    try std.testing.expectEqual(sdl.Rect{ .x = 682, .y = 42, .w = 236, .h = 456 }, debug_layout.comparison_frame.?);
    try std.testing.expectEqual(sdl.Rect{ .x = 692, .y = 52, .w = 216, .h = 436 }, debug_layout.comparison.?);
}

test "viewer projection keeps the canonical schematic fit stable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    const render = state.buildRenderSnapshot(room);
    const schematic_layout = layout.computeSchematicLayout(960, 540, render.grid_width, render.grid_depth);
    try std.testing.expectEqual(sdl.Rect{ .x = 24, .y = 24, .w = 912, .h = 492 }, schematic_layout.frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 252, .y = 42, .w = 456, .h = 456 }, schematic_layout.schematic);

    const southwest = layout.projectWorldPoint(render, schematic_layout.schematic, render.world_bounds.min_x, render.world_bounds.min_z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 252, .y = 497 }, southwest);

    const northeast = layout.projectWorldPoint(render, schematic_layout.schematic, render.world_bounds.max_x, render.world_bounds.max_z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 707, .y = 42 }, northeast);

    const hero = layout.projectWorldPoint(render, schematic_layout.schematic, render.hero_start.x, render.hero_start.z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 684, .y = 465 }, hero);

    const first_zone = layout.projectZoneBounds(render, schematic_layout.schematic, render.zones[0]);
    try std.testing.expectEqual(sdl.Rect{ .x = 684, .y = 435, .w = 24, .h = 42 }, first_zone);

    const first_tile_rect = layout.projectGridCellRect(schematic_layout.schematic.inset(10), render.grid_width, render.grid_depth, 59, 12);
    try std.testing.expectEqual(@as(i32, 663), first_tile_rect.x);
    try std.testing.expectEqual(@as(i32, 134), first_tile_rect.y);
    try std.testing.expect(first_tile_rect.w >= 6);
    try std.testing.expect(first_tile_rect.h >= 6);
}
