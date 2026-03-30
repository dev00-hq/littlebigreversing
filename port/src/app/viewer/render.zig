const sdl = @import("../../platform/sdl.zig");
const state = @import("state.zig");
const layout = @import("layout.zig");
const draw = @import("draw.zig");
const fragment_compare = @import("fragment_compare.zig");

pub fn renderDebugView(
    canvas: *sdl.Canvas,
    snapshot: state.RenderSnapshot,
    catalog: fragment_compare.FragmentComparisonCatalog,
    selection: fragment_compare.FragmentComparisonSelection,
) !void {
    const fragment_panel = fragment_compare.buildFragmentComparisonPanel(catalog, selection);
    const debug_layout = layout.computeDebugLayout(
        canvas.width,
        canvas.height,
        snapshot.grid_width,
        snapshot.grid_depth,
        fragment_panel.focus != null,
    );

    try canvas.clear(.{ .r = 13, .g = 20, .b = 26, .a = 255 });
    try canvas.fillRect(debug_layout.frame, .{ .r = 22, .g = 32, .b = 41, .a = 255 });
    try canvas.drawRect(debug_layout.frame, .{ .r = 96, .g = 123, .b = 142, .a = 255 });
    try canvas.fillRect(debug_layout.schematic_frame, .{ .r = 10, .g = 14, .b = 19, .a = 255 });
    try canvas.drawRect(debug_layout.schematic_frame, .{ .r = 56, .g = 80, .b = 92, .a = 255 });
    try drawComposition(canvas, debug_layout.schematic, snapshot);
    try drawFragmentZones(canvas, debug_layout.schematic, snapshot);
    try drawGrid(canvas, debug_layout.schematic, snapshot.grid_width, snapshot.grid_depth);
    if (fragment_panel.focus) |focus| {
        try fragment_compare.drawFragmentFocusHighlight(canvas, debug_layout.schematic, snapshot, focus);
    }

    if (debug_layout.comparison_frame) |comparison_frame| {
        try canvas.fillRect(comparison_frame, .{ .r = 12, .g = 17, .b = 23, .a = 255 });
        try canvas.drawRect(comparison_frame, .{ .r = 66, .g = 90, .b = 103, .a = 255 });
    }
    if (debug_layout.comparison) |comparison| {
        try fragment_compare.drawFragmentComparisonPanel(canvas, comparison, snapshot, fragment_panel);
    }

    for (snapshot.zones) |zone| {
        const rect = layout.projectZoneBounds(snapshot, debug_layout.schematic, zone);
        const zone_color = draw.zoneColor(zone.kind);
        try canvas.fillRect(rect, draw.withAlpha(zone_color, 40));
        try canvas.drawRect(rect, zone_color);
    }

    for (snapshot.tracks[0..snapshot.tracks.len -| 1], 0..) |track, index| {
        const next = snapshot.tracks[index + 1];
        const start = layout.projectWorldPoint(snapshot, debug_layout.schematic, track.x, track.z);
        const finish = layout.projectWorldPoint(snapshot, debug_layout.schematic, next.x, next.z);
        try canvas.drawLine(start.x, start.y, finish.x, finish.y, .{ .r = 59, .g = 201, .b = 255, .a = 192 });
    }

    for (snapshot.tracks) |track| {
        const point = layout.projectWorldPoint(snapshot, debug_layout.schematic, track.x, track.z);
        try draw.drawMarker(canvas, point, 4, .{ .r = 76, .g = 226, .b = 255, .a = 255 });
    }

    for (snapshot.objects) |object| {
        const point = layout.projectWorldPoint(snapshot, debug_layout.schematic, object.x, object.z);
        try draw.drawMarker(canvas, point, 6, .{ .r = 255, .g = 194, .b = 92, .a = 255 });
    }

    const hero = layout.projectWorldPoint(snapshot, debug_layout.schematic, snapshot.hero_start.x, snapshot.hero_start.z);
    try draw.drawCrosshair(canvas, hero, 8, .{ .r = 255, .g = 86, .b = 86, .a = 255 });
    try draw.drawMarker(canvas, hero, 6, .{ .r = 255, .g = 240, .b = 148, .a = 255 });
    canvas.present();
}

fn drawGrid(canvas: *sdl.Canvas, rect: sdl.Rect, width: usize, depth: usize) !void {
    const left = rect.x;
    const right = rect.right();
    const top = rect.y;
    const bottom = rect.bottom();

    for (0..(width + 1)) |column| {
        const x = layout.interpolateAxis(left, right, column, width);
        const color = if (column % 8 == 0)
            sdl.Color{ .r = 42, .g = 61, .b = 74, .a = 255 }
        else
            sdl.Color{ .r = 25, .g = 36, .b = 45, .a = 255 };
        try canvas.drawLine(x, top, x, bottom, color);
    }

    for (0..(depth + 1)) |row| {
        const y = layout.interpolateAxis(top, bottom, row, depth);
        const color = if (row % 8 == 0)
            sdl.Color{ .r = 42, .g = 61, .b = 74, .a = 255 }
        else
            sdl.Color{ .r = 25, .g = 36, .b = 45, .a = 255 };
        try canvas.drawLine(left, y, right, y, color);
    }
}

fn drawComposition(canvas: *sdl.Canvas, rect: sdl.Rect, snapshot: state.RenderSnapshot) !void {
    for (snapshot.composition.tiles) |tile| {
        const tile_rect = layout.projectGridCellRect(rect, snapshot.grid_width, snapshot.grid_depth, tile.x, tile.z);
        try drawCompositionTile(canvas, snapshot, tile_rect, tile);
    }
}

fn drawFragmentZones(canvas: *sdl.Canvas, rect: sdl.Rect, snapshot: state.RenderSnapshot) !void {
    for (snapshot.fragments.zones) |zone| {
        const zone_bounds = layout.projectGridAreaRect(
            rect,
            snapshot.grid_width,
            snapshot.grid_depth,
            zone.origin_x,
            zone.origin_z,
            zone.width,
            zone.depth,
        );
        const border_color = draw.fragmentZoneBorderColor(zone.initially_on);
        for (zone.cells) |cell| {
            const cell_rect = layout.projectGridCellRect(rect, snapshot.grid_width, snapshot.grid_depth, cell.x, cell.z);
            if (cell.has_non_empty) {
                const base_color = draw.fragmentCellColor(cell);
                const brick_delta = fragment_compare.fragmentBrickDelta(snapshot, cell);
                const fill = draw.withAlpha(base_color, switch (brick_delta) {
                    .changed => @as(u8, 142),
                    .same => @as(u8, 118),
                    .no_base => @as(u8, 104),
                });
                try canvas.fillRect(cell_rect, fill);
                try canvas.drawRect(cell_rect, draw.withAlpha(draw.lightenColor(base_color, 28), 196));
                try draw.drawBrickProbe(
                    canvas,
                    cell_rect.inset(1),
                    cell.top_brick_index,
                    draw.withAlpha(draw.lightenColor(base_color, switch (brick_delta) {
                        .changed => @as(u8, 96),
                        .same => @as(u8, 72),
                        .no_base => @as(u8, 52),
                    }), switch (brick_delta) {
                        .changed => @as(u8, 228),
                        .same => @as(u8, 208),
                        .no_base => @as(u8, 182),
                    }),
                );
                try draw.drawBrickPreviewSwatch(canvas, cell_rect, snapshot.brick_previews, cell.top_brick_index, .top_left);
                try draw.drawFragmentCellMarker(canvas, cell_rect, cell, draw.withAlpha(draw.lightenColor(base_color, 72), 216));
                if (brick_delta == .changed) {
                    try draw.drawFragmentDeltaMarker(canvas, cell_rect, draw.withAlpha(draw.lightenColor(base_color, 120), 240));
                }
            } else {
                try canvas.drawLine(cell_rect.x, cell_rect.y, cell_rect.right(), cell_rect.bottom(), draw.withAlpha(border_color, 176));
                try canvas.drawLine(cell_rect.right(), cell_rect.y, cell_rect.x, cell_rect.bottom(), draw.withAlpha(border_color, 176));
            }
        }
        try canvas.drawRect(zone_bounds, border_color);
    }
}

fn drawCompositionTile(
    canvas: *sdl.Canvas,
    snapshot: state.RenderSnapshot,
    tile_rect: sdl.Rect,
    tile: state.CompositionTileSnapshot,
) !void {
    const relief = draw.computeTileRelief(tile_rect, tile.total_height, snapshot.composition.max_total_height);
    const base_color = draw.compositionTileColor(tile);
    const side_color = draw.darkenColor(base_color, 28);
    const right_wall_color = draw.darkenColor(base_color, 54);
    const bottom_wall_color = draw.darkenColor(base_color, 42);
    const contour_color = draw.withAlpha(draw.lightenColor(base_color, 26), 236);

    try canvas.fillRect(tile_rect, side_color);
    if (relief.right_wall.w > 0 and relief.right_wall.h > 0) {
        try canvas.fillRect(relief.right_wall, right_wall_color);
    }
    if (relief.bottom_wall.w > 0 and relief.bottom_wall.h > 0) {
        try canvas.fillRect(relief.bottom_wall, bottom_wall_color);
    }
    try canvas.fillRect(relief.top_surface, base_color);

    const north_height = if (tile.z == 0) @as(u8, 0) else draw.compositionHeightAt(snapshot, tile.x, tile.z - 1);
    const west_height = if (tile.x == 0) @as(u8, 0) else draw.compositionHeightAt(snapshot, tile.x - 1, tile.z);

    try draw.drawCompositionContour(canvas, relief.top_surface, .north, draw.contourThickness(tile.total_height -| north_height), contour_color);
    try draw.drawCompositionContour(canvas, relief.top_surface, .west, draw.contourThickness(tile.total_height -| west_height), contour_color);
    try canvas.drawRect(relief.top_surface, draw.withAlpha(draw.lightenColor(base_color, 18), 212));
    try draw.drawBrickProbe(
        canvas,
        relief.top_surface.inset(1),
        tile.top_brick_index,
        draw.withAlpha(draw.lightenColor(base_color, draw.brickProbeStyle(tile.top_brick_index).accent), 148),
    );
    if (draw.shouldDrawCompositionBrickPreview(tile)) {
        try draw.drawBrickPreviewSwatch(canvas, relief.top_surface, snapshot.brick_previews, tile.top_brick_index, .bottom_right);
    }
    try draw.drawSurfaceMarker(canvas, relief.top_surface, tile, draw.withAlpha(draw.lightenColor(base_color, 64), 232));
}
