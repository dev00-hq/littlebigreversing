const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const background_data = @import("../../game_data/background.zig");
const state = @import("state.zig");
const layout = @import("layout.zig");
const draw = @import("draw.zig");

pub const max_fragment_comparison_entries = 4;

pub const FragmentBrickDelta = enum {
    no_base,
    same,
    changed,
};

pub const FragmentComparisonDetail = struct {
    base_present: bool,
    brick_matches: bool,
    floor_type_matches: bool,
    shape_matches: bool,
    base_stack_depth: u8,
    fragment_stack_depth: u8,

    pub fn stackDepthDelta(self: FragmentComparisonDetail) i16 {
        return @as(i16, self.fragment_stack_depth) - @as(i16, self.base_stack_depth);
    }

    pub fn changedAspectCount(self: FragmentComparisonDetail) u8 {
        if (!self.base_present) return 0;

        var count: u8 = 0;
        if (!self.brick_matches) count += 1;
        if (!self.floor_type_matches) count += 1;
        if (!self.shape_matches) count += 1;
        if (self.base_stack_depth != self.fragment_stack_depth) count += 1;
        return count;
    }
};

pub const FragmentComparisonEntry = struct {
    zone_index: usize,
    fragment_entry_index: usize,
    x: usize,
    z: usize,
    delta: FragmentBrickDelta,
    base_tile: ?state.CompositionTileSnapshot,
    fragment_cell: state.FragmentZoneCellSnapshot,
    detail: FragmentComparisonDetail,
};

pub const FragmentComparisonPanel = struct {
    focus: ?FragmentComparisonEntry,
    entries: [max_fragment_comparison_entries]FragmentComparisonEntry,
    entry_count: usize,
    changed_count: usize,
    same_count: usize,
    no_base_count: usize,
};

pub fn buildFragmentComparisonPanel(snapshot: state.RenderSnapshot) FragmentComparisonPanel {
    var panel = FragmentComparisonPanel{
        .focus = null,
        .entries = undefined,
        .entry_count = 0,
        .changed_count = 0,
        .same_count = 0,
        .no_base_count = 0,
    };

    for (snapshot.fragments.zones) |zone| {
        for (zone.cells) |cell| {
            if (!cell.has_non_empty) continue;

            const entry = makeFragmentComparisonEntry(snapshot, zone, cell);
            switch (entry.delta) {
                .changed => panel.changed_count += 1,
                .same => panel.same_count += 1,
                .no_base => panel.no_base_count += 1,
            }
            insertPanelEntry(&panel, entry);
        }
    }

    if (panel.entry_count > 0) panel.focus = panel.entries[0];
    return panel;
}

fn insertPanelEntry(panel: *FragmentComparisonPanel, entry: FragmentComparisonEntry) void {
    if (panel.entry_count == 0) {
        panel.entries[0] = entry;
        panel.entry_count = 1;
        return;
    }

    var insert_index = panel.entry_count;
    var index: usize = 0;
    while (index < panel.entry_count) : (index += 1) {
        if (isPreferredComparisonEntry(entry, panel.entries[index])) {
            insert_index = index;
            break;
        }
    }

    if (insert_index == panel.entry_count) {
        if (panel.entry_count < max_fragment_comparison_entries) {
            panel.entries[panel.entry_count] = entry;
            panel.entry_count += 1;
        }
        return;
    }

    const new_count = @min(panel.entry_count + 1, max_fragment_comparison_entries);
    var shift_index = new_count - 1;
    while (shift_index > insert_index) : (shift_index -= 1) {
        panel.entries[shift_index] = panel.entries[shift_index - 1];
    }
    panel.entries[insert_index] = entry;
    panel.entry_count = new_count;
}

fn isPreferredComparisonEntry(candidate: FragmentComparisonEntry, existing: FragmentComparisonEntry) bool {
    const candidate_priority = fragmentComparisonPriority(candidate.delta);
    const existing_priority = fragmentComparisonPriority(existing.delta);
    if (candidate_priority != existing_priority) return candidate_priority < existing_priority;

    const candidate_changed = candidate.detail.changedAspectCount();
    const existing_changed = existing.detail.changedAspectCount();
    if (candidate_changed != existing_changed) return candidate_changed > existing_changed;

    const candidate_stack_delta = @abs(candidate.detail.stackDepthDelta());
    const existing_stack_delta = @abs(existing.detail.stackDepthDelta());
    if (candidate_stack_delta != existing_stack_delta) return candidate_stack_delta > existing_stack_delta;

    if (candidate.zone_index != existing.zone_index) return candidate.zone_index < existing.zone_index;
    if (candidate.z != existing.z) return candidate.z < existing.z;
    if (candidate.x != existing.x) return candidate.x < existing.x;
    return candidate.fragment_entry_index < existing.fragment_entry_index;
}

fn makeFragmentComparisonEntry(
    snapshot: state.RenderSnapshot,
    zone: state.FragmentZoneSnapshot,
    cell: state.FragmentZoneCellSnapshot,
) FragmentComparisonEntry {
    const base_tile = findCompositionTile(snapshot.composition.tiles, cell.x, cell.z);
    const detail = buildFragmentComparisonDetail(base_tile, cell);
    return .{
        .zone_index = zone.zone_index,
        .fragment_entry_index = zone.fragment_entry_index,
        .x = cell.x,
        .z = cell.z,
        .delta = if (!detail.base_present)
            .no_base
        else if (detail.brick_matches)
            .same
        else
            .changed,
        .base_tile = base_tile,
        .fragment_cell = cell,
        .detail = detail,
    };
}

pub fn buildFragmentComparisonDetail(
    base_tile: ?state.CompositionTileSnapshot,
    fragment_cell: state.FragmentZoneCellSnapshot,
) FragmentComparisonDetail {
    return if (base_tile) |tile|
        .{
            .base_present = true,
            .brick_matches = tile.top_brick_index == fragment_cell.top_brick_index,
            .floor_type_matches = tile.top_floor_type == fragment_cell.top_floor_type,
            .shape_matches = tile.top_shape == fragment_cell.top_shape,
            .base_stack_depth = tile.stack_depth,
            .fragment_stack_depth = fragment_cell.stack_depth,
        }
    else
        .{
            .base_present = false,
            .brick_matches = false,
            .floor_type_matches = false,
            .shape_matches = false,
            .base_stack_depth = 0,
            .fragment_stack_depth = fragment_cell.stack_depth,
        };
}

fn fragmentComparisonPriority(delta: FragmentBrickDelta) u8 {
    return switch (delta) {
        .changed => 0,
        .same => 1,
        .no_base => 2,
    };
}

pub fn fragmentComparisonDeltaColor(delta: FragmentBrickDelta) sdl.Color {
    return switch (delta) {
        .changed => .{ .r = 255, .g = 148, .b = 118, .a = 255 },
        .same => .{ .r = 112, .g = 216, .b = 188, .a = 255 },
        .no_base => .{ .r = 176, .g = 186, .b = 198, .a = 255 },
    };
}

pub fn fragmentBrickDelta(snapshot: state.RenderSnapshot, cell: state.FragmentZoneCellSnapshot) FragmentBrickDelta {
    const base_brick_index = compositionBrickIndexAt(snapshot, cell.x, cell.z) orelse return .no_base;
    return if (base_brick_index == cell.top_brick_index) .same else .changed;
}

fn compositionBrickIndexAt(snapshot: state.RenderSnapshot, x: usize, z: usize) ?u16 {
    const tile = findCompositionTile(snapshot.composition.tiles, x, z) orelse return null;
    return tile.top_brick_index;
}

pub fn drawFragmentFocusHighlight(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    snapshot: state.RenderSnapshot,
    focus: FragmentComparisonEntry,
) !void {
    const cell_rect = layout.projectGridCellRect(rect, snapshot.grid_width, snapshot.grid_depth, focus.x, focus.z);
    const accent = fragmentComparisonDeltaColor(focus.delta);
    try canvas.drawRect(cell_rect, accent);

    const inner = cell_rect.inset(1);
    if (inner.w > 1 and inner.h > 1) {
        try canvas.drawRect(inner, draw.withAlpha(draw.lightenColor(accent, 28), 236));
    }

    const marker_size = std.math.clamp(@divTrunc(@min(cell_rect.w, cell_rect.h), 2), 2, 6);
    try draw.drawMarker(canvas, .{
        .x = cell_rect.x + @divTrunc(cell_rect.w, 2),
        .y = cell_rect.y + @divTrunc(cell_rect.h, 2),
    }, marker_size, draw.withAlpha(draw.lightenColor(accent, 42), 220));
}

pub fn drawFragmentComparisonPanel(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    snapshot: state.RenderSnapshot,
    panel: FragmentComparisonPanel,
) !void {
    if (panel.focus == null) return;

    try canvas.fillRect(rect, .{ .r = 9, .g = 13, .b = 18, .a = 255 });
    try canvas.drawRect(rect, .{ .r = 82, .g = 104, .b = 118, .a = 255 });

    const summary_height = 18;
    const summary_rect = sdl.Rect{
        .x = rect.x,
        .y = rect.y,
        .w = rect.w,
        .h = @min(summary_height, rect.h),
    };
    try drawFragmentComparisonSummary(canvas, summary_rect, panel);

    const focus_height = std.math.clamp(@divTrunc(rect.h, 3), 88, 132);
    const focus_rect = sdl.Rect{
        .x = rect.x,
        .y = rect.y + summary_rect.h + 8,
        .w = rect.w,
        .h = @min(focus_height, @max(0, rect.h - summary_rect.h - 8)),
    };
    try drawFragmentComparisonFocus(canvas, focus_rect, snapshot, panel.focus.?);

    if (panel.entry_count == 0) return;

    const rows_y = focus_rect.y + focus_rect.h + 10;
    const rows_height = rect.y + rect.h - rows_y;
    if (rows_height <= 0) return;

    const row_gap = 6;
    const total_gap_height = row_gap * @as(i32, @intCast(panel.entry_count -| 1));
    const row_height = std.math.clamp(@divTrunc(rows_height - total_gap_height, @as(i32, @intCast(panel.entry_count))), 28, 42);
    var row_y = rows_y;
    for (panel.entries[0..panel.entry_count], 0..) |entry, index| {
        const row_rect = sdl.Rect{
            .x = rect.x,
            .y = row_y,
            .w = rect.w,
            .h = row_height,
        };
        try drawFragmentComparisonEntryRow(canvas, row_rect, snapshot, entry, index == 0, panel.focus.?);
        row_y += row_height + row_gap;
    }
}

fn drawFragmentComparisonSummary(canvas: *sdl.Canvas, rect: sdl.Rect, panel: FragmentComparisonPanel) !void {
    const total = panel.changed_count + panel.same_count + panel.no_base_count;
    try canvas.fillRect(rect, .{ .r = 18, .g = 24, .b = 30, .a = 255 });
    if (total == 0) {
        try canvas.drawRect(rect, .{ .r = 74, .g = 94, .b = 108, .a = 255 });
        return;
    }

    var cursor_x = rect.x;
    const segments = [_]struct { count: usize, color: sdl.Color }{
        .{ .count = panel.changed_count, .color = fragmentComparisonDeltaColor(.changed) },
        .{ .count = panel.same_count, .color = fragmentComparisonDeltaColor(.same) },
        .{ .count = panel.no_base_count, .color = fragmentComparisonDeltaColor(.no_base) },
    };

    for (segments, 0..) |segment, index| {
        if (segment.count == 0) continue;

        const is_last_segment = index == segments.len - 1 or cursor_x >= rect.x + rect.w - 1;
        const segment_width = if (is_last_segment)
            rect.x + rect.w - cursor_x
        else
            @max(1, @as(i32, @intFromFloat(@round(
                @as(f64, @floatFromInt(rect.w)) *
                    (@as(f64, @floatFromInt(segment.count)) / @as(f64, @floatFromInt(total))),
            ))));
        if (segment_width <= 0) continue;

        const segment_rect = sdl.Rect{
            .x = cursor_x,
            .y = rect.y,
            .w = @min(segment_width, rect.x + rect.w - cursor_x),
            .h = rect.h,
        };
        try canvas.fillRect(segment_rect, draw.withAlpha(segment.color, 216));
        cursor_x += segment_rect.w;
        if (cursor_x >= rect.x + rect.w) break;
    }

    try canvas.drawRect(rect, .{ .r = 74, .g = 94, .b = 108, .a = 255 });
}

fn drawFragmentComparisonFocus(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    snapshot: state.RenderSnapshot,
    focus: FragmentComparisonEntry,
) !void {
    const accent = fragmentComparisonDeltaColor(focus.delta);
    try canvas.fillRect(rect, draw.withAlpha(draw.darkenColor(accent, 132), 56));
    try canvas.drawRect(rect, draw.withAlpha(draw.lightenColor(accent, 20), 232));

    const content = rect.inset(8);
    const locator_height = std.math.clamp(@divTrunc(content.h, 5), 16, 22);
    const detail_height = std.math.clamp(@divTrunc(content.h, 4), 22, 34);
    const card_gap_y = 6;
    const card_area = sdl.Rect{
        .x = content.x,
        .y = content.y,
        .w = content.w,
        .h = @max(0, content.h - locator_height - detail_height - (card_gap_y * 2)),
    };
    const card_gap = 10;
    const card_width = @max(24, @divTrunc(card_area.w - card_gap, 2));
    const card_height = @max(24, @min(card_area.h, card_width));
    const card_y = card_area.y + @divTrunc(@max(0, card_area.h - card_height), 2);
    const base_card = sdl.Rect{ .x = card_area.x, .y = card_y, .w = card_width, .h = card_height };
    const fragment_card = sdl.Rect{
        .x = card_area.x + card_width + card_gap,
        .y = card_y,
        .w = card_width,
        .h = card_height,
    };

    try drawFragmentComparisonCard(canvas, base_card, snapshot.brick_previews, accent, focus.base_tile, null);
    try drawFragmentComparisonCard(canvas, fragment_card, snapshot.brick_previews, accent, null, focus.fragment_cell);

    const detail_rect = sdl.Rect{
        .x = content.x,
        .y = card_area.y + card_area.h + card_gap_y,
        .w = content.w,
        .h = detail_height,
    };
    try drawFragmentComparisonDetailStrip(canvas, detail_rect, focus, accent);

    const locator = sdl.Rect{
        .x = content.x,
        .y = detail_rect.y + detail_rect.h + card_gap_y,
        .w = content.w,
        .h = locator_height,
    };
    try drawFragmentComparisonLocator(canvas, locator, snapshot, focus, accent);
}

fn drawFragmentComparisonEntryRow(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    snapshot: state.RenderSnapshot,
    entry: FragmentComparisonEntry,
    is_first: bool,
    focus: FragmentComparisonEntry,
) !void {
    const accent = fragmentComparisonDeltaColor(entry.delta);
    const row_fill = if (entry.x == focus.x and entry.z == focus.z)
        draw.withAlpha(draw.darkenColor(accent, 128), 88)
    else
        draw.withAlpha(draw.darkenColor(accent, 148), 48);
    try canvas.fillRect(rect, row_fill);
    try canvas.drawRect(rect, if (is_first)
        draw.withAlpha(draw.lightenColor(accent, 24), 224)
    else
        draw.withAlpha(draw.lightenColor(accent, 8), 180));

    const accent_bar = sdl.Rect{ .x = rect.x, .y = rect.y, .w = 4, .h = rect.h };
    try canvas.fillRect(accent_bar, draw.withAlpha(accent, 228));

    const locator_side = std.math.clamp(rect.h - 10, 16, 24);
    const locator = sdl.Rect{
        .x = rect.x + 10,
        .y = rect.y + @divTrunc(rect.h - locator_side, 2),
        .w = locator_side,
        .h = locator_side,
    };
    try drawFragmentComparisonLocator(canvas, locator, snapshot, entry, accent);

    const card_gap = 6;
    const card_side = std.math.clamp(rect.h - 10, 18, 30);
    const base_card = sdl.Rect{
        .x = locator.x + locator.w + 10,
        .y = rect.y + @divTrunc(rect.h - card_side, 2),
        .w = card_side,
        .h = card_side,
    };
    const fragment_card = sdl.Rect{
        .x = base_card.x + base_card.w + card_gap,
        .y = base_card.y,
        .w = card_side,
        .h = card_side,
    };
    try drawFragmentComparisonCard(canvas, base_card, snapshot.brick_previews, accent, entry.base_tile, null);
    try drawFragmentComparisonCard(canvas, fragment_card, snapshot.brick_previews, accent, null, entry.fragment_cell);

    const detail_width = std.math.clamp(@divTrunc(rect.w, 5), 28, 48);
    const detail_rect = sdl.Rect{
        .x = rect.right() - detail_width - 8,
        .y = rect.y + 5,
        .w = detail_width,
        .h = rect.h - 10,
    };
    try drawFragmentComparisonDetailStrip(canvas, detail_rect, entry, accent);
}

fn drawFragmentComparisonCard(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    previews: []const background_data.BrickPreview,
    accent: sdl.Color,
    tile: ?state.CompositionTileSnapshot,
    cell: ?state.FragmentZoneCellSnapshot,
) !void {
    if (rect.w <= 0 or rect.h <= 0) return;

    const base_color = if (tile) |composition_tile|
        draw.compositionTileColor(composition_tile)
    else if (cell) |fragment_cell|
        draw.fragmentCellColor(fragment_cell)
    else
        sdl.Color{ .r = 28, .g = 34, .b = 42, .a = 255 };

    try canvas.fillRect(rect, draw.withAlpha(draw.darkenColor(base_color, 54), 200));
    try canvas.drawRect(rect, draw.withAlpha(draw.lightenColor(accent, 10), 220));

    const content = rect.inset(3);
    const maybe_brick_index = if (tile) |composition_tile|
        if (composition_tile.top_brick_index == 0) null else composition_tile.top_brick_index
    else if (cell) |fragment_cell|
        if (fragment_cell.top_brick_index == 0) null else fragment_cell.top_brick_index
    else
        null;

    if (maybe_brick_index) |brick_index| {
        if (!try draw.drawBrickPreviewSurface(canvas, content, previews, brick_index)) {
            try canvas.fillRect(content, draw.withAlpha(base_color, 164));
        }
        try draw.drawBrickProbe(canvas, content.inset(1), brick_index, draw.withAlpha(draw.lightenColor(base_color, 42), 168));
    } else {
        try canvas.fillRect(content, .{ .r = 12, .g = 16, .b = 21, .a = 255 });
        try canvas.drawLine(content.x, content.y, content.right(), content.bottom(), draw.withAlpha(accent, 224));
        try canvas.drawLine(content.right(), content.y, content.x, content.bottom(), draw.withAlpha(accent, 224));
    }

    if (tile) |composition_tile| {
        try draw.drawSurfaceMarker(canvas, content, composition_tile, draw.withAlpha(draw.lightenColor(base_color, 62), 232));
    } else if (cell) |fragment_cell| {
        try draw.drawFragmentCellMarker(canvas, content, fragment_cell, draw.withAlpha(draw.lightenColor(base_color, 72), 224));
    }
}

fn drawFragmentComparisonLocator(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    snapshot: state.RenderSnapshot,
    entry: FragmentComparisonEntry,
    accent: sdl.Color,
) !void {
    if (rect.w <= 0 or rect.h <= 0) return;

    try canvas.fillRect(rect, .{ .r = 12, .g = 16, .b = 21, .a = 255 });
    try canvas.drawRect(rect, draw.withAlpha(draw.lightenColor(accent, 10), 204));

    const vertical_mid = rect.x + @divTrunc(rect.w, 2);
    const horizontal_mid = rect.y + @divTrunc(rect.h, 2);
    try canvas.drawLine(vertical_mid, rect.y, vertical_mid, rect.bottom(), draw.withAlpha(accent, 124));
    try canvas.drawLine(rect.x, horizontal_mid, rect.right(), horizontal_mid, draw.withAlpha(accent, 124));

    const marker_padding = 2;
    const marker_left = layout.interpolateAxis(rect.x + marker_padding, rect.right() - marker_padding, entry.x, snapshot.grid_width -| 1);
    const marker_top = layout.interpolateAxis(rect.y + marker_padding, rect.bottom() - marker_padding, entry.z, snapshot.grid_depth -| 1);
    const marker = sdl.Rect{ .x = marker_left - 1, .y = marker_top - 1, .w = 3, .h = 3 };
    try canvas.fillRect(marker, draw.withAlpha(draw.lightenColor(accent, 32), 236));
}

fn drawFragmentComparisonDetailStrip(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    entry: FragmentComparisonEntry,
    accent: sdl.Color,
) !void {
    if (rect.w <= 0 or rect.h <= 0) return;

    try canvas.fillRect(rect, .{ .r = 11, .g = 15, .b = 20, .a = 255 });
    try canvas.drawRect(rect, draw.withAlpha(draw.lightenColor(accent, 8), 196));

    const slot_gap = 4;
    const slot_count: i32 = 4;
    const slot_width = @max(8, @divTrunc(rect.w - (slot_gap * (slot_count - 1)), slot_count));
    var slot_x = rect.x;
    var slot_index: i32 = 0;
    while (slot_index < slot_count) : (slot_index += 1) {
        const slot = sdl.Rect{
            .x = slot_x,
            .y = rect.y,
            .w = if (slot_index == slot_count - 1) rect.right() - slot_x else slot_width,
            .h = rect.h,
        };
        switch (slot_index) {
            0 => try drawAspectMatchSlot(canvas, slot, accent, entry.detail.base_present, entry.detail.brick_matches, entry.base_tile != null, entry.fragment_cell.has_non_empty),
            1 => try drawAspectMatchSlot(canvas, slot, accent, entry.detail.base_present, entry.detail.floor_type_matches, entry.base_tile != null, entry.fragment_cell.has_non_empty),
            2 => try drawAspectMatchSlot(canvas, slot, accent, entry.detail.base_present, entry.detail.shape_matches, entry.base_tile != null, entry.fragment_cell.has_non_empty),
            else => try drawStackDepthSlot(canvas, slot, entry.detail, accent),
        }
        slot_x += slot.w + slot_gap;
    }
}

fn drawAspectMatchSlot(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    accent: sdl.Color,
    base_present: bool,
    matches: bool,
    show_base: bool,
    show_fragment: bool,
) !void {
    if (rect.w <= 0 or rect.h <= 0) return;

    const border = if (!base_present)
        sdl.Color{ .r = 176, .g = 186, .b = 198, .a = 224 }
    else if (matches)
        fragmentComparisonDeltaColor(.same)
    else
        draw.lightenColor(accent, 8);
    try canvas.fillRect(rect, draw.withAlpha(draw.darkenColor(border, 146), 74));
    try canvas.drawRect(rect, border);

    const content = rect.inset(3);
    if (content.w <= 0 or content.h <= 0) return;

    if (!base_present) {
        try canvas.drawLine(content.x, content.y, content.right(), content.bottom(), draw.withAlpha(border, 220));
        try canvas.drawLine(content.right(), content.y, content.x, content.bottom(), draw.withAlpha(border, 220));
        return;
    }

    const lane_gap = 2;
    const lane_height = @max(2, @divTrunc(content.h - lane_gap, 2));
    const top_lane = sdl.Rect{ .x = content.x, .y = content.y, .w = content.w, .h = lane_height };
    const bottom_lane = sdl.Rect{
        .x = content.x,
        .y = top_lane.y + top_lane.h + lane_gap,
        .w = content.w,
        .h = content.bottom() - (top_lane.y + top_lane.h + lane_gap),
    };

    if (show_base) {
        try canvas.fillRect(top_lane, draw.withAlpha(draw.lightenColor(border, 10), 190));
    }
    if (show_fragment and bottom_lane.h > 0) {
        try canvas.fillRect(bottom_lane, draw.withAlpha(border, if (matches) 170 else 222));
    }

    if (!matches) {
        const marker = content.inset(@max(1, @divTrunc(@min(content.w, content.h), 4)));
        if (marker.w > 0 and marker.h > 0) {
            try canvas.drawLine(marker.x, marker.y, marker.right(), marker.bottom(), draw.withAlpha(accent, 232));
        }
    }
}

fn drawStackDepthSlot(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    detail: FragmentComparisonDetail,
    accent: sdl.Color,
) !void {
    if (rect.w <= 0 or rect.h <= 0) return;

    const border = if (!detail.base_present)
        fragmentComparisonDeltaColor(.no_base)
    else if (detail.base_stack_depth == detail.fragment_stack_depth)
        fragmentComparisonDeltaColor(.same)
    else
        accent;
    try canvas.fillRect(rect, draw.withAlpha(draw.darkenColor(border, 146), 74));
    try canvas.drawRect(rect, border);

    const content = rect.inset(3);
    if (content.w <= 0 or content.h <= 0) return;
    if (!detail.base_present) {
        try canvas.drawLine(content.x, content.y, content.right(), content.bottom(), draw.withAlpha(border, 220));
        try canvas.drawLine(content.right(), content.y, content.x, content.bottom(), draw.withAlpha(border, 220));
        return;
    }

    const bar_gap = 3;
    const bar_width = @max(2, @divTrunc(content.w - bar_gap, 2));
    const max_depth = @max(@as(u8, 1), @max(detail.base_stack_depth, detail.fragment_stack_depth));
    const base_height = @max(1, @as(i32, @intCast(@divTrunc(content.h * detail.base_stack_depth, max_depth))));
    const fragment_height = @max(1, @as(i32, @intCast(@divTrunc(content.h * detail.fragment_stack_depth, max_depth))));
    const base_bar = sdl.Rect{
        .x = content.x,
        .y = content.bottom() - base_height,
        .w = bar_width,
        .h = base_height,
    };
    const fragment_bar = sdl.Rect{
        .x = content.x + bar_width + bar_gap,
        .y = content.bottom() - fragment_height,
        .w = content.right() - (content.x + bar_width + bar_gap),
        .h = fragment_height,
    };

    if (base_bar.w > 0 and base_bar.h > 0) {
        try canvas.fillRect(base_bar, draw.withAlpha(fragmentComparisonDeltaColor(.same), 184));
    }
    if (fragment_bar.w > 0 and fragment_bar.h > 0) {
        try canvas.fillRect(fragment_bar, draw.withAlpha(border, if (detail.base_stack_depth == detail.fragment_stack_depth) 184 else 228));
    }
}

pub fn findCompositionTile(tiles: []const state.CompositionTileSnapshot, x: usize, z: usize) ?state.CompositionTileSnapshot {
    for (tiles) |tile| {
        if (tile.x == x and tile.z == z) return tile;
    }
    return null;
}
