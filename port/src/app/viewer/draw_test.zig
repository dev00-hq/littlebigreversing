const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const background_data = @import("../../game_data/background.zig");
const draw = @import("draw.zig");
const state = @import("state.zig");

test "viewer tile relief thickens with taller composition cells" {
    const tile_rect = sdl.Rect{ .x = 40, .y = 80, .w = 12, .h = 12 };
    const short_relief = draw.computeTileRelief(tile_rect, 3, 25);
    const tall_relief = draw.computeTileRelief(tile_rect, 18, 25);

    try std.testing.expect(short_relief.inset_depth < tall_relief.inset_depth);
    try std.testing.expectEqual(tile_rect.x, tall_relief.top_surface.x);
    try std.testing.expectEqual(tile_rect.y, tall_relief.top_surface.y);
    try std.testing.expect(tall_relief.right_wall.w > 0);
    try std.testing.expect(tall_relief.bottom_wall.h > 0);
}

test "viewer brick probe style stays deterministic for representative brick ids" {
    try std.testing.expectEqual(draw.BrickProbeStyle{ .pattern = .diagonal_ascending, .spacing = 2, .accent = 23 }, draw.brickProbeStyle(123));
    try std.testing.expectEqual(draw.BrickProbeStyle{ .pattern = .checker, .spacing = 3, .accent = 24 }, draw.brickProbeStyle(149));
    try std.testing.expectEqual(draw.BrickProbeStyle{ .pattern = .diagonal_descending, .spacing = 3, .accent = 40 }, draw.brickProbeStyle(667));
}

test "viewer composition preview selector stays deterministic on eight-cell boundaries" {
    try std.testing.expect(draw.shouldDrawCompositionBrickPreview(.{
        .x = 8,
        .z = 16,
        .total_height = 1,
        .stack_depth = 1,
        .top_floor_type = 0,
        .top_shape = 1,
        .top_shape_class = state.SurfaceShapeClass.solid,
        .top_brick_index = 667,
    }));
    try std.testing.expect(!draw.shouldDrawCompositionBrickPreview(.{
        .x = 9,
        .z = 16,
        .total_height = 1,
        .stack_depth = 1,
        .top_floor_type = 0,
        .top_shape = 1,
        .top_shape_class = .solid,
        .top_brick_index = 667,
    }));
}

test "viewer brick preview lookup resolves decoded swatches by brick index" {
    const previews = [_]background_data.BrickPreview{
        .{
            .brick_index = 127,
            .entry_index = 323,
            .width = 24,
            .height = 38,
            .offset_x = 0,
            .offset_y = 0,
            .opaque_pixel_count = 400,
            .unique_color_count = 12,
            .swatch = [_]background_data.BrickSwatchPixel{.{ .r = 0, .g = 0, .b = 0, .a = 0 }} ** background_data.brick_preview_swatch_pixel_count,
        },
    };

    try std.testing.expectEqual(@as(?background_data.BrickPreview, previews[0]), draw.findBrickPreview(&previews, 127));
    try std.testing.expectEqual(@as(?background_data.BrickPreview, null), draw.findBrickPreview(&previews, 667));
}
