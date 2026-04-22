const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const state = @import("../../runtime/room_state.zig");
const runtime_session = @import("../../runtime/session.zig");
const runtime_query = @import("../../runtime/world_query.zig");
const world_geometry = @import("../../runtime/world_geometry.zig");
const layout = @import("layout.zig");
const draw = @import("draw.zig");
const fragment_compare = @import("fragment_compare.zig");

const GridCell = world_geometry.GridCell;
const CardinalDirection = world_geometry.CardinalDirection;

pub const LocomotionSchematicMoveOption = struct {
    direction: CardinalDirection,
    target_cell: ?GridCell,
    status: runtime_query.MoveTargetStatus,
};

pub const LocomotionSchematicCue = union(enum) {
    none,
    admitted_path: struct {
        current_cell: GridCell,
        move_options: [4]LocomotionSchematicMoveOption,
    },
};

pub const LocomotionAttemptCue = union(enum) {
    none,
    accepted: struct {
        direction: CardinalDirection,
        origin_cell: GridCell,
        destination_cell: GridCell,
    },
    rejected: struct {
        direction: CardinalDirection,
        current_cell: GridCell,
        target_cell: GridCell,
    },
};

pub const LocomotionStatusDisplay = struct {
    line_count: usize = 0,
    lines: [7][]const u8 = .{ "", "", "", "", "", "", "" },
    schematic: LocomotionSchematicCue = .none,
    attempt: LocomotionAttemptCue = .none,
};

pub const LocomotionStatusDisplayBuffer = struct {
    line_0: [128]u8 = undefined,
    line_1: [128]u8 = undefined,
    line_2: [128]u8 = undefined,
    line_3: [128]u8 = undefined,
    line_4: [128]u8 = undefined,
    line_5: [128]u8 = undefined,
    line_6: [128]u8 = undefined,
};

pub const DialogOverlayDisplay = struct {
    title: []const u8 = "",
    nav_title: []const u8 = "NAV / OVERLAY",
    line_count: usize = 0,
    lines: [4][]const u8 = .{ "", "", "", "" },
    accent: sdl.Color = .{ .r = 255, .g = 196, .b = 92, .a = 255 },
};

pub const ControlMode = enum {
    locomotion,
    fragment_navigation,
};

pub const SidebarTab = enum {
    info,
    controls,
};

pub const ZoomLevel = layout.ZoomLevel;

pub const ViewMode = enum {
    isometric,
    grid,
};

pub fn renderDebugView(
    canvas: *sdl.Canvas,
    snapshot: state.RenderSnapshot,
    catalog: fragment_compare.FragmentComparisonCatalog,
    selection: fragment_compare.FragmentComparisonSelection,
    locomotion_status: LocomotionStatusDisplay,
    control_mode: ControlMode,
    sidebar_tab: SidebarTab,
    zoom_level: ZoomLevel,
    view_mode: ViewMode,
    dialog_overlay: DialogOverlayDisplay,
    reward_collectibles: []const runtime_session.RewardCollectible,
) !void {
    const fragment_panel = fragment_compare.buildFragmentComparisonPanel(catalog, selection);
    const viewport = layout.computeGridViewport(snapshot, if (view_mode == .isometric and zoom_level == .fit) .room else zoom_level);
    const debug_layout = layout.computeDebugLayout(
        canvas.width,
        canvas.height,
        viewport.width,
        viewport.depth,
        fragment_panel.focus != null,
    );

    try canvas.clear(.{ .r = 13, .g = 20, .b = 26, .a = 255 });
    try canvas.fillRect(debug_layout.frame, .{ .r = 22, .g = 32, .b = 41, .a = 255 });
    try canvas.drawRect(debug_layout.frame, .{ .r = 96, .g = 123, .b = 142, .a = 255 });
    try canvas.fillRect(debug_layout.sidebar, .{ .r = 15, .g = 20, .b = 26, .a = 255 });
    try canvas.drawRect(debug_layout.sidebar, .{ .r = 59, .g = 76, .b = 88, .a = 255 });
    try canvas.fillRect(debug_layout.schematic_frame, .{ .r = 10, .g = 14, .b = 19, .a = 255 });
    try canvas.drawRect(debug_layout.schematic_frame, .{ .r = 56, .g = 80, .b = 92, .a = 255 });

    if (view_mode == .grid) {
        try drawComposition(canvas, debug_layout.schematic, snapshot, viewport);
        try drawFragmentZones(canvas, debug_layout.schematic, snapshot, viewport);
        if (fragment_panel.focus) |focus| {
            try drawFocusedFragmentZoneOverlay(canvas, debug_layout.schematic, snapshot, viewport, focus);
        }
        try drawGrid(canvas, debug_layout.schematic, viewport);
        if (fragment_panel.focus) |focus| {
            if (layout.projectGridCellRectInViewport(debug_layout.schematic, viewport, focus.x, focus.z)) |focus_rect| {
                try canvas.drawRect(focus_rect, fragment_compare.fragmentComparisonDeltaColor(focus.delta));
                const inner_rect = focus_rect.inset(2);
                if (inner_rect.w > 4 and inner_rect.h > 4) {
                    try canvas.drawRect(inner_rect, fragment_compare.fragmentComparisonDeltaColor(focus.delta));
                }
            }
        }

        for (snapshot.zones) |zone| {
            const rect = layout.projectZoneBoundsInViewport(debug_layout.schematic, viewport, zone) orelse continue;
            const zone_color = draw.zoneColor(zone.kind);
            try canvas.fillRect(rect, draw.withAlpha(zone_color, 40));
            try canvas.drawRect(rect, zone_color);
        }

        for (snapshot.tracks[0..snapshot.tracks.len -| 1], 0..) |track, index| {
            const next = snapshot.tracks[index + 1];
            const start = layout.projectWorldPointInViewport(debug_layout.schematic, viewport, track.x, track.z) orelse continue;
            const finish = layout.projectWorldPointInViewport(debug_layout.schematic, viewport, next.x, next.z) orelse continue;
            try canvas.drawLine(start.x, start.y, finish.x, finish.y, .{ .r = 59, .g = 201, .b = 255, .a = 192 });
        }

        for (snapshot.tracks) |track| {
            const point = layout.projectWorldPointInViewport(debug_layout.schematic, viewport, track.x, track.z) orelse continue;
            try draw.drawMarker(canvas, point, 4, .{ .r = 76, .g = 226, .b = 255, .a = 255 });
        }

        for (snapshot.objects) |object| {
            const point = layout.projectWorldPointInViewport(debug_layout.schematic, viewport, object.x, object.z) orelse continue;
            try draw.drawMarker(canvas, point, 6, .{ .r = 255, .g = 194, .b = 92, .a = 255 });
        }

        for (reward_collectibles) |collectible| {
            const point = layout.projectWorldPointInViewport(debug_layout.schematic, viewport, collectible.world_position.x, collectible.world_position.z) orelse continue;
            const target = layout.projectWorldPointInViewport(
                debug_layout.schematic,
                viewport,
                collectible.motion_target_world_position.x,
                collectible.motion_target_world_position.z,
            );
            try drawRewardCollectibleMarker(canvas, point, target, collectible);
        }

        try drawLocomotionSchematicCue(
            canvas,
            debug_layout.schematic,
            viewport,
            locomotion_status.schematic,
        );
        try drawLocomotionAttemptCue(
            canvas,
            debug_layout.schematic,
            viewport,
            locomotion_status.attempt,
        );

        if (layout.projectWorldPointInViewport(debug_layout.schematic, viewport, snapshot.hero_position.x, snapshot.hero_position.z)) |hero| {
            try draw.drawCrosshair(canvas, hero, 8, .{ .r = 255, .g = 86, .b = 86, .a = 255 });
            try draw.drawMarker(canvas, hero, 6, .{ .r = 255, .g = 240, .b = 148, .a = 255 });
        }
    } else {
        try drawIsometricView(canvas, debug_layout.schematic, snapshot, viewport, reward_collectibles);
    }
    try drawHud(canvas, debug_layout, snapshot, catalog, selection, locomotion_status, control_mode, sidebar_tab, zoom_level, view_mode, dialog_overlay);
    canvas.present();
}

fn drawGrid(canvas: *sdl.Canvas, rect: sdl.Rect, viewport: layout.GridViewport) !void {
    const left = rect.x;
    const right = rect.right();
    const top = rect.y;
    const bottom = rect.bottom();

    for (0..(viewport.width + 1)) |column| {
        const x = layout.interpolateAxis(left, right, column, viewport.width);
        const color = if ((viewport.origin_x + column) % 8 == 0)
            sdl.Color{ .r = 42, .g = 61, .b = 74, .a = 255 }
        else
            sdl.Color{ .r = 25, .g = 36, .b = 45, .a = 255 };
        try canvas.drawLine(x, top, x, bottom, color);
    }

    for (0..(viewport.depth + 1)) |row| {
        const y = layout.interpolateAxis(top, bottom, row, viewport.depth);
        const color = if ((viewport.origin_z + row) % 8 == 0)
            sdl.Color{ .r = 42, .g = 61, .b = 74, .a = 255 }
        else
            sdl.Color{ .r = 25, .g = 36, .b = 45, .a = 255 };
        try canvas.drawLine(left, y, right, y, color);
    }
}

fn drawComposition(canvas: *sdl.Canvas, rect: sdl.Rect, snapshot: state.RenderSnapshot, viewport: layout.GridViewport) !void {
    for (snapshot.composition.tiles) |tile| {
        const tile_rect = layout.projectGridCellRectInViewport(rect, viewport, tile.x, tile.z) orelse continue;
        try drawCompositionTile(canvas, snapshot, tile_rect, tile);
    }
}

fn drawFragmentZones(canvas: *sdl.Canvas, rect: sdl.Rect, snapshot: state.RenderSnapshot, viewport: layout.GridViewport) !void {
    for (snapshot.fragments.zones) |zone| {
        const zone_bounds = layout.projectGridAreaRectInViewport(
            rect,
            viewport,
            zone.origin_x,
            zone.origin_z,
            zone.width,
            zone.depth,
        ) orelse continue;
        const border_color = draw.fragmentZoneBorderColor(zone.initially_on);
        for (zone.cells) |cell| {
            const cell_rect = layout.projectGridCellRectInViewport(rect, viewport, cell.x, cell.z) orelse continue;
            if (cell.has_non_empty) {
                const base_color = draw.fragmentCellColor(cell);
                const brick_delta = fragment_compare.fragmentBrickDelta(snapshot, cell);
                const overlay = draw.withAlpha(base_color, switch (brick_delta) {
                    .changed => @as(u8, 142),
                    .same => @as(u8, 118),
                    .no_base => @as(u8, 104),
                });
                if (cell.top_brick_index != 0) {
                    try draw.drawBrickPreviewSurface(canvas, cell_rect, snapshot.brick_previews, cell.top_brick_index);
                    try canvas.fillRect(cell_rect, overlay);
                } else {
                    try canvas.fillRect(cell_rect, overlay);
                }
                try canvas.drawRect(cell_rect, draw.withAlpha(draw.lightenColor(base_color, 28), 196));
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

pub fn focusedFragmentZoneOverlayFillColor() sdl.Color {
    return .{ .r = 84, .g = 192, .b = 232, .a = 54 };
}

pub fn focusedFragmentZoneOverlayBorderColor() sdl.Color {
    return .{ .r = 112, .g = 228, .b = 255, .a = 228 };
}

pub fn locomotionCurrentCellOverlayFillColor() sdl.Color {
    return .{ .r = 52, .g = 138, .b = 196, .a = 92 };
}

pub fn locomotionCurrentCellOverlayBorderColor() sdl.Color {
    return .{ .r = 132, .g = 228, .b = 255, .a = 236 };
}

pub fn locomotionTargetOverlayColor(status: runtime_query.MoveTargetStatus) sdl.Color {
    return switch (status) {
        .allowed => .{ .r = 132, .g = 224, .b = 140, .a = 232 },
        .target_out_of_bounds => .{ .r = 255, .g = 198, .b = 92, .a = 232 },
        .target_empty => .{ .r = 255, .g = 122, .b = 122, .a = 232 },
        .target_missing_top_surface => .{ .r = 240, .g = 166, .b = 82, .a = 232 },
        .target_blocked => .{ .r = 214, .g = 132, .b = 92, .a = 232 },
        .target_height_mismatch => .{ .r = 116, .g = 212, .b = 228, .a = 232 },
    };
}

pub fn locomotionAttemptAcceptedColor() sdl.Color {
    return .{ .r = 96, .g = 240, .b = 132, .a = 240 };
}

pub fn locomotionAttemptRejectedColor() sdl.Color {
    return .{ .r = 255, .g = 108, .b = 108, .a = 240 };
}

fn drawFocusedFragmentZoneOverlay(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    snapshot: state.RenderSnapshot,
    viewport: layout.GridViewport,
    focus: fragment_compare.FragmentComparisonEntry,
) !void {
    const zone = findFocusedFragmentZone(snapshot, focus);
    const zone_rect = layout.projectGridAreaRectInViewport(
        rect,
        viewport,
        zone.origin_x,
        zone.origin_z,
        zone.width,
        zone.depth,
    ) orelse return;
    try canvas.fillRect(zone_rect, focusedFragmentZoneOverlayFillColor());

    const inner_rect = zone_rect.inset(2);
    if (inner_rect.w > 4 and inner_rect.h > 4) {
        try canvas.drawRect(inner_rect, focusedFragmentZoneOverlayBorderColor());
    }
}

fn drawLocomotionSchematicCue(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    viewport: layout.GridViewport,
    cue: LocomotionSchematicCue,
) !void {
    switch (cue) {
        .none => {},
        .admitted_path => |value| {
            try drawCurrentLocomotionCellCue(canvas, rect, viewport, value.current_cell);
            for (value.move_options) |move_option| {
                try drawLocomotionMoveOptionCue(canvas, rect, viewport, move_option);
            }
        },
    }
}

fn drawLocomotionAttemptCue(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    viewport: layout.GridViewport,
    cue: LocomotionAttemptCue,
) !void {
    switch (cue) {
        .none => {},
        .accepted => |value| try drawLocomotionAttemptSegment(
            canvas,
            rect,
            viewport,
            value.origin_cell,
            value.destination_cell,
            locomotionAttemptAcceptedColor(),
        ),
        .rejected => |value| try drawLocomotionAttemptSegment(
            canvas,
            rect,
            viewport,
            value.current_cell,
            value.target_cell,
            locomotionAttemptRejectedColor(),
        ),
    }
}

fn drawLocomotionAttemptSegment(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    viewport: layout.GridViewport,
    start_cell: GridCell,
    end_cell: GridCell,
    color: sdl.Color,
) !void {
    const start = projectGridCellCenter(rect, viewport, start_cell) orelse return;
    const finish = projectGridCellCenter(rect, viewport, end_cell) orelse return;
    try canvas.drawLine(start.x, start.y, finish.x, finish.y, color);
}

fn drawCurrentLocomotionCellCue(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    viewport: layout.GridViewport,
    cell: GridCell,
) !void {
    const cell_rect = layout.projectGridCellRectInViewport(rect, viewport, cell.x, cell.z) orelse return;
    const fill_rect = insetRectSafe(cell_rect, 2);
    const border_rect = insetRectSafe(cell_rect, 1);

    try canvas.fillRect(fill_rect, locomotionCurrentCellOverlayFillColor());
    try canvas.drawRect(border_rect, locomotionCurrentCellOverlayBorderColor());
}

fn drawLocomotionMoveOptionCue(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    viewport: layout.GridViewport,
    move_option: LocomotionSchematicMoveOption,
) !void {
    const target_cell = move_option.target_cell orelse return;
    const cell_rect = layout.projectGridCellRectInViewport(rect, viewport, target_cell.x, target_cell.z) orelse return;
    const border_rect = insetRectSafe(cell_rect, 1);
    const border_color = locomotionTargetOverlayColor(move_option.status);
    const label = shortDirectionLabel(move_option.direction);

    try canvas.drawRect(border_rect, border_color);
    _ = try draw.drawText(
        canvas,
        border_rect.x + 1,
        border_rect.y + 1,
        1,
        border_color,
        label,
    );
}

fn insetRectSafe(rect: sdl.Rect, inset: i32) sdl.Rect {
    const candidate = rect.inset(inset);
    if (candidate.w > 0 and candidate.h > 0) return candidate;
    return rect;
}

fn projectGridCellCenter(
    rect: sdl.Rect,
    viewport: layout.GridViewport,
    cell: GridCell,
) ?layout.ScreenPoint {
    const cell_rect = layout.projectGridCellRectInViewport(rect, viewport, cell.x, cell.z) orelse return null;
    return .{
        .x = cell_rect.x + @divTrunc(cell_rect.w, 2),
        .y = cell_rect.y + @divTrunc(cell_rect.h, 2),
    };
}

fn shortDirectionLabel(direction: CardinalDirection) []const u8 {
    return switch (direction) {
        .north => "N",
        .east => "E",
        .south => "S",
        .west => "W",
    };
}

fn findFocusedFragmentZone(
    snapshot: state.RenderSnapshot,
    focus: fragment_compare.FragmentComparisonEntry,
) state.FragmentZoneSnapshot {
    for (snapshot.fragments.zones) |zone| {
        if (zone.zone_index == focus.zone_index and
            zone.zone_num == focus.zone_num and
            zone.grm_index == focus.grm_index and
            zone.fragment_entry_index == focus.fragment_entry_index)
        {
            return zone;
        }
    }
    unreachable;
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
    if (tile.top_brick_index != 0) {
        try draw.drawBrickPreviewSurface(canvas, relief.top_surface, snapshot.brick_previews, tile.top_brick_index);
        try canvas.fillRect(relief.top_surface, draw.withAlpha(base_color, 68));
    } else {
        try canvas.fillRect(relief.top_surface, base_color);
    }

    const north_height = if (tile.z == 0) @as(u8, 0) else draw.compositionHeightAt(snapshot, tile.x, tile.z - 1);
    const west_height = if (tile.x == 0) @as(u8, 0) else draw.compositionHeightAt(snapshot, tile.x - 1, tile.z);

    try draw.drawCompositionContour(canvas, relief.top_surface, .north, draw.contourThickness(tile.total_height -| north_height), contour_color);
    try draw.drawCompositionContour(canvas, relief.top_surface, .west, draw.contourThickness(tile.total_height -| west_height), contour_color);
    try canvas.drawRect(relief.top_surface, draw.withAlpha(draw.lightenColor(base_color, 18), 212));
    try draw.drawSurfaceMarker(canvas, relief.top_surface, tile, draw.withAlpha(draw.lightenColor(base_color, 64), 232));
}

const IsoProjection = struct {
    rect: sdl.Rect,
    viewport: layout.GridViewport,
    origin_x: i32,
    origin_y: i32,
    half_w: i32,
    half_h: i32,
    height_scale: i32,
};

fn drawIsometricView(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    snapshot: state.RenderSnapshot,
    viewport: layout.GridViewport,
    reward_collectibles: []const runtime_session.RewardCollectible,
) !void {
    const iso = computeIsoProjection(rect, snapshot, viewport);
    try drawIsoBackdrop(canvas, iso);

    const max_diagonal = viewport.width + viewport.depth + 1;
    var diagonal: usize = 0;
    while (diagonal <= max_diagonal) : (diagonal += 1) {
        for (snapshot.composition.tiles) |tile| {
            if (tile.x < viewport.origin_x or tile.z < viewport.origin_z) continue;
            if (tile.x >= viewport.origin_x + viewport.width or tile.z >= viewport.origin_z + viewport.depth) continue;
            const local_x = tile.x - viewport.origin_x;
            const local_z = tile.z - viewport.origin_z;
            if (local_x + local_z != diagonal) continue;
            try drawIsoTile(canvas, iso, snapshot, tile);
        }
    }

    for (snapshot.zones) |zone| {
        try drawIsoZoneBounds(canvas, iso, zone);
    }

    for (snapshot.tracks[0..snapshot.tracks.len -| 1], 0..) |track, index| {
        const next = snapshot.tracks[index + 1];
        const start = isoWorldPoint(iso, track.x, track.z) orelse continue;
        const finish = isoWorldPoint(iso, next.x, next.z) orelse continue;
        try canvas.drawLine(start.x, start.y, finish.x, finish.y, .{ .r = 59, .g = 201, .b = 255, .a = 192 });
    }

    for (snapshot.tracks) |track| {
        const point = isoWorldPoint(iso, track.x, track.z) orelse continue;
        try draw.drawMarker(canvas, point, 4, .{ .r = 76, .g = 226, .b = 255, .a = 255 });
    }

    for (snapshot.objects) |object| {
        const point = isoWorldPoint(iso, object.x, object.z) orelse continue;
        try draw.drawMarker(canvas, point, 6, .{ .r = 255, .g = 194, .b = 92, .a = 255 });
    }

    for (reward_collectibles) |collectible| {
        const point = isoWorldPoint(iso, collectible.world_position.x, collectible.world_position.z) orelse continue;
        const target = isoWorldPoint(iso, collectible.motion_target_world_position.x, collectible.motion_target_world_position.z);
        try drawRewardCollectibleMarker(canvas, point, target, collectible);
    }

    if (isoWorldPoint(iso, snapshot.hero_position.x, snapshot.hero_position.z)) |hero| {
        try draw.drawCrosshair(canvas, hero, 9, .{ .r = 255, .g = 86, .b = 86, .a = 255 });
        try draw.drawMarker(canvas, hero, 6, .{ .r = 255, .g = 240, .b = 148, .a = 255 });
    }
}

fn drawRewardCollectibleMarker(
    canvas: *sdl.Canvas,
    point: layout.ScreenPoint,
    target: ?layout.ScreenPoint,
    collectible: runtime_session.RewardCollectible,
) !void {
    const color = rewardCollectibleColor(collectible.kind);
    if (!collectible.settled) {
        if (target) |target_point| {
            try canvas.drawLine(point.x, point.y, target_point.x, target_point.y, rewardCollectibleMotionPathColor(collectible.kind));
            try draw.drawCrosshair(canvas, target_point, 8, rewardCollectibleTargetColor(collectible.kind));
            try draw.drawMarker(canvas, target_point, 4, rewardCollectibleTargetColor(collectible.kind));
        }
    }
    const radius: i32 = if (collectible.settled) 7 else 5;
    try draw.drawCrosshair(canvas, point, radius + 2, draw.withAlpha(color, 220));
    try draw.drawMarker(canvas, point, radius, color);
}

fn rewardCollectibleMotionPathColor(kind: runtime_session.RuntimeBonusKind) sdl.Color {
    const color = rewardCollectibleColor(kind);
    return draw.withAlpha(color, 132);
}

fn rewardCollectibleTargetColor(kind: runtime_session.RuntimeBonusKind) sdl.Color {
    const color = rewardCollectibleColor(kind);
    return draw.withAlpha(color, 168);
}

fn rewardCollectibleColor(kind: runtime_session.RuntimeBonusKind) sdl.Color {
    return switch (kind) {
        .magic => .{ .r = 117, .g = 230, .b = 186, .a = 255 },
        .little_key => .{ .r = 245, .g = 216, .b = 95, .a = 255 },
    };
}

pub fn rewardCollectibleMotionPathColorForTesting(kind: runtime_session.RuntimeBonusKind) sdl.Color {
    return rewardCollectibleMotionPathColor(kind);
}

pub fn rewardCollectibleTargetColorForTesting(kind: runtime_session.RuntimeBonusKind) sdl.Color {
    return rewardCollectibleTargetColor(kind);
}

fn computeIsoProjection(rect: sdl.Rect, snapshot: state.RenderSnapshot, viewport: layout.GridViewport) IsoProjection {
    const diagonal_span = @max(1, viewport.width + viewport.depth);
    const max_height = @max(1, @as(i32, @intCast(snapshot.composition.max_total_height)));
    const width_limit = @max(3, @divTrunc(rect.w, @as(i32, @intCast(diagonal_span + 3))));
    const height_limit = @max(3, @divTrunc(rect.h * 2, @as(i32, @intCast(diagonal_span)) + max_height + 6));
    const half_w = @max(4, @min(width_limit, height_limit));
    const half_h = @max(2, @divTrunc(half_w, 2));
    const height_scale = @max(1, @divTrunc(half_h, 2));
    const bbox_center_x = @divTrunc((@as(i32, @intCast(viewport.width)) - @as(i32, @intCast(viewport.depth))) * half_w, 2);
    return .{
        .rect = rect,
        .viewport = viewport,
        .origin_x = rect.x + @divTrunc(rect.w, 2) - bbox_center_x,
        .origin_y = rect.y + 18 + (max_height * height_scale),
        .half_w = half_w,
        .half_h = half_h,
        .height_scale = height_scale,
    };
}

fn drawIsoBackdrop(canvas: *sdl.Canvas, iso: IsoProjection) !void {
    const origin = isoGridCorner(iso, iso.viewport.origin_x, iso.viewport.origin_z, 0) orelse return;
    const east = isoGridCorner(iso, iso.viewport.origin_x + iso.viewport.width, iso.viewport.origin_z, 0) orelse return;
    const south = isoGridCorner(iso, iso.viewport.origin_x + iso.viewport.width, iso.viewport.origin_z + iso.viewport.depth, 0) orelse return;
    const west = isoGridCorner(iso, iso.viewport.origin_x, iso.viewport.origin_z + iso.viewport.depth, 0) orelse return;
    try drawFilledDiamond(canvas, origin, east, south, west, .{ .r = 12, .g = 21, .b = 28, .a = 255 });
    try drawDiamondOutline(canvas, origin, east, south, west, .{ .r = 40, .g = 58, .b = 70, .a = 220 });
}

fn drawIsoTile(
    canvas: *sdl.Canvas,
    iso: IsoProjection,
    snapshot: state.RenderSnapshot,
    tile: state.CompositionTileSnapshot,
) !void {
    const height_px = @as(i32, tile.total_height) * iso.height_scale;
    const top = isoGridCorner(iso, tile.x, tile.z, height_px) orelse return;
    const right = isoGridCorner(iso, tile.x + 1, tile.z, height_px) orelse return;
    const bottom = isoGridCorner(iso, tile.x + 1, tile.z + 1, height_px) orelse return;
    const left = isoGridCorner(iso, tile.x, tile.z + 1, height_px) orelse return;
    const base_color = draw.compositionTileColor(tile);
    const border = draw.withAlpha(draw.lightenColor(base_color, 34), 226);

    if (height_px > 0) {
        const ground_right = isoGridCorner(iso, tile.x + 1, tile.z, 0) orelse return;
        const ground_bottom = isoGridCorner(iso, tile.x + 1, tile.z + 1, 0) orelse return;
        const ground_left = isoGridCorner(iso, tile.x, tile.z + 1, 0) orelse return;
        try drawFilledDiamond(canvas, right, ground_right, ground_bottom, bottom, draw.darkenColor(base_color, 56));
        try drawFilledDiamond(canvas, bottom, ground_bottom, ground_left, left, draw.darkenColor(base_color, 42));
    }

    try drawFilledDiamond(canvas, top, right, bottom, left, draw.lightenColor(base_color, 18));
    const north_height = if (tile.z == 0) @as(u8, 0) else draw.compositionHeightAt(snapshot, tile.x, tile.z - 1);
    const west_height = if (tile.x == 0) @as(u8, 0) else draw.compositionHeightAt(snapshot, tile.x - 1, tile.z);
    if (tile.total_height > north_height) {
        try canvas.drawLine(top.x, top.y, right.x, right.y, draw.withAlpha(border, 240));
    }
    if (tile.total_height > west_height) {
        try canvas.drawLine(top.x, top.y, left.x, left.y, draw.withAlpha(border, 240));
    }
    try canvas.drawLine(right.x, right.y, bottom.x, bottom.y, draw.withAlpha(border, 180));
    try canvas.drawLine(bottom.x, bottom.y, left.x, left.y, draw.withAlpha(border, 180));
}

fn drawIsoZoneBounds(canvas: *sdl.Canvas, iso: IsoProjection, zone: state.ZoneBoundsSnapshot) !void {
    const north = isoWorldPoint(iso, zone.x_min, zone.z_min) orelse return;
    const east = isoWorldPoint(iso, zone.x_max, zone.z_min) orelse return;
    const south = isoWorldPoint(iso, zone.x_max, zone.z_max) orelse return;
    const west = isoWorldPoint(iso, zone.x_min, zone.z_max) orelse return;
    const color = draw.zoneColor(zone.kind);
    try drawDiamondOutline(canvas, north, east, south, west, draw.withAlpha(color, 224));
}

fn isoGridCorner(iso: IsoProjection, grid_x: usize, grid_z: usize, height_px: i32) ?layout.ScreenPoint {
    if (grid_x < iso.viewport.origin_x or grid_z < iso.viewport.origin_z) return null;
    if (grid_x > iso.viewport.origin_x + iso.viewport.width or grid_z > iso.viewport.origin_z + iso.viewport.depth) return null;
    const local_x = @as(i32, @intCast(grid_x - iso.viewport.origin_x));
    const local_z = @as(i32, @intCast(grid_z - iso.viewport.origin_z));
    return .{
        .x = iso.origin_x + ((local_x - local_z) * iso.half_w),
        .y = iso.origin_y + ((local_x + local_z) * iso.half_h) - height_px,
    };
}

fn isoWorldPoint(iso: IsoProjection, world_x: i32, world_z: i32) ?layout.ScreenPoint {
    const world_grid_span_xz: i64 = 512;
    const min_x = @as(i64, @intCast(iso.viewport.origin_x)) * world_grid_span_xz;
    const min_z = @as(i64, @intCast(iso.viewport.origin_z)) * world_grid_span_xz;
    const max_x = @as(i64, @intCast(iso.viewport.origin_x + iso.viewport.width)) * world_grid_span_xz;
    const max_z = @as(i64, @intCast(iso.viewport.origin_z + iso.viewport.depth)) * world_grid_span_xz;
    const x = @as(i64, world_x);
    const z = @as(i64, world_z);
    if (x < min_x or x > max_x or z < min_z or z > max_z) return null;
    const local_x = x - min_x;
    const local_z = z - min_z;
    const screen_x = @as(i64, iso.origin_x) + @divTrunc((local_x - local_z) * @as(i64, iso.half_w), world_grid_span_xz);
    const screen_y = @as(i64, iso.origin_y) + @divTrunc((local_x + local_z) * @as(i64, iso.half_h), world_grid_span_xz);
    return .{ .x = @as(i32, @intCast(screen_x)), .y = @as(i32, @intCast(screen_y)) };
}

fn drawFilledDiamond(
    canvas: *sdl.Canvas,
    top: layout.ScreenPoint,
    right: layout.ScreenPoint,
    bottom: layout.ScreenPoint,
    left: layout.ScreenPoint,
    color: sdl.Color,
) !void {
    const upper_steps = @max(1, left.y - top.y);
    var upper_step: i32 = 0;
    while (upper_step <= upper_steps) : (upper_step += 1) {
        const start = interpolatePoint(top, left, upper_step, upper_steps);
        const finish = interpolatePoint(top, right, upper_step, upper_steps);
        try canvas.drawLine(start.x, start.y, finish.x, finish.y, color);
    }

    const lower_steps = @max(1, bottom.y - left.y);
    var lower_step: i32 = 0;
    while (lower_step <= lower_steps) : (lower_step += 1) {
        const start = interpolatePoint(left, bottom, lower_step, lower_steps);
        const finish = interpolatePoint(right, bottom, lower_step, lower_steps);
        try canvas.drawLine(start.x, start.y, finish.x, finish.y, color);
    }
}

fn drawDiamondOutline(
    canvas: *sdl.Canvas,
    top: layout.ScreenPoint,
    right: layout.ScreenPoint,
    bottom: layout.ScreenPoint,
    left: layout.ScreenPoint,
    color: sdl.Color,
) !void {
    try canvas.drawLine(top.x, top.y, right.x, right.y, color);
    try canvas.drawLine(right.x, right.y, bottom.x, bottom.y, color);
    try canvas.drawLine(bottom.x, bottom.y, left.x, left.y, color);
    try canvas.drawLine(left.x, left.y, top.x, top.y, color);
}

fn interpolatePoint(start: layout.ScreenPoint, finish: layout.ScreenPoint, step: i32, steps: i32) layout.ScreenPoint {
    return .{
        .x = start.x + @divTrunc((finish.x - start.x) * step, steps),
        .y = start.y + @divTrunc((finish.y - start.y) * step, steps),
    };
}

fn drawHud(
    canvas: *sdl.Canvas,
    debug_layout: layout.DebugLayout,
    snapshot: state.RenderSnapshot,
    catalog: fragment_compare.FragmentComparisonCatalog,
    selection: fragment_compare.FragmentComparisonSelection,
    locomotion_status: LocomotionStatusDisplay,
    control_mode: ControlMode,
    sidebar_tab: SidebarTab,
    zoom_level: ZoomLevel,
    view_mode: ViewMode,
    dialog_overlay: DialogOverlayDisplay,
) !void {
    const sidebar_content = debug_layout.sidebar.inset(10);
    const tab_bar = sdl.Rect{ .x = sidebar_content.x, .y = sidebar_content.y, .w = sidebar_content.w, .h = 30 };
    try drawSidebarTabs(canvas, tab_bar, sidebar_tab);

    const content = sdl.Rect{
        .x = sidebar_content.x,
        .y = tab_bar.y + tab_bar.h + 10,
        .w = sidebar_content.w,
        .h = @max(1, sidebar_content.bottom() - (tab_bar.y + tab_bar.h + 10) + 1),
    };
    if (sidebar_tab == .controls) {
        const panels = computeSidebarPanels(content);
        try drawControlsTab(canvas, panels, selection, locomotion_status, control_mode, zoom_level, view_mode, dialog_overlay);
        return;
    }
    const panels = computeInfoSidebarPanels(content);

    var scene_kind_buffer: [32]u8 = undefined;
    const scene_kind = upperAscii(&scene_kind_buffer, snapshot.metadata.scene_kind);

    var room_line_0_buffer: [48]u8 = undefined;
    const room_line_0 = try std.fmt.bufPrint(
        &room_line_0_buffer,
        "SCN {d} BKG {d}",
        .{ snapshot.metadata.scene_entry_index, snapshot.metadata.background_entry_index },
    );
    var room_line_1_buffer: [48]u8 = undefined;
    const room_line_1 = if (snapshot.metadata.classic_loader_scene_number) |loader_scene|
        try std.fmt.bufPrint(&room_line_1_buffer, "LDR {d} {s}", .{ loader_scene, scene_kind })
    else
        try std.fmt.bufPrint(&room_line_1_buffer, "LDR NONE {s}", .{scene_kind});
    var room_line_2_buffer: [48]u8 = undefined;
    const room_line_2 = try std.fmt.bufPrint(
        &room_line_2_buffer,
        "OBJ {d} ZON {d} TRK {d}",
        .{ snapshot.metadata.object_count, snapshot.metadata.zone_count, snapshot.metadata.track_count },
    );
    try drawHudTextCard(
        canvas,
        panels.overview,
        "OVERVIEW",
        .{ .r = 112, .g = 196, .b = 255, .a = 255 },
        &.{ room_line_0, room_line_1, room_line_2, viewModeLabel(view_mode), zoomLevelLabel(zoom_level) },
    );

    if (dialog_overlay.line_count != 0) {
        try drawHudTextCardWithMetrics(
            canvas,
            panels.status,
            dialog_overlay.title,
            dialog_overlay.accent,
            2,
            4,
            dialog_overlay.lines[0..dialog_overlay.line_count],
        );
    } else {
        try drawHudTextCardWithMetrics(
            canvas,
            panels.status,
            "STATUS",
            .{ .r = 112, .g = 196, .b = 255, .a = 255 },
            2,
            4,
            locomotion_status.lines[0..locomotion_status.line_count],
        );
    }

    var fragment_line_0_buffer: [48]u8 = undefined;
    const fragment_line_0 = try std.fmt.bufPrint(
        &fragment_line_0_buffer,
        "FRAG Z {d} OWN {d}",
        .{ snapshot.metadata.fragment_zone_count, snapshot.metadata.owned_fragment_count },
    );
    var fragment_line_1_buffer: [48]u8 = undefined;
    const fragment_line_1 = try std.fmt.bufPrint(
        &fragment_line_1_buffer,
        "CELLS {d}/{d}",
        .{ snapshot.metadata.fragment_non_empty_cell_count, snapshot.metadata.fragment_footprint_cell_count },
    );
    var compare_line_buffer: [48]u8 = undefined;
    const compare_line = try std.fmt.bufPrint(
        &compare_line_buffer,
        "CMP CHG {d} EQ {d} NB {d}",
        .{ catalog.changed_count, catalog.exact_count, catalog.no_base_count },
    );

    if (selection.focus) |focus| {
        var delta_summary_buffer: [24]u8 = undefined;
        const delta_summary = try fragment_compare.formatDeltaSummary(&delta_summary_buffer, focus.detail);
        var stack_summary_buffer: [16]u8 = undefined;
        const stack_summary = try fragment_compare.formatStackSummary(&stack_summary_buffer, focus.detail);
        var focus_line_0_buffer: [48]u8 = undefined;
        const focus_line_0 = try std.fmt.bufPrint(
            &focus_line_0_buffer,
            "CELL {d} {d} FR {d}",
            .{ focus.x, focus.z, focus.fragment_entry_index },
        );
        var focus_line_1_buffer: [48]u8 = undefined;
        const focus_line_1 = try std.fmt.bufPrint(
            &focus_line_1_buffer,
            "ZONE {d} NUM {d} {s}",
            .{ focus.zone_index, focus.zone_num, if (focus.initially_on) "ON" else "OFF" },
        );
        var focus_line_2_buffer: [48]u8 = undefined;
        const focus_line_2 = try std.fmt.bufPrint(
            &focus_line_2_buffer,
            "GRM {d} SZ {d}x{d}x{d}",
            .{ focus.grm_index, focus.zone_width, focus.zone_height, focus.zone_depth },
        );
        var focus_line_5_buffer: [64]u8 = undefined;
        const focus_line_5 = try std.fmt.bufPrint(
            &focus_line_5_buffer,
            "DELTA {s} STK {s}",
            .{ delta_summary, stack_summary },
        );
        try drawHudTextCardWithMetrics(
            canvas,
            panels.details,
            "DETAILS",
            fragment_compare.fragmentComparisonDeltaColor(focus.delta),
            2,
            4,
            &.{ focus_line_0, focus_line_1, focus_line_2, focus_line_5, fragment_line_0, compare_line },
        );
    } else {
        try drawHudTextCardWithMetrics(
            canvas,
            panels.details,
            "DETAILS",
            .{ .r = 176, .g = 186, .b = 198, .a = 255 },
            2,
            4,
            &.{ "FOCUS NONE", fragment_line_0, fragment_line_1, compare_line },
        );
    }

    const nav_lines: []const []const u8 = if (selection.focus != null)
        switch (control_mode) {
            .fragment_navigation => &.{ "TAB HERO CTRL", "LEFT RIGHT RANK", "UP DOWN CELL" },
            .locomotion => switch (locomotion_status.schematic) {
                .admitted_path => &.{ "TAB FRAG NAV", "ARROWS MOVE HERO", "ENTER RESEED HERO" },
                .none => &.{ "TAB FRAG NAV", "ENTER SEED HERO", "RAW START STAYS" },
            },
        }
    else switch (locomotion_status.schematic) {
        .admitted_path => &.{ "ENTER SEED HERO", "ARROWS MOVE HERO", "ARROWS MOVE FROM HERE" },
        .none => &.{ "ENTER SEED HERO", "ARROWS MOVE HERO", "RAW START STAYS" },
    };
    const nav_title = if (dialog_overlay.line_count != 0) dialog_overlay.nav_title else "NAV";
    try drawHudTextCard(
        canvas,
        panels.nav,
        nav_title,
        .{ .r = 112, .g = 196, .b = 255, .a = 255 },
        nav_lines,
    );
}

fn drawSidebarTabs(canvas: *sdl.Canvas, rect: sdl.Rect, active: SidebarTab) !void {
    const gap = 8;
    const tab_width = @divTrunc(rect.w - gap, 2);
    const info_rect = sdl.Rect{ .x = rect.x, .y = rect.y, .w = tab_width, .h = rect.h };
    const controls_rect = sdl.Rect{ .x = info_rect.x + info_rect.w + gap, .y = rect.y, .w = rect.right() - (info_rect.x + info_rect.w + gap) + 1, .h = rect.h };

    try drawSidebarTab(canvas, info_rect, "INFO", active == .info);
    try drawSidebarTab(canvas, controls_rect, "CTRL", active == .controls);
}

fn drawSidebarTab(canvas: *sdl.Canvas, rect: sdl.Rect, label: []const u8, is_active: bool) !void {
    const accent = if (is_active)
        sdl.Color{ .r = 112, .g = 196, .b = 255, .a = 255 }
    else
        sdl.Color{ .r = 92, .g = 111, .b = 123, .a = 255 };
    try canvas.fillRect(rect, if (is_active)
        sdl.Color{ .r = 17, .g = 31, .b = 42, .a = 255 }
    else
        sdl.Color{ .r = 10, .g = 15, .b = 20, .a = 236 });
    try canvas.drawRect(rect, draw.withAlpha(accent, 224));
    _ = try draw.drawText(canvas, rect.x + 10, rect.y + 8, 2, accent, label);
}

fn drawControlsTab(
    canvas: *sdl.Canvas,
    panels: SidebarPanels,
    selection: fragment_compare.FragmentComparisonSelection,
    locomotion_status: LocomotionStatusDisplay,
    control_mode: ControlMode,
    zoom_level: ZoomLevel,
    view_mode: ViewMode,
    dialog_overlay: DialogOverlayDisplay,
) !void {
    const mode_line = if (control_mode == .fragment_navigation and selection.focus != null)
        "MODE FRAGMENT NAV"
    else
        "MODE HERO CTRL";
    const focus_line = if (selection.focus != null) "FOCUS ACTIVE" else "FOCUS NONE";
    const motion_line = switch (locomotion_status.schematic) {
        .admitted_path => "MOVE OPTIONS ON",
        .none => "MOVE OPTIONS OFF",
    };
    const zoom_line = zoomLevelLabel(zoom_level);
    const view_line = viewModeLabel(view_mode);

    try drawHudTextCard(
        canvas,
        panels.room,
        "VIEW",
        .{ .r = 112, .g = 196, .b = 255, .a = 255 },
        &.{ view_line, "V ISO / GRID", "C INFO / CTRL" },
    );
    try drawHudTextCard(
        canvas,
        panels.gameplay,
        "OVERLAYS",
        .{ .r = 117, .g = 230, .b = 186, .a = 255 },
        &.{ "HERO MARK ON", "OBJECTS ON", "ZONES ON", "TRACKS ON", if (dialog_overlay.line_count != 0) dialog_overlay.nav_title else "LEGEND ON INFO" },
    );
    try drawHudTextCard(
        canvas,
        panels.focus,
        "INPUT",
        .{ .r = 255, .g = 206, .b = 84, .a = 255 },
        &.{ mode_line, "TAB HERO / FRAG", "ARROWS MOVE / SELECT", "ENTER SEED / ACK", "SPACE TICK", "W ACTION F MAGIC" },
    );
    try drawHudTextCard(
        canvas,
        panels.fragments,
        "STATUS",
        .{ .r = 255, .g = 148, .b = 118, .a = 255 },
        &.{ focus_line, motion_line },
    );
    try drawHudTextCard(
        canvas,
        panels.compare,
        "ZOOM",
        .{ .r = 176, .g = 186, .b = 198, .a = 255 },
        &.{ zoom_line, "+ ZOOM IN", "- ZOOM OUT", "0 RESET FIT" },
    );
    try drawHudTextCard(
        canvas,
        panels.nav,
        "NAV",
        .{ .r = 112, .g = 196, .b = 255, .a = 255 },
        &.{ "C SWITCH TAB", "1 KEY SOURCE", "2 KEY PICKUP", "3 HOUSE DOOR", "4 CELLAR RETURN" },
    );
}

fn zoomLevelLabel(zoom_level: ZoomLevel) []const u8 {
    return switch (zoom_level) {
        .fit => "ZOOM FIT",
        .room => "ZOOM ROOM",
        .detail => "ZOOM DETAIL",
    };
}

fn viewModeLabel(view_mode: ViewMode) []const u8 {
    return switch (view_mode) {
        .isometric => "VIEW ISO",
        .grid => "VIEW GRID",
    };
}

const SidebarPanels = struct {
    room: sdl.Rect,
    gameplay: sdl.Rect,
    focus: sdl.Rect,
    fragments: sdl.Rect,
    compare: sdl.Rect,
    nav: sdl.Rect,
};

const InfoSidebarPanels = struct {
    overview: sdl.Rect,
    status: sdl.Rect,
    details: sdl.Rect,
    nav: sdl.Rect,
};

fn computeInfoSidebarPanels(sidebar: sdl.Rect) InfoSidebarPanels {
    const gap = 12;
    const overview_height = @min(148, @max(128, @divTrunc(sidebar.h, 6)));
    const status_height = @min(280, @max(220, @divTrunc(sidebar.h, 3)));
    const details_height = @min(190, @max(150, @divTrunc(sidebar.h, 4)));

    var y = sidebar.y;
    const overview = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = overview_height };
    y += overview.h + gap;
    const status = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = status_height };
    y += status.h + gap;
    const details = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = details_height };
    y += details.h + gap;
    const nav = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = @max(1, sidebar.bottom() - y + 1) };

    return .{
        .overview = overview,
        .status = status,
        .details = details,
        .nav = nav,
    };
}

fn computeSidebarPanels(sidebar: sdl.Rect) SidebarPanels {
    const gap = 10;
    const room_height = @min(96, @max(72, @divTrunc(sidebar.h, 9)));
    const gameplay_height = @min(124, @max(88, @divTrunc(sidebar.h, 7)));
    const focus_height = @min(210, @max(144, @divTrunc(sidebar.h, 3)));
    const fragment_height = @min(110, @max(72, @divTrunc(sidebar.h, 8)));
    const compare_height = @min(128, @max(108, @divTrunc(sidebar.h, 8)));

    var y = sidebar.y;
    const room = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = room_height };
    y += room.h + gap;
    const gameplay = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = gameplay_height };
    y += gameplay.h + gap;
    const focus = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = focus_height };
    y += focus.h + gap;
    const fragments = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = fragment_height };
    y += fragments.h + gap;
    const compare = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = compare_height };
    y += compare.h + gap;
    const nav = sdl.Rect{ .x = sidebar.x, .y = y, .w = sidebar.w, .h = @max(1, sidebar.bottom() - y + 1) };

    return .{
        .room = room,
        .gameplay = gameplay,
        .focus = focus,
        .fragments = fragments,
        .compare = compare,
        .nav = nav,
    };
}

fn drawHudTextCard(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    title: []const u8,
    accent: sdl.Color,
    lines: []const []const u8,
) !void {
    return drawHudTextCardWithMetrics(canvas, rect, title, accent, 2, 4, lines);
}

fn drawHudTextCardWithMetrics(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    title: []const u8,
    accent: sdl.Color,
    scale: i32,
    line_gap: i32,
    lines: []const []const u8,
) !void {
    const body = try drawHudCardFrame(canvas, rect, title, accent);
    var cursor_y = body.y;
    for (lines) |line| {
        if (cursor_y + draw.textLineHeight(scale) > body.bottom() + 1) break;
        var clipped_buffer: [96]u8 = undefined;
        const visible_line = clipHudLine(&clipped_buffer, line, body.w, scale);
        _ = try draw.drawText(
            canvas,
            body.x,
            cursor_y,
            scale,
            .{ .r = 223, .g = 231, .b = 237, .a = 255 },
            visible_line,
        );
        cursor_y += draw.textLineHeight(scale) + line_gap;
    }
}

fn clipHudLine(buffer: []u8, line: []const u8, max_width: i32, scale: i32) []const u8 {
    if (draw.textWidth(line, scale) <= max_width) return line;
    const suffix = "...";
    const suffix_width = draw.textWidth(suffix, scale);
    if (max_width <= suffix_width or buffer.len < suffix.len) {
        return line[0..@min(line.len, @max(@as(usize, 1), buffer.len))];
    }

    var copied: usize = 0;
    while (copied < line.len and copied + suffix.len < buffer.len) : (copied += 1) {
        const candidate = line[0 .. copied + 1];
        if (draw.textWidth(candidate, scale) + suffix_width > max_width) break;
        buffer[copied] = line[copied];
    }
    if (copied == 0) return suffix;
    std.mem.copyForwards(u8, buffer[copied .. copied + suffix.len], suffix);
    return buffer[0 .. copied + suffix.len];
}

fn drawHudCardFrame(canvas: *sdl.Canvas, rect: sdl.Rect, title: []const u8, accent: sdl.Color) !sdl.Rect {
    try canvas.fillRect(rect, .{ .r = 10, .g = 15, .b = 20, .a = 236 });
    try canvas.drawRect(rect, draw.withAlpha(draw.lightenColor(accent, 10), 224));

    const title_height = 18;
    const title_bar = sdl.Rect{
        .x = rect.x,
        .y = rect.y,
        .w = rect.w,
        .h = @min(title_height, rect.h),
    };
    try canvas.fillRect(title_bar, draw.withAlpha(draw.darkenColor(accent, 84), 124));
    _ = try draw.drawText(canvas, title_bar.x + 8, title_bar.y + 4, 2, accent, title);

    return .{
        .x = rect.x + 8,
        .y = title_bar.y + title_bar.h + 8,
        .w = @max(1, rect.w - 16),
        .h = @max(1, rect.h - title_bar.h - 16),
    };
}

fn drawOverlayLegendCard(canvas: *sdl.Canvas, rect: sdl.Rect) !void {
    const body = try drawHudCardFrame(canvas, rect, "OVERLAYS", .{ .r = 117, .g = 230, .b = 186, .a = 255 });
    const item_width = @divTrunc(@max(1, body.w - 12), 2);
    const item_height = @divTrunc(@max(1, body.h - 8), 2);

    const LegendKind = enum { hero, object, track, zone, fragment };
    const items = [_]struct { label: []const u8, kind: LegendKind }{
        .{ .label = "HERO", .kind = .hero },
        .{ .label = "OBJECT", .kind = .object },
        .{ .label = "TRACK", .kind = .track },
        .{ .label = "ZONE", .kind = .zone },
        .{ .label = "FRAGMENT", .kind = .fragment },
    };

    for (items, 0..) |item, index| {
        const column: i32 = @intCast(index % 2);
        const row: i32 = @intCast(index / 2);
        const item_rect = sdl.Rect{
            .x = body.x + (column * (item_width + 12)),
            .y = body.y + (row * (item_height + 8)),
            .w = item_width,
            .h = item_height,
        };
        try drawOverlayLegendItem(canvas, item_rect, item.label, item.kind);
    }
}

fn drawOverlayLegendItem(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    label: []const u8,
    kind: anytype,
) !void {
    const icon_rect = sdl.Rect{
        .x = rect.x,
        .y = rect.y,
        .w = 18,
        .h = @min(18, rect.h),
    };
    const text_x = icon_rect.x + icon_rect.w + 6;
    const text_y = rect.y + @max(0, @divTrunc(rect.h - draw.textLineHeight(2), 2));

    switch (kind) {
        .hero => {
            const center = layout.ScreenPoint{ .x = icon_rect.x + @divTrunc(icon_rect.w, 2), .y = icon_rect.y + @divTrunc(icon_rect.h, 2) };
            try draw.drawCrosshair(canvas, center, 5, .{ .r = 255, .g = 86, .b = 86, .a = 255 });
            try draw.drawMarker(canvas, center, 4, .{ .r = 255, .g = 240, .b = 148, .a = 255 });
        },
        .object => try canvas.fillRect(icon_rect.inset(5), .{ .r = 255, .g = 194, .b = 92, .a = 255 }),
        .track => {
            const y = icon_rect.y + @divTrunc(icon_rect.h, 2);
            try canvas.drawLine(icon_rect.x, y, icon_rect.right(), y, .{ .r = 59, .g = 201, .b = 255, .a = 220 });
        },
        .zone => try canvas.drawRect(icon_rect.inset(3), draw.zoneColor(.scenario)),
        .fragment => {
            const fill = icon_rect.inset(4);
            try canvas.fillRect(fill, .{ .r = 224, .g = 178, .b = 86, .a = 220 });
            try canvas.drawRect(fill, draw.fragmentZoneBorderColor(true));
        },
    }

    _ = try draw.drawText(canvas, text_x, text_y, 2, .{ .r = 223, .g = 231, .b = 237, .a = 255 }, label);
}

fn drawComparisonLegendCard(canvas: *sdl.Canvas, rect: sdl.Rect) !void {
    const body = try drawHudCardFrame(canvas, rect, "COMPARE ORDER", .{ .r = 255, .g = 148, .b = 118, .a = 255 });
    const rows = [_]struct { label: []const u8, color: sdl.Color }{
        .{ .label = "CHANGED FIRST", .color = fragment_compare.fragmentComparisonDeltaColor(.changed) },
        .{ .label = "EXACT NEXT", .color = fragment_compare.fragmentComparisonDeltaColor(.exact) },
        .{ .label = "NO BASE LAST", .color = fragment_compare.fragmentComparisonDeltaColor(.no_base) },
    };

    const row_gap = 4;
    const row_height = @max(12, @divTrunc(body.h - (row_gap * @as(i32, @intCast(rows.len -| 1))), @as(i32, @intCast(rows.len))));
    var cursor_y = body.y;
    for (rows) |row| {
        const swatch = sdl.Rect{ .x = body.x, .y = cursor_y + 2, .w = 12, .h = @min(12, row_height - 4) };
        try canvas.fillRect(swatch, draw.withAlpha(row.color, 216));
        try canvas.drawRect(swatch, row.color);
        _ = try draw.drawText(
            canvas,
            swatch.x + swatch.w + 6,
            cursor_y + @max(0, @divTrunc(row_height - draw.textLineHeight(2), 2)),
            2,
            .{ .r = 223, .g = 231, .b = 237, .a = 255 },
            row.label,
        );
        cursor_y += row_height + row_gap;
    }
}

fn comparisonDeltaLabel(delta: fragment_compare.FragmentComparisonDelta) []const u8 {
    return switch (delta) {
        .changed => "CHANGED",
        .exact => "EXACT",
        .no_base => "NO BASE",
    };
}

fn upperAscii(buffer: []u8, text: []const u8) []const u8 {
    const len = @min(buffer.len, text.len);
    for (text[0..len], 0..) |char, index| {
        buffer[index] = if (char >= 'a' and char <= 'z') char - 32 else char;
    }
    return buffer[0..len];
}
