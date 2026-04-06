const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const background_data = @import("../../game_data/background.zig");
const runtime_locomotion = @import("../../runtime/locomotion.zig");
const state = @import("../../runtime/room_state.zig");
const runtime_query = @import("../../runtime/world_query.zig");
const room_fixtures = @import("../../testing/room_fixtures.zig");
const viewer_shell = @import("../viewer_shell.zig");
const viewer_state = @import("state.zig");
const draw = @import("draw.zig");
const layout = @import("layout.zig");
const render = @import("render.zig");
const fragment_compare = @import("fragment_compare.zig");

fn hasTraceRectOp(trace: sdl.CanvasTrace, comptime tag: std.meta.Tag(sdl.TraceOp), rect: sdl.Rect, color: ?sdl.Color) bool {
    for (trace.ops.items) |op| {
        switch (op) {
            tag => |entry| {
                if (!std.meta.eql(entry.rect, rect)) continue;
                if (color) |expected| {
                    if (!std.meta.eql(entry.color, expected)) continue;
                }
                return true;
            },
            else => {},
        }
    }
    return false;
}

fn hasTraceRectColor(trace: sdl.CanvasTrace, comptime tag: std.meta.Tag(sdl.TraceOp), color: sdl.Color) bool {
    for (trace.ops.items) |op| {
        switch (op) {
            tag => |entry| {
                if (std.meta.eql(entry.color, color)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn hasPresent(trace: sdl.CanvasTrace) bool {
    for (trace.ops.items) |op| {
        if (std.meta.activeTag(op) == .present) return true;
    }
    return false;
}

fn hasTraceText(trace: sdl.CanvasTrace, text: []const u8) bool {
    for (trace.ops.items) |op| {
        switch (op) {
            .text => |entry| {
                if (std.mem.eql(u8, entry.text[0..entry.text_len], text)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn hasTraceTextOp(trace: sdl.CanvasTrace, text: []const u8, rect: sdl.Rect, color: ?sdl.Color) bool {
    for (trace.ops.items) |op| {
        switch (op) {
            .text => |entry| {
                if (!std.mem.eql(u8, entry.text[0..entry.text_len], text)) continue;
                if (!std.meta.eql(entry.rect, rect)) continue;
                if (color) |expected| {
                    if (!std.meta.eql(entry.color, expected)) continue;
                }
                return true;
            },
            else => {},
        }
    }
    return false;
}

fn expectTraceHasMoveOptionsForPosition(
    trace: sdl.CanvasTrace,
    room: *const viewer_shell.RoomSnapshot,
    hero_position: viewer_shell.WorldPointSnapshot,
) !void {
    const query = runtime_query.init(room);
    const move_options = try query.evaluateCardinalMoveOptions(hero_position);

    var north_cell_buffer: [16]u8 = undefined;
    var east_cell_buffer: [16]u8 = undefined;
    var south_cell_buffer: [16]u8 = undefined;
    var west_cell_buffer: [16]u8 = undefined;
    var line_0_buffer: [96]u8 = undefined;
    const line_0 = try std.fmt.bufPrint(
        &line_0_buffer,
        "N {s} {s} E {s} {s}",
        .{
            try formatDisplayTargetCellValue(&north_cell_buffer, move_options.options[0].evaluation.raw_cell.cell),
            moveOptionStatusHudLabel(move_options.options[0].evaluation.status),
            try formatDisplayTargetCellValue(&east_cell_buffer, move_options.options[1].evaluation.raw_cell.cell),
            moveOptionStatusHudLabel(move_options.options[1].evaluation.status),
        },
    );
    var line_1_buffer: [96]u8 = undefined;
    const line_1 = try std.fmt.bufPrint(
        &line_1_buffer,
        "S {s} {s} W {s} {s}",
        .{
            try formatDisplayTargetCellValue(&south_cell_buffer, move_options.options[2].evaluation.raw_cell.cell),
            moveOptionStatusHudLabel(move_options.options[2].evaluation.status),
            try formatDisplayTargetCellValue(&west_cell_buffer, move_options.options[3].evaluation.raw_cell.cell),
            moveOptionStatusHudLabel(move_options.options[3].evaluation.status),
        },
    );

    try std.testing.expect(hasTraceText(trace, line_0));
    try std.testing.expect(hasTraceText(trace, line_1));
}

fn formatDisplayTargetCellValue(buffer: []u8, cell: ?viewer_shell.GridCell) ![]const u8 {
    if (cell) |resolved| return std.fmt.bufPrint(buffer, "{d}/{d}", .{ resolved.x, resolved.z });
    return "NONE";
}

fn moveOptionStatusHudLabel(status: runtime_query.MoveTargetStatus) []const u8 {
    return switch (status) {
        .allowed => "ALLOWED",
        .target_out_of_bounds => "OOB",
        .target_empty => "EMPTY",
        .target_missing_top_surface => "NO_TOP",
        .target_blocked => "BLOCKED",
        .target_height_mismatch => "HEIGHT",
    };
}

fn shortDirectionLabel(direction: viewer_shell.CardinalDirection) []const u8 {
    return switch (direction) {
        .north => "N",
        .east => "E",
        .south => "S",
        .west => "W",
    };
}

fn insetRectSafe(rect: sdl.Rect, inset: i32) sdl.Rect {
    const candidate = rect.inset(inset);
    if (candidate.w > 0 and candidate.h > 0) return candidate;
    return rect;
}

fn expectNoLocomotionSchematicCue(trace: sdl.CanvasTrace) !void {
    try std.testing.expect(!hasTraceRectColor(trace, .fill_rect, render.locomotionCurrentCellOverlayFillColor()));
    try std.testing.expect(!hasTraceRectColor(trace, .draw_rect, render.locomotionCurrentCellOverlayBorderColor()));

    const target_statuses = [_]runtime_query.MoveTargetStatus{
        .allowed,
        .target_out_of_bounds,
        .target_empty,
        .target_missing_top_surface,
        .target_blocked,
        .target_height_mismatch,
    };
    for (target_statuses) |status| {
        try std.testing.expect(!hasTraceRectColor(trace, .draw_rect, render.locomotionTargetOverlayColor(status)));
    }
}

fn expectTraceHasLocomotionSchematicCue(
    trace: sdl.CanvasTrace,
    room: *const viewer_shell.RoomSnapshot,
    runtime_session: viewer_shell.Session,
    display: viewer_shell.ViewerLocomotionStatusDisplay,
) !void {
    const snapshot = viewer_shell.buildRenderSnapshot(room, runtime_session);
    const schematic = layout.computeDebugLayout(1440, 900, snapshot.grid_width, snapshot.grid_depth, false).schematic;

    switch (display.schematic) {
        .admitted_path => |value| {
            const current_cell_rect = layout.projectGridCellRect(
                schematic,
                snapshot.grid_width,
                snapshot.grid_depth,
                value.current_cell.x,
                value.current_cell.z,
            );
            try std.testing.expect(hasTraceRectOp(
                trace,
                .fill_rect,
                insetRectSafe(current_cell_rect, 2),
                render.locomotionCurrentCellOverlayFillColor(),
            ));
            try std.testing.expect(hasTraceRectOp(
                trace,
                .draw_rect,
                insetRectSafe(current_cell_rect, 1),
                render.locomotionCurrentCellOverlayBorderColor(),
            ));

            for (value.move_options) |move_option| {
                const target_cell = move_option.target_cell orelse continue;
                const target_cell_rect = layout.projectGridCellRect(
                    schematic,
                    snapshot.grid_width,
                    snapshot.grid_depth,
                    target_cell.x,
                    target_cell.z,
                );
                const border_rect = insetRectSafe(target_cell_rect, 1);
                const label = shortDirectionLabel(move_option.direction);
                const label_rect = sdl.Rect{
                    .x = border_rect.x + 1,
                    .y = border_rect.y + 1,
                    .w = draw.textWidth(label, 1),
                    .h = draw.textLineHeight(1),
                };
                const cue_color = render.locomotionTargetOverlayColor(move_option.status);

                try std.testing.expect(hasTraceRectOp(trace, .draw_rect, border_rect, cue_color));
                try std.testing.expect(hasTraceTextOp(trace, label, label_rect, cue_color));
            }
        },
        .none => return error.MissingRenderLocomotionSchematicCue,
    }
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

fn firstComparisonRowRect(rect: sdl.Rect, entry_count: usize) sdl.Rect {
    const summary_height = 18;
    const summary_rect = sdl.Rect{
        .x = rect.x,
        .y = rect.y,
        .w = rect.w,
        .h = @min(summary_height, rect.h),
    };
    const focus_height = std.math.clamp(@divTrunc(rect.h, 3), 88, 132);
    const focus_rect = sdl.Rect{
        .x = rect.x,
        .y = rect.y + summary_rect.h + 8,
        .w = rect.w,
        .h = @min(focus_height, @max(0, rect.h - summary_rect.h - 8)),
    };
    const rows_y = focus_rect.y + focus_rect.h + 10;
    const rows_height = rect.y + rect.h - rows_y;
    const row_gap = 6;
    const total_gap_height = row_gap * @as(i32, @intCast(entry_count -| 1));
    const row_height = std.math.clamp(@divTrunc(rows_height - total_gap_height, @as(i32, @intCast(entry_count))), 28, 42);
    return .{
        .x = rect.x,
        .y = rows_y,
        .w = rect.w,
        .h = row_height,
    };
}

fn findReferencedBrickIndex(snapshot: state.RenderSnapshot) u16 {
    for (snapshot.composition.tiles) |tile| {
        if (tile.top_brick_index != 0) return tile.top_brick_index;
    }
    for (snapshot.fragments.zones) |zone| {
        for (zone.cells) |cell| {
            if (cell.has_non_empty and cell.top_brick_index != 0) return cell.top_brick_index;
        }
    }
    unreachable;
}

fn withoutBrickPreview(
    allocator: std.mem.Allocator,
    previews: []const background_data.BrickPreview,
    brick_index: u16,
) ![]background_data.BrickPreview {
    var count: usize = 0;
    for (previews) |preview| {
        if (preview.brick_index != brick_index) count += 1;
    }
    try std.testing.expect(count != previews.len);

    const trimmed = try allocator.alloc(background_data.BrickPreview, count);
    var cursor: usize = 0;
    for (previews) |preview| {
        if (preview.brick_index == brick_index) continue;
        trimmed[cursor] = preview;
        cursor += 1;
    }
    return trimmed;
}

fn steppedPinnedSelection(catalog: fragment_compare.FragmentComparisonCatalog) fragment_compare.FragmentComparisonSelection {
    var selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    var steps: usize = 0;
    while (steps < catalog.cell_entries.len) : (steps += 1) {
        selection = fragment_compare.stepCellSelection(catalog, selection, 1);
        if (selection.ranked_index) |ranked_index| {
            if (ranked_index >= fragment_compare.max_fragment_comparison_entries) return selection;
        }
    }
    return selection;
}

fn renderZeroFragmentTrace(
    allocator: std.mem.Allocator,
    room: *const viewer_shell.RoomSnapshot,
    runtime_session: viewer_shell.Session,
    status: viewer_shell.ViewerLocomotionStatus,
) !sdl.CanvasTrace {
    const snapshot = viewer_shell.buildRenderSnapshot(room, runtime_session);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);
    const selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    var status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const display = viewer_shell.formatLocomotionStatusDisplay(&status_buffer, status);

    var trace: sdl.CanvasTrace = .{};
    errdefer trace.deinit(allocator);
    var canvas = sdl.Canvas.initForTesting(allocator, 1440, 900, &trace);
    try render.renderDebugView(&canvas, snapshot, catalog, selection, display);
    return trace;
}

test "viewer render path draws the checked-in fragment comparison panel and focus highlight" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.unchecked1110();

    const snapshot = state.buildRenderSnapshot(room);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);
    const selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    const panel = fragment_compare.buildFragmentComparisonPanel(catalog, selection);
    const debug_layout = layout.computeDebugLayout(1440, 900, snapshot.grid_width, snapshot.grid_depth, panel.focus != null);
    const comparison_frame = debug_layout.comparison_frame.?;
    const focus = selection.focus.?;
    const focus_rect = layout.projectGridCellRect(debug_layout.schematic, snapshot.grid_width, snapshot.grid_depth, focus.x, focus.z);
    var room_line_buffer: [48]u8 = undefined;
    const room_line = try std.fmt.bufPrint(
        &room_line_buffer,
        "SCN {d} BKG {d}",
        .{ snapshot.metadata.scene_entry_index, snapshot.metadata.background_entry_index },
    );
    const focus_world_bounds = viewer_state.gridCellWorldBounds(focus.x, focus.z);
    var focus_delta_summary_buffer: [24]u8 = undefined;
    const focus_delta_summary = try fragment_compare.formatDeltaSummary(&focus_delta_summary_buffer, focus.detail);
    var focus_stack_summary_buffer: [16]u8 = undefined;
    const focus_stack_summary = try fragment_compare.formatStackSummary(&focus_stack_summary_buffer, focus.detail);
    var focus_source_line_buffer: [48]u8 = undefined;
    const focus_source_line = try std.fmt.bufPrint(
        &focus_source_line_buffer,
        "CELL {d} {d} FR {d}",
        .{ focus.x, focus.z, focus.fragment_entry_index },
    );
    var focus_zone_line_buffer: [48]u8 = undefined;
    const focus_zone_line = try std.fmt.bufPrint(
        &focus_zone_line_buffer,
        "ZONE {d} NUM {d} {s}",
        .{ focus.zone_index, focus.zone_num, if (focus.initially_on) "ON" else "OFF" },
    );
    var focus_grm_line_buffer: [48]u8 = undefined;
    const focus_grm_line = try std.fmt.bufPrint(
        &focus_grm_line_buffer,
        "GRM {d} SZ {d}x{d}x{d}",
        .{ focus.grm_index, focus.zone_width, focus.zone_height, focus.zone_depth },
    );
    var focus_footprint_line_buffer: [64]u8 = undefined;
    const focus_footprint_line = try std.fmt.bufPrint(
        &focus_footprint_line_buffer,
        "FT {d} NE {d} Y {d}..{d}",
        .{ focus.zone_footprint_cell_count, focus.zone_non_empty_cell_count, focus.zone_y_min, focus.zone_y_max },
    );
    var focus_world_line_buffer: [64]u8 = undefined;
    const focus_world_line = try std.fmt.bufPrint(
        &focus_world_line_buffer,
        "X {d}..{d} Z {d}..{d}",
        .{ focus_world_bounds.min_x, focus_world_bounds.max_x, focus_world_bounds.min_z, focus_world_bounds.max_z },
    );
    var focus_delta_line_buffer: [64]u8 = undefined;
    const focus_delta_line = try std.fmt.bufPrint(
        &focus_delta_line_buffer,
        "DELTA {s} STK {s}",
        .{ focus_delta_summary, focus_stack_summary },
    );

    var trace: sdl.CanvasTrace = .{};
    defer trace.deinit(allocator);
    var canvas = sdl.Canvas.initForTesting(allocator, 1440, 900, &trace);

    try render.renderDebugView(&canvas, snapshot, catalog, selection, .{});

    try std.testing.expect(panel.focus != null);
    try std.testing.expect(debug_layout.comparison != null);
    try std.testing.expect(hasTraceRectOp(trace, .fill_rect, debug_layout.header, .{ .r = 15, .g = 20, .b = 26, .a = 255 }));
    try std.testing.expect(hasTraceRectOp(trace, .fill_rect, debug_layout.footer, .{ .r = 15, .g = 20, .b = 26, .a = 255 }));
    try std.testing.expect(hasTraceRectOp(trace, .fill_rect, comparison_frame, .{ .r = 12, .g = 17, .b = 23, .a = 255 }));
    try std.testing.expect(hasTraceRectOp(trace, .draw_rect, comparison_frame, .{ .r = 66, .g = 90, .b = 103, .a = 255 }));
    try std.testing.expect(hasTraceRectOp(trace, .draw_rect, focus_rect, fragment_compare.fragmentComparisonDeltaColor(focus.delta)));
    try std.testing.expect(hasTraceText(trace, "ROOM"));
    try std.testing.expect(hasTraceText(trace, room_line));
    try std.testing.expect(hasTraceText(trace, "FRAGMENT STATE"));
    try std.testing.expect(hasTraceText(trace, "FOCUS"));
    try std.testing.expect(hasTraceText(trace, focus_source_line));
    try std.testing.expect(hasTraceText(trace, focus_zone_line));
    try std.testing.expect(hasTraceText(trace, focus_grm_line));
    try std.testing.expect(hasTraceText(trace, focus_footprint_line));
    try std.testing.expect(hasTraceText(trace, focus_world_line));
    try std.testing.expect(hasTraceText(trace, focus_delta_line));
    try std.testing.expect(hasTraceText(trace, "OVERLAYS"));
    try std.testing.expect(hasTraceText(trace, "COMPARE ORDER"));
    try std.testing.expect(hasTraceText(trace, "LEFT RIGHT RANK"));
    try std.testing.expect(hasPresent(trace));
}

test "viewer render path exposes a deterministic owning-zone rect for the focused checked-in fragment cell on the unchecked evidence path" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.unchecked1110();

    const snapshot = state.buildRenderSnapshot(room);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);
    const selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    const panel = fragment_compare.buildFragmentComparisonPanel(catalog, selection);
    const debug_layout = layout.computeDebugLayout(1440, 900, snapshot.grid_width, snapshot.grid_depth, panel.focus != null);
    const focus = selection.focus.?;
    const zone = findFocusedFragmentZone(snapshot, focus);
    const focus_rect = layout.projectGridCellRect(debug_layout.schematic, snapshot.grid_width, snapshot.grid_depth, focus.x, focus.z);
    const zone_rect = layout.projectGridAreaRect(
        debug_layout.schematic,
        snapshot.grid_width,
        snapshot.grid_depth,
        zone.origin_x,
        zone.origin_z,
        zone.width,
        zone.depth,
    );

    var trace: sdl.CanvasTrace = .{};
    defer trace.deinit(allocator);
    var canvas = sdl.Canvas.initForTesting(allocator, 1440, 900, &trace);

    try render.renderDebugView(&canvas, snapshot, catalog, selection, .{});

    try std.testing.expect(zone_rect.x <= focus_rect.x);
    try std.testing.expect(zone_rect.y <= focus_rect.y);
    try std.testing.expect(zone_rect.right() >= focus_rect.right());
    try std.testing.expect(zone_rect.bottom() >= focus_rect.bottom());
    try std.testing.expect(hasTraceRectOp(trace, .fill_rect, zone_rect, render.focusedFragmentZoneOverlayFillColor()));
    try std.testing.expect(hasTraceRectOp(trace, .draw_rect, zone_rect, draw.fragmentZoneBorderColor(zone.initially_on)));
}

test "viewer render path keeps the selected cell pinned at the head of the comparison panel" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.unchecked1110();

    const snapshot = state.buildRenderSnapshot(room);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);
    const selection = steppedPinnedSelection(catalog);
    const panel = fragment_compare.buildFragmentComparisonPanel(catalog, selection);
    const comparison = layout.computeDebugLayout(1440, 900, snapshot.grid_width, snapshot.grid_depth, true).comparison.?;
    const first_row = firstComparisonRowRect(comparison, panel.entry_count);
    const focus = selection.focus.?;
    const accent = fragment_compare.fragmentComparisonDeltaColor(focus.delta);
    const focused_row_fill = draw.withAlpha(draw.darkenColor(accent, 128), 88);
    const focused_row_border = draw.withAlpha(draw.lightenColor(accent, 24), 224);

    var trace: sdl.CanvasTrace = .{};
    defer trace.deinit(allocator);
    var canvas = sdl.Canvas.initForTesting(allocator, 1440, 900, &trace);

    try render.renderDebugView(&canvas, snapshot, catalog, selection, .{});

    try std.testing.expect(selection.ranked_index.? >= fragment_compare.max_fragment_comparison_entries);
    try std.testing.expectEqual(focus.x, panel.entries[0].x);
    try std.testing.expectEqual(focus.z, panel.entries[0].z);
    try std.testing.expectEqual(focus.fragment_entry_index, panel.entries[0].fragment_entry_index);
    try std.testing.expect(hasTraceRectOp(trace, .fill_rect, first_row, focused_row_fill));
    try std.testing.expect(hasTraceRectOp(trace, .draw_rect, first_row, focused_row_border));
}

test "viewer render path surfaces runtime-owned locomotion states on the zero-fragment guarded path" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    const raw_runtime_session = viewer_shell.initSession(room);
    const raw_status = try runtime_locomotion.inspectCurrentStatus(room, raw_runtime_session);
    var raw_status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const raw_display = viewer_shell.formatLocomotionStatusDisplay(&raw_status_buffer, raw_status);
    var raw_trace = try renderZeroFragmentTrace(allocator, room, raw_runtime_session, raw_status);
    defer raw_trace.deinit(allocator);

    try std.testing.expect(hasTraceText(raw_trace, "RAW START INVALID"));
    try std.testing.expect(hasTraceText(raw_trace, "CELL 3/7 MAPPED_CELL_EMPTY"));
    try std.testing.expect(hasTraceText(raw_trace, "BOUNDS OUTSIDE_OCCUPIED_BOUNDS"));
    try std.testing.expect(!hasTraceText(raw_trace, "ZONES NONE"));
    try std.testing.expect(hasTraceText(raw_trace, "ENTER SEED HERO"));
    try std.testing.expect(hasTraceText(raw_trace, "ARROWS MOVE HERO"));
    try std.testing.expect(hasTraceText(raw_trace, "RAW START STAYS"));
    try expectNoLocomotionSchematicCue(raw_trace);

    var origin_invalid_runtime_session = viewer_shell.initSession(room);
    const origin_invalid_status = try runtime_locomotion.applyStep(room, &origin_invalid_runtime_session, .south);
    var origin_invalid_status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const origin_invalid_display = viewer_shell.formatLocomotionStatusDisplay(&origin_invalid_status_buffer, origin_invalid_status);
    var origin_invalid_trace = try renderZeroFragmentTrace(allocator, room, origin_invalid_runtime_session, origin_invalid_status);
    defer origin_invalid_trace.deinit(allocator);

    try std.testing.expect(hasTraceText(origin_invalid_trace, "MOVE SOUTH REJECTED"));
    try std.testing.expect(hasTraceText(origin_invalid_trace, "STAY CELL 3/7"));
    try std.testing.expect(hasTraceText(origin_invalid_trace, "REASON TARGET_EMPTY"));
    switch (raw_display.schematic) {
        .none => {},
        else => return error.UnexpectedRenderLocomotionSchematicCue,
    }
    switch (origin_invalid_display.schematic) {
        .none => {},
        else => return error.UnexpectedRenderLocomotionSchematicCue,
    }
    try expectNoLocomotionSchematicCue(origin_invalid_trace);

    var seeded_runtime_session = viewer_shell.initSession(room);
    _ = try viewer_shell.seedSessionToLocomotionFixture(room, &seeded_runtime_session);
    const seeded_status = try runtime_locomotion.inspectCurrentStatus(room, seeded_runtime_session);
    var seeded_status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const seeded_display = viewer_shell.formatLocomotionStatusDisplay(&seeded_status_buffer, seeded_status);
    var seeded_trace = try renderZeroFragmentTrace(allocator, room, seeded_runtime_session, seeded_status);
    defer seeded_trace.deinit(allocator);

    try std.testing.expect(hasTraceText(seeded_trace, "FIXTURE SEEDED VALID"));
    try std.testing.expect(hasTraceText(seeded_trace, "CELL 39/6 STATUS ALLOWED"));
    try expectTraceHasMoveOptionsForPosition(seeded_trace, room, seeded_runtime_session.heroWorldPosition());
    try std.testing.expect(hasTraceText(seeded_trace, "ZONES NONE"));
    try std.testing.expect(hasTraceText(seeded_trace, "ARROWS MOVE FROM HERE"));
    try expectTraceHasLocomotionSchematicCue(seeded_trace, room, seeded_runtime_session, seeded_display);

    var moved_runtime_session = viewer_shell.initSession(room);
    _ = try viewer_shell.seedSessionToLocomotionFixture(room, &moved_runtime_session);
    const moved_status = try runtime_locomotion.applyStep(room, &moved_runtime_session, .south);
    var moved_status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const moved_display = viewer_shell.formatLocomotionStatusDisplay(&moved_status_buffer, moved_status);
    var moved_trace = try renderZeroFragmentTrace(allocator, room, moved_runtime_session, moved_status);
    defer moved_trace.deinit(allocator);

    try std.testing.expect(hasTraceText(moved_trace, "MOVE SOUTH ACCEPTED"));
    try std.testing.expect(hasTraceText(moved_trace, "CELL 39/7 STATUS ALLOWED"));
    try expectTraceHasMoveOptionsForPosition(moved_trace, room, moved_runtime_session.heroWorldPosition());
    try std.testing.expect(hasTraceText(moved_trace, "ZONES NONE"));
    try std.testing.expect(hasTraceText(moved_trace, "HERO POSITION UPDATED"));
    try expectTraceHasLocomotionSchematicCue(moved_trace, room, moved_runtime_session, moved_display);

    var rejected_runtime_session = viewer_shell.initSession(room);
    _ = try viewer_shell.seedSessionToLocomotionFixture(room, &rejected_runtime_session);
    const rejected_status = try runtime_locomotion.applyStep(room, &rejected_runtime_session, .west);
    var rejected_status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const rejected_display = viewer_shell.formatLocomotionStatusDisplay(&rejected_status_buffer, rejected_status);
    var rejected_trace = try renderZeroFragmentTrace(allocator, room, rejected_runtime_session, rejected_status);
    defer rejected_trace.deinit(allocator);

    try std.testing.expect(hasTraceText(rejected_trace, "MOVE WEST REJECTED"));
    try std.testing.expect(hasTraceText(rejected_trace, "STAY CELL 39/6"));
    try expectTraceHasMoveOptionsForPosition(rejected_trace, room, rejected_runtime_session.heroWorldPosition());
    try std.testing.expect(hasTraceText(rejected_trace, "ZONES NONE"));
    try std.testing.expect(hasTraceText(rejected_trace, "REASON TARGET_EMPTY"));
    try expectTraceHasLocomotionSchematicCue(rejected_trace, room, rejected_runtime_session, rejected_display);
}

test "viewer render path keeps the zero-fragment room out of the comparison panel" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    const snapshot = state.buildRenderSnapshot(room);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);
    const selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    const comparison_frame_if_present = layout.computeDebugLayout(1440, 900, snapshot.grid_width, snapshot.grid_depth, true).comparison_frame.?;
    const runtime_session = viewer_shell.initSession(room);
    const locomotion_status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);
    var status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const display = viewer_shell.formatLocomotionStatusDisplay(&status_buffer, locomotion_status);

    var trace: sdl.CanvasTrace = .{};
    defer trace.deinit(allocator);
    var canvas = sdl.Canvas.initForTesting(allocator, 1440, 900, &trace);

    try render.renderDebugView(&canvas, snapshot, catalog, selection, display);

    try std.testing.expect(selection.focus == null);
    try std.testing.expectEqual(@as(?sdl.Rect, null), layout.computeDebugLayout(1440, 900, snapshot.grid_width, snapshot.grid_depth, false).comparison_frame);
    try std.testing.expect(!hasTraceRectOp(trace, .fill_rect, comparison_frame_if_present, .{ .r = 12, .g = 17, .b = 23, .a = 255 }));
    try std.testing.expect(!hasTraceRectOp(trace, .draw_rect, comparison_frame_if_present, .{ .r = 66, .g = 90, .b = 103, .a = 255 }));
    try std.testing.expect(!hasTraceRectColor(trace, .fill_rect, render.focusedFragmentZoneOverlayFillColor()));
    try std.testing.expect(hasTraceText(trace, "RAW START INVALID"));
    try std.testing.expect(hasTraceText(trace, "CELL 3/7 MAPPED_CELL_EMPTY"));
    try std.testing.expect(hasPresent(trace));
}

test "viewer render path fails fast when a required brick preview is missing" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.unchecked1110();

    const snapshot = state.buildRenderSnapshot(room);
    const missing_brick_index = findReferencedBrickIndex(snapshot);
    const trimmed_previews = try withoutBrickPreview(allocator, snapshot.brick_previews, missing_brick_index);
    defer allocator.free(trimmed_previews);

    var missing_snapshot = snapshot;
    missing_snapshot.brick_previews = trimmed_previews;

    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, missing_snapshot);
    defer catalog.deinit(allocator);
    const selection = fragment_compare.initialFragmentComparisonSelection(catalog);

    var trace: sdl.CanvasTrace = .{};
    defer trace.deinit(allocator);
    var canvas = sdl.Canvas.initForTesting(allocator, 1440, 900, &trace);

    try std.testing.expectError(error.ViewerBrickPreviewMissing, render.renderDebugView(&canvas, missing_snapshot, catalog, selection, .{}));
}
