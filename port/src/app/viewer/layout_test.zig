const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const projection = @import("../../runtime/room_projection.zig");
const state = @import("../../runtime/room_state.zig");
const room_fixtures = @import("../../testing/room_fixtures.zig");
const layout = @import("layout.zig");

test "viewer fragment debug layout reserves a deterministic sidebar rail" {
    const debug_layout = layout.computeDebugLayout(960, 540, 64, 64, true);
    try std.testing.expectEqual(sdl.Rect{ .x = 24, .y = 24, .w = 912, .h = 492 }, debug_layout.frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 84, .y = 42, .w = 456, .h = 456 }, debug_layout.schematic_frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 94, .y = 52, .w = 436, .h = 436 }, debug_layout.schematic);
    try std.testing.expectEqual(sdl.Rect{ .x = 598, .y = 42, .w = 320, .h = 456 }, debug_layout.sidebar);
}

test "viewer projection keeps the canonical schematic fit stable" {
    const room = try room_fixtures.guarded1919();

    const render = projection.buildRenderSnapshot(room);
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
    const room = try room_fixtures.guarded1919();

    const seeded_render = projection.buildRenderSnapshotWithHeroPosition(room, .{
        .x = 20224,
        .y = 6400,
        .z = 3328,
    });
    const moved_render = projection.buildRenderSnapshotWithHeroPosition(room, .{
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

test "viewer zoom viewport crops into occupied room cells" {
    const room = try room_fixtures.guarded1919();
    const render = projection.buildRenderSnapshot(room);

    const fit_view = layout.computeGridViewport(render, .fit);
    const room_view = layout.computeGridViewport(render, .room);
    const detail_view = layout.computeGridViewport(render, .detail);

    try std.testing.expectEqual(@as(usize, 0), fit_view.origin_x);
    try std.testing.expectEqual(@as(usize, 0), fit_view.origin_z);
    try std.testing.expectEqual(render.grid_width, fit_view.width);
    try std.testing.expectEqual(render.grid_depth, fit_view.depth);
    try std.testing.expect(room_view.width < fit_view.width);
    try std.testing.expect(room_view.depth < fit_view.depth);
    try std.testing.expect(detail_view.width <= room_view.width);
    try std.testing.expect(detail_view.depth <= room_view.depth);

    const tile = render.composition.tiles[0];
    const fit_layout = layout.computeDebugLayout(1440, 900, fit_view.width, fit_view.depth, false);
    const room_layout = layout.computeDebugLayout(1440, 900, room_view.width, room_view.depth, false);
    const fit_rect = layout.projectGridCellRectInViewport(fit_layout.schematic, fit_view, tile.x, tile.z) orelse return error.MissingFitTile;
    const room_rect = layout.projectGridCellRectInViewport(room_layout.schematic, room_view, tile.x, tile.z) orelse return error.MissingRoomTile;

    try std.testing.expect((room_rect.w * room_rect.h) > (fit_rect.w * fit_rect.h));
}
