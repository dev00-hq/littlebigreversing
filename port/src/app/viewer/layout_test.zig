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

    const northwest = layout.projectWorldPoint(render, schematic_layout.schematic, render.world_bounds.min_x, render.world_bounds.min_z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 252, .y = 42 }, northwest);

    const southeast = layout.projectWorldPoint(render, schematic_layout.schematic, render.world_bounds.max_x, render.world_bounds.max_z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 707, .y = 497 }, southeast);

    const hero = layout.projectWorldPoint(render, schematic_layout.schematic, render.hero_position.x, render.hero_position.z);
    try std.testing.expectEqual(layout.ScreenPoint{ .x = 280, .y = 94 }, hero);

    const first_zone = layout.projectZoneBounds(render, schematic_layout.schematic, render.zones[0]);
    try std.testing.expectEqual(sdl.Rect{ .x = 259, .y = 49, .w = 58, .h = 86 }, first_zone);
}

test "viewer projection moves the hero marker down the schematic after southward seeded locomotion" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    const seeded_render = state.buildRenderSnapshotWithHeroPosition(room, .{
        .x = 20224,
        .y = 6400,
        .z = 3328,
    });
    const moved_render = state.buildRenderSnapshotWithHeroPosition(room, .{
        .x = 20224,
        .y = 6400,
        .z = 4864,
    });
    const schematic_layout = layout.computeSchematicLayout(960, 540, seeded_render.grid_width, seeded_render.grid_depth);

    const seeded_hero = layout.projectWorldPoint(
        seeded_render,
        schematic_layout.schematic,
        seeded_render.hero_position.x,
        seeded_render.hero_position.z,
    );
    const moved_hero = layout.projectWorldPoint(
        moved_render,
        schematic_layout.schematic,
        moved_render.hero_position.x,
        moved_render.hero_position.z,
    );

    try std.testing.expectEqual(seeded_hero.x, moved_hero.x);
    try std.testing.expect(moved_hero.y > seeded_hero.y);
}
