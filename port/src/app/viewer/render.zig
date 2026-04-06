const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const state = @import("../../runtime/room_state.zig");
const runtime_query = @import("../../runtime/world_query.zig");
const world_geometry = @import("../../runtime/world_geometry.zig");
const viewer_state = @import("state.zig");
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

pub fn renderDebugView(
    canvas: *sdl.Canvas,
    snapshot: state.RenderSnapshot,
    catalog: fragment_compare.FragmentComparisonCatalog,
    selection: fragment_compare.FragmentComparisonSelection,
    locomotion_status: LocomotionStatusDisplay,
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
    try canvas.fillRect(debug_layout.header, .{ .r = 15, .g = 20, .b = 26, .a = 255 });
    try canvas.drawRect(debug_layout.header, .{ .r = 59, .g = 76, .b = 88, .a = 255 });
    try canvas.fillRect(debug_layout.footer, .{ .r = 15, .g = 20, .b = 26, .a = 255 });
    try canvas.drawRect(debug_layout.footer, .{ .r = 59, .g = 76, .b = 88, .a = 255 });
    try canvas.fillRect(debug_layout.schematic_frame, .{ .r = 10, .g = 14, .b = 19, .a = 255 });
    try canvas.drawRect(debug_layout.schematic_frame, .{ .r = 56, .g = 80, .b = 92, .a = 255 });
    try drawComposition(canvas, debug_layout.schematic, snapshot);
    try drawFragmentZones(canvas, debug_layout.schematic, snapshot);
    if (fragment_panel.focus) |focus| {
        try drawFocusedFragmentZoneOverlay(canvas, debug_layout.schematic, snapshot, focus);
    }
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

    try drawLocomotionSchematicCue(
        canvas,
        debug_layout.schematic,
        snapshot.grid_width,
        snapshot.grid_depth,
        locomotion_status.schematic,
    );
    try drawLocomotionAttemptCue(
        canvas,
        debug_layout.schematic,
        snapshot.grid_width,
        snapshot.grid_depth,
        locomotion_status.attempt,
    );

    const hero = layout.projectWorldPoint(snapshot, debug_layout.schematic, snapshot.hero_position.x, snapshot.hero_position.z);
    try draw.drawCrosshair(canvas, hero, 8, .{ .r = 255, .g = 86, .b = 86, .a = 255 });
    try draw.drawMarker(canvas, hero, 6, .{ .r = 255, .g = 240, .b = 148, .a = 255 });
    try drawHud(canvas, debug_layout, snapshot, catalog, selection, locomotion_status);
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
    focus: fragment_compare.FragmentComparisonEntry,
) !void {
    const zone = findFocusedFragmentZone(snapshot, focus);
    const zone_rect = layout.projectGridAreaRect(
        rect,
        snapshot.grid_width,
        snapshot.grid_depth,
        zone.origin_x,
        zone.origin_z,
        zone.width,
        zone.depth,
    );
    try canvas.fillRect(zone_rect, focusedFragmentZoneOverlayFillColor());

    const inner_rect = zone_rect.inset(2);
    if (inner_rect.w > 4 and inner_rect.h > 4) {
        try canvas.drawRect(inner_rect, focusedFragmentZoneOverlayBorderColor());
    }
}

fn drawLocomotionSchematicCue(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    grid_width: usize,
    grid_depth: usize,
    cue: LocomotionSchematicCue,
) !void {
    switch (cue) {
        .none => {},
        .admitted_path => |value| {
            try drawCurrentLocomotionCellCue(canvas, rect, grid_width, grid_depth, value.current_cell);
            for (value.move_options) |move_option| {
                try drawLocomotionMoveOptionCue(canvas, rect, grid_width, grid_depth, move_option);
            }
        },
    }
}

fn drawLocomotionAttemptCue(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    grid_width: usize,
    grid_depth: usize,
    cue: LocomotionAttemptCue,
) !void {
    switch (cue) {
        .none => {},
        .accepted => |value| try drawLocomotionAttemptSegment(
            canvas,
            rect,
            grid_width,
            grid_depth,
            value.origin_cell,
            value.destination_cell,
            locomotionAttemptAcceptedColor(),
        ),
        .rejected => |value| try drawLocomotionAttemptSegment(
            canvas,
            rect,
            grid_width,
            grid_depth,
            value.current_cell,
            value.target_cell,
            locomotionAttemptRejectedColor(),
        ),
    }
}

fn drawLocomotionAttemptSegment(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    grid_width: usize,
    grid_depth: usize,
    start_cell: GridCell,
    end_cell: GridCell,
    color: sdl.Color,
) !void {
    const start = projectGridCellCenter(rect, grid_width, grid_depth, start_cell);
    const finish = projectGridCellCenter(rect, grid_width, grid_depth, end_cell);
    try canvas.drawLine(start.x, start.y, finish.x, finish.y, color);
}

fn drawCurrentLocomotionCellCue(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    grid_width: usize,
    grid_depth: usize,
    cell: GridCell,
) !void {
    const cell_rect = layout.projectGridCellRect(rect, grid_width, grid_depth, cell.x, cell.z);
    const fill_rect = insetRectSafe(cell_rect, 2);
    const border_rect = insetRectSafe(cell_rect, 1);

    try canvas.fillRect(fill_rect, locomotionCurrentCellOverlayFillColor());
    try canvas.drawRect(border_rect, locomotionCurrentCellOverlayBorderColor());
}

fn drawLocomotionMoveOptionCue(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    grid_width: usize,
    grid_depth: usize,
    move_option: LocomotionSchematicMoveOption,
) !void {
    const target_cell = move_option.target_cell orelse return;
    const cell_rect = layout.projectGridCellRect(rect, grid_width, grid_depth, target_cell.x, target_cell.z);
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
    grid_width: usize,
    grid_depth: usize,
    cell: GridCell,
) layout.ScreenPoint {
    const cell_rect = layout.projectGridCellRect(rect, grid_width, grid_depth, cell.x, cell.z);
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

fn drawHud(
    canvas: *sdl.Canvas,
    debug_layout: layout.DebugLayout,
    snapshot: state.RenderSnapshot,
    catalog: fragment_compare.FragmentComparisonCatalog,
    selection: fragment_compare.FragmentComparisonSelection,
    locomotion_status: LocomotionStatusDisplay,
) !void {
    const room_card = splitHudRow(debug_layout.header, 0, 3, 12);
    const fragment_card = splitHudRow(debug_layout.header, 1, 3, 12);
    const focus_card = splitHudRow(debug_layout.header, 2, 3, 12);
    const overlay_card = splitHudRow(debug_layout.footer, 0, 3, 12);
    const compare_card = splitHudRow(debug_layout.footer, 1, 3, 12);
    const nav_card = splitHudRow(debug_layout.footer, 2, 3, 12);

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
        room_card,
        "ROOM",
        .{ .r = 112, .g = 196, .b = 255, .a = 255 },
        &.{ room_line_0, room_line_1, room_line_2 },
    );

    if (snapshot.metadata.fragment_zone_count == 0 and snapshot.metadata.owned_fragment_count == 0) {
        var fragment_line_1_buffer: [48]u8 = undefined;
        const fragment_line_1 = try std.fmt.bufPrint(
            &fragment_line_1_buffer,
            "SCENE ZONES {d} OWNED {d}",
            .{ snapshot.metadata.fragment_zone_count, snapshot.metadata.owned_fragment_count },
        );
        try drawHudTextCard(
            canvas,
            fragment_card,
            "FRAGMENT STATE",
            .{ .r = 176, .g = 186, .b = 198, .a = 255 },
            &.{ "ZERO FRAGMENT CONTROL", fragment_line_1, "CELLS 0 OF 0" },
        );
    } else {
        var fragment_line_0_buffer: [48]u8 = undefined;
        const fragment_line_0 = try std.fmt.bufPrint(
            &fragment_line_0_buffer,
            "SCENE ZONES {d} OWNED {d}",
            .{ snapshot.metadata.fragment_zone_count, snapshot.metadata.owned_fragment_count },
        );
        var fragment_line_1_buffer: [48]u8 = undefined;
        const fragment_line_1 = try std.fmt.bufPrint(
            &fragment_line_1_buffer,
            "CELLS {d} OF {d}",
            .{ snapshot.metadata.fragment_non_empty_cell_count, snapshot.metadata.fragment_footprint_cell_count },
        );
        var fragment_line_2_buffer: [48]u8 = undefined;
        const fragment_line_2 = try std.fmt.bufPrint(
            &fragment_line_2_buffer,
            "CHG {d} EQ {d} NB {d}",
            .{ catalog.changed_count, catalog.exact_count, catalog.no_base_count },
        );
        try drawHudTextCard(
            canvas,
            fragment_card,
            "FRAGMENT STATE",
            .{ .r = 255, .g = 206, .b = 84, .a = 255 },
            &.{ fragment_line_0, fragment_line_1, fragment_line_2 },
        );
    }

    if (selection.focus) |focus| {
        const world_bounds = viewer_state.gridCellWorldBounds(focus.x, focus.z);
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
        var focus_line_3_buffer: [64]u8 = undefined;
        const focus_line_3 = try std.fmt.bufPrint(
            &focus_line_3_buffer,
            "FT {d} NE {d} Y {d}..{d}",
            .{ focus.zone_footprint_cell_count, focus.zone_non_empty_cell_count, focus.zone_y_min, focus.zone_y_max },
        );
        var focus_line_4_buffer: [64]u8 = undefined;
        const focus_line_4 = try std.fmt.bufPrint(
            &focus_line_4_buffer,
            "X {d}..{d} Z {d}..{d}",
            .{ world_bounds.min_x, world_bounds.max_x, world_bounds.min_z, world_bounds.max_z },
        );
        var focus_line_5_buffer: [64]u8 = undefined;
        const focus_line_5 = try std.fmt.bufPrint(
            &focus_line_5_buffer,
            "DELTA {s} STK {s}",
            .{ delta_summary, stack_summary },
        );
        try drawHudTextCardWithMetrics(
            canvas,
            focus_card,
            "FOCUS",
            fragment_compare.fragmentComparisonDeltaColor(focus.delta),
            1,
            1,
            &.{ focus_line_0, focus_line_1, focus_line_2, focus_line_3, focus_line_4, focus_line_5 },
        );
    } else {
        try drawHudTextCardWithMetrics(
            canvas,
            focus_card,
            "FOCUS",
            .{ .r = 112, .g = 196, .b = 255, .a = 255 },
            1,
            -1,
            locomotion_status.lines[0..locomotion_status.line_count],
        );
    }

    try drawOverlayLegendCard(canvas, overlay_card);
    try drawComparisonLegendCard(canvas, compare_card);
    const nav_lines: []const []const u8 = if (selection.focus != null)
        &.{ "LEFT RIGHT RANK", "UP DOWN CELL", "PINNED ROW FOCUS" }
    else switch (locomotion_status.schematic) {
        .admitted_path => &.{ "ENTER SEED HERO", "ARROWS MOVE HERO", "ARROWS MOVE FROM HERE" },
        .none => &.{ "ENTER SEED HERO", "ARROWS MOVE HERO", "RAW START STAYS" },
    };
    try drawHudTextCard(
        canvas,
        nav_card,
        "NAV",
        .{ .r = 112, .g = 196, .b = 255, .a = 255 },
        nav_lines,
    );
}

fn splitHudRow(row: sdl.Rect, index: usize, count: usize, gap: i32) sdl.Rect {
    const total_gap_width = gap * @as(i32, @intCast(count -| 1));
    const base_width = @divTrunc(row.w - total_gap_width, @as(i32, @intCast(count)));
    const x = row.x + (@as(i32, @intCast(index)) * (base_width + gap));
    const is_last = index == count - 1;
    return .{
        .x = x,
        .y = row.y,
        .w = if (is_last) row.right() - x + 1 else base_width,
        .h = row.h,
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
        _ = try draw.drawText(
            canvas,
            body.x,
            cursor_y,
            scale,
            .{ .r = 223, .g = 231, .b = 237, .a = 255 },
            line,
        );
        cursor_y += draw.textLineHeight(scale) + line_gap;
    }
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
