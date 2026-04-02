const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const paths_mod = @import("../../foundation/paths.zig");
const state = @import("../../runtime/room_state.zig");
const layout = @import("layout.zig");

test "viewer fragment debug layout reserves a deterministic comparison panel" {
    const debug_layout = layout.computeDebugLayout(960, 540, 64, 64, true);
    try std.testing.expectEqual(sdl.Rect{ .x = 24, .y = 24, .w = 912, .h = 492 }, debug_layout.frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 42, .y = 42, .w = 876, .h = 72 }, debug_layout.header);
    try std.testing.expectEqual(sdl.Rect{ .x = 217, .y = 126, .w = 276, .h = 276 }, debug_layout.schematic_frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 227, .y = 136, .w = 256, .h = 256 }, debug_layout.schematic);
    try std.testing.expectEqual(sdl.Rect{ .x = 682, .y = 126, .w = 236, .h = 276 }, debug_layout.comparison_frame.?);
    try std.testing.expectEqual(sdl.Rect{ .x = 692, .y = 136, .w = 216, .h = 256 }, debug_layout.comparison.?);
    try std.testing.expectEqual(sdl.Rect{ .x = 42, .y = 414, .w = 876, .h = 84 }, debug_layout.footer);
}

test "viewer projection keeps the canonical schematic fit stable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    const render = state.buildRenderSnapshot(room);
    const schematic_layout = layout.computeSchematicLayout(960, 540, render.grid_width, render.grid_depth);
    try std.testing.expectEqual(sdl.Rect{ .x = 24, .y = 24, .w = 912, .h = 492 }, schematic_layout.frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 252, .y = 42, .w = 456, .h = 456 }, schematic_layout.schematic);

    const southwest = layout.projectWorldPoint(render, schematic_layout.schematic, render.world_bounds.min_x, render.world_bounds.min_z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 252, .y = 497 }, southwest);

    const northeast = layout.projectWorldPoint(render, schematic_layout.schematic, render.world_bounds.max_x, render.world_bounds.max_z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 707, .y = 42 }, northeast);

    const hero = layout.projectWorldPoint(render, schematic_layout.schematic, render.hero_position.x, render.hero_position.z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 429, .y = 241 }, hero);

    const first_zone = layout.projectZoneBounds(render, schematic_layout.schematic, render.zones[0]);
    try std.testing.expectEqual(sdl.Rect{ .x = 298, .y = 42, .w = 365, .h = 421 }, first_zone);
}
