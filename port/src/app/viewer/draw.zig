const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const background_data = @import("../../game_data/background.zig");
const scene_data = @import("../../game_data/scene.zig");
const projection = @import("../../runtime/room_projection.zig");
const state = @import("../../runtime/room_state.zig");
const layout = @import("layout.zig");

pub const TileRelief = struct {
    top_surface: sdl.Rect,
    right_wall: sdl.Rect,
    bottom_wall: sdl.Rect,
    inset_depth: i32,
};

const ContourEdge = enum {
    north,
    west,
};

const Facing = enum {
    top,
    bottom,
    left,
    right,
};

const glyph_width = 5;
const glyph_height = 7;
const glyph_spacing = 1;

pub fn computeTileRelief(tile_rect: sdl.Rect, total_height: u8, max_total_height: u8) TileRelief {
    const max_inset = @max(0, @min(tile_rect.w - 1, tile_rect.h - 1));
    const capped_max_height = @max(@as(i32, max_total_height), 1);
    const available_depth = @min(max_inset, 5);
    const inset_depth = if (available_depth == 0)
        0
    else
        std.math.clamp(
            1 + @divTrunc((@as(i32, total_height) - 1) * available_depth, capped_max_height),
            1,
            available_depth,
        );
    const top_surface = sdl.Rect{
        .x = tile_rect.x,
        .y = tile_rect.y,
        .w = @max(1, tile_rect.w - inset_depth),
        .h = @max(1, tile_rect.h - inset_depth),
    };

    return .{
        .top_surface = top_surface,
        .right_wall = .{
            .x = top_surface.x + top_surface.w,
            .y = tile_rect.y,
            .w = tile_rect.w - top_surface.w,
            .h = top_surface.h,
        },
        .bottom_wall = .{
            .x = tile_rect.x,
            .y = top_surface.y + top_surface.h,
            .w = tile_rect.w,
            .h = tile_rect.h - top_surface.h,
        },
        .inset_depth = inset_depth,
    };
}

pub fn drawBrickPreviewSurface(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    previews: []const background_data.BrickPreview,
    brick_index: u16,
) !void {
    if (rect.w <= 0 or rect.h <= 0) return;

    const preview = try requireBrickPreview(previews, brick_index);
    try canvas.fillRect(rect, .{ .r = 6, .g = 10, .b = 14, .a = 212 });
    try drawBrickPreviewPixels(canvas, rect.inset(1), preview);
}

fn drawBrickPreviewPixels(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    preview: background_data.BrickPreview,
) !void {
    if (rect.w <= 0 or rect.h <= 0) return;

    for (0..background_data.brick_preview_swatch_side) |sample_y| {
        const top = layout.interpolateAxis(rect.y, rect.bottom(), sample_y, background_data.brick_preview_swatch_side);
        const bottom = layout.interpolateAxis(rect.y, rect.bottom(), sample_y + 1, background_data.brick_preview_swatch_side);
        for (0..background_data.brick_preview_swatch_side) |sample_x| {
            const left = layout.interpolateAxis(rect.x, rect.right(), sample_x, background_data.brick_preview_swatch_side);
            const right = layout.interpolateAxis(rect.x, rect.right(), sample_x + 1, background_data.brick_preview_swatch_side);
            const pixel = preview.swatch[(sample_y * background_data.brick_preview_swatch_side) + sample_x];
            if (pixel.a == 0) continue;

            const sample_rect = sdl.Rect{
                .x = @min(left, right),
                .y = @min(top, bottom),
                .w = @max(1, @max(left, right) - @min(left, right)),
                .h = @max(1, @max(top, bottom) - @min(top, bottom)),
            };
            try canvas.fillRect(sample_rect, .{
                .r = pixel.r,
                .g = pixel.g,
                .b = pixel.b,
                .a = pixel.a,
            });
        }
    }
}

pub fn textWidth(text: []const u8, scale: i32) i32 {
    const resolved_scale = @max(scale, 1);
    if (text.len == 0) return 0;
    return (@as(i32, @intCast(text.len)) * ((glyph_width + glyph_spacing) * resolved_scale)) - (glyph_spacing * resolved_scale);
}

pub fn textLineHeight(scale: i32) i32 {
    return glyph_height * @max(scale, 1);
}

pub fn drawText(
    canvas: *sdl.Canvas,
    x: i32,
    y: i32,
    scale: i32,
    color: sdl.Color,
    text: []const u8,
) !sdl.Rect {
    const resolved_scale = @max(scale, 1);
    const bounds = sdl.Rect{
        .x = x,
        .y = y,
        .w = textWidth(text, resolved_scale),
        .h = textLineHeight(resolved_scale),
    };
    try canvas.traceText(bounds, color, resolved_scale, text);

    var cursor_x = x;
    for (text) |raw_char| {
        const glyph = glyphRows(raw_char);
        var row: usize = 0;
        while (row < glyph_height) : (row += 1) {
            var column: usize = 0;
            while (column < glyph_width) : (column += 1) {
                if ((glyph[row] & (@as(u8, 1) << @intCast((glyph_width - 1) - column))) == 0) continue;
                try canvas.fillRect(.{
                    .x = cursor_x + (@as(i32, @intCast(column)) * resolved_scale),
                    .y = y + (@as(i32, @intCast(row)) * resolved_scale),
                    .w = resolved_scale,
                    .h = resolved_scale,
                }, color);
            }
        }
        cursor_x += (glyph_width + glyph_spacing) * resolved_scale;
    }

    return bounds;
}

pub fn compositionTileColor(tile: state.CompositionTileSnapshot) sdl.Color {
    const height_boost: u8 = @intCast(@min(@as(usize, 72), (@as(usize, tile.total_height) * 2) + @as(usize, tile.stack_depth)));
    const depth_boost: u8 = @intCast(@min(@as(usize, 56), @as(usize, tile.stack_depth) * 3));
    return switch (tile.top_floor_type) {
        1, 0x0F => .{ .r = 24, .g = saturatingAdd(92, depth_boost / 3), .b = saturatingAdd(140, height_boost), .a = 188 },
        0x09, 0x0D => .{ .r = saturatingAdd(166, height_boost), .g = saturatingAdd(82, depth_boost / 3), .b = 44, .a = 196 },
        0x0B, 0x0E => .{ .r = saturatingAdd(78, depth_boost / 2), .g = saturatingAdd(140, height_boost), .b = saturatingAdd(84, depth_boost / 3), .a = 192 },
        0x03...0x06 => .{ .r = saturatingAdd(110, height_boost / 2), .g = saturatingAdd(112, depth_boost / 3), .b = saturatingAdd(54, depth_boost / 4), .a = 188 },
        8 => .{ .r = saturatingAdd(92, depth_boost / 3), .g = saturatingAdd(132, height_boost), .b = 66, .a = 188 },
        else => switch (tile.top_shape_class) {
            .solid => .{ .r = saturatingAdd(76, height_boost / 2), .g = saturatingAdd(100, depth_boost / 3), .b = saturatingAdd(112, depth_boost / 4), .a = 184 },
            .single_stair => .{ .r = saturatingAdd(132, height_boost / 2), .g = saturatingAdd(108, depth_boost / 4), .b = 84, .a = 188 },
            .double_stair_corner => .{ .r = saturatingAdd(120, height_boost / 2), .g = saturatingAdd(94, depth_boost / 4), .b = 74, .a = 188 },
            .double_stair_peak => .{ .r = saturatingAdd(116, height_boost / 3), .g = saturatingAdd(118, depth_boost / 3), .b = 78, .a = 188 },
            .open => .{ .r = 46, .g = 58, .b = saturatingAdd(72, depth_boost / 4), .a = 172 },
            else => .{ .r = saturatingAdd(126, height_boost / 2), .g = saturatingAdd(96, depth_boost / 4), .b = 62, .a = 188 },
        },
    };
}

pub fn drawCompositionContour(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    edge: anytype,
    thickness: i32,
    color: sdl.Color,
) !void {
    const resolved_edge: ContourEdge = edge;
    if (thickness <= 0) return;

    switch (resolved_edge) {
        .north => for (0..@as(usize, @intCast(thickness))) |offset| {
            const y = rect.y + @as(i32, @intCast(offset));
            try canvas.drawLine(rect.x, y, rect.right(), y, color);
        },
        .west => for (0..@as(usize, @intCast(thickness))) |offset| {
            const x = rect.x + @as(i32, @intCast(offset));
            try canvas.drawLine(x, rect.y, x, rect.bottom(), color);
        },
    }
}

pub fn contourThickness(height_delta: u8) i32 {
    if (height_delta == 0) return 0;
    return std.math.clamp(1 + @divTrunc(@as(i32, height_delta) - 1, 4), 1, 3);
}

pub fn compositionHeightAt(snapshot: projection.RenderSnapshot, x: usize, z: usize) u8 {
    if (x >= snapshot.grid_width or z >= snapshot.grid_depth) return 0;
    return snapshot.composition.height_grid[(z * snapshot.grid_width) + x];
}

pub fn drawSurfaceMarker(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    tile: state.CompositionTileSnapshot,
    color: sdl.Color,
) !void {
    if (rect.w < 3 or rect.h < 3) return;

    const marker = rect.inset(@max(1, @divTrunc(@min(rect.w, rect.h), 4)));
    if (marker.w < 2 or marker.h < 2) return;

    switch (tile.top_shape_class) {
        .solid => {},
        .open => try canvas.drawRect(marker, color),
        .single_stair => switch (tile.top_shape) {
            2, 5 => try canvas.drawLine(marker.x, marker.y, marker.right(), marker.bottom(), color),
            3, 4 => try canvas.drawLine(marker.right(), marker.y, marker.x, marker.bottom(), color),
            else => {},
        },
        .double_stair_corner => {
            const center_x = marker.x + @divTrunc(marker.w, 2);
            const center_y = marker.y + @divTrunc(marker.h, 2);
            switch (shapeFacing(tile.top_shape) orelse .top) {
                .top => {
                    try canvas.drawLine(marker.x, marker.bottom(), center_x, marker.y, color);
                    try canvas.drawLine(marker.right(), marker.bottom(), center_x, marker.y, color);
                },
                .bottom => {
                    try canvas.drawLine(marker.x, marker.y, center_x, marker.bottom(), color);
                    try canvas.drawLine(marker.right(), marker.y, center_x, marker.bottom(), color);
                },
                .left => {
                    try canvas.drawLine(marker.right(), marker.y, marker.x, center_y, color);
                    try canvas.drawLine(marker.right(), marker.bottom(), marker.x, center_y, color);
                },
                .right => {
                    try canvas.drawLine(marker.x, marker.y, marker.right(), center_y, color);
                    try canvas.drawLine(marker.x, marker.bottom(), marker.right(), center_y, color);
                },
            }
        },
        .double_stair_peak => {
            try canvas.drawLine(marker.x, marker.y, marker.right(), marker.bottom(), color);
            try canvas.drawLine(marker.right(), marker.y, marker.x, marker.bottom(), color);
        },
        .weird => {
            const center_x = marker.x + @divTrunc(marker.w, 2);
            const center_y = marker.y + @divTrunc(marker.h, 2);
            try canvas.drawLine(marker.x, center_y, marker.right(), center_y, color);
            try canvas.drawLine(center_x, marker.y, center_x, marker.bottom(), color);
        },
    }
}

pub fn drawFragmentCellMarker(
    canvas: *sdl.Canvas,
    cell_rect: sdl.Rect,
    cell: state.FragmentZoneCellSnapshot,
    color: sdl.Color,
) !void {
    const marker = cell_rect.inset(@max(1, @divTrunc(@min(cell_rect.w, cell_rect.h), 4)));
    if (marker.w <= 0 or marker.h <= 0) return;

    if (cell.top_shape_class == .solid) {
        try canvas.drawRect(marker, color);
        return;
    }
    if (cell.top_shape_class == .single_stair) {
        if (cell.top_shape == 2 or cell.top_shape == 5) {
            try canvas.drawLine(marker.x, marker.y, marker.right(), marker.bottom(), color);
        } else {
            try canvas.drawLine(marker.right(), marker.y, marker.x, marker.bottom(), color);
        }
        return;
    }
    try canvas.drawLine(marker.x, marker.y, marker.right(), marker.bottom(), color);
    try canvas.drawLine(marker.right(), marker.y, marker.x, marker.bottom(), color);
}

pub fn drawFragmentDeltaMarker(canvas: *sdl.Canvas, cell_rect: sdl.Rect, color: sdl.Color) !void {
    const marker_size = std.math.clamp(@divTrunc(@min(cell_rect.w, cell_rect.h), 3), 2, 5);
    const marker = sdl.Rect{
        .x = cell_rect.right() - marker_size,
        .y = cell_rect.y,
        .w = marker_size,
        .h = marker_size,
    };
    if (marker.w <= 0 or marker.h <= 0) return;
    try canvas.fillRect(marker, color);
}

pub fn fragmentZoneBorderColor(initially_on: bool) sdl.Color {
    return if (initially_on)
        .{ .r = 255, .g = 215, .b = 112, .a = 255 }
    else
        .{ .r = 174, .g = 188, .b = 198, .a = 255 };
}

pub fn fragmentCellColor(cell: state.FragmentZoneCellSnapshot) sdl.Color {
    return switch (cell.top_floor_type) {
        1, 0x0F => .{ .r = 68, .g = 148, .b = 220, .a = 255 },
        0x09, 0x0D => .{ .r = 224, .g = 118, .b = 70, .a = 255 },
        0x0B, 0x0E => .{ .r = 116, .g = 188, .b = 102, .a = 255 },
        else => switch (cell.top_shape_class) {
            .solid => .{ .r = 224, .g = 178, .b = 86, .a = 255 },
            .single_stair => .{ .r = 240, .g = 148, .b = 102, .a = 255 },
            .double_stair_corner => .{ .r = 232, .g = 126, .b = 142, .a = 255 },
            .double_stair_peak => .{ .r = 208, .g = 118, .b = 198, .a = 255 },
            .open, .weird => .{ .r = 192, .g = 196, .b = 204, .a = 255 },
        },
    };
}

pub fn zoneColor(kind: scene_data.ZoneType) sdl.Color {
    return switch (kind) {
        .change_cube => .{ .r = 255, .g = 122, .b = 69, .a = 255 },
        .camera => .{ .r = 113, .g = 173, .b = 255, .a = 255 },
        .scenario => .{ .r = 145, .g = 211, .b = 106, .a = 255 },
        .grm => .{ .r = 255, .g = 206, .b = 84, .a = 255 },
        .giver => .{ .r = 204, .g = 128, .b = 255, .a = 255 },
        .message => .{ .r = 255, .g = 133, .b = 194, .a = 255 },
        .ladder => .{ .r = 117, .g = 230, .b = 186, .a = 255 },
        .escalator => .{ .r = 255, .g = 159, .b = 96, .a = 255 },
        .hit => .{ .r = 255, .g = 84, .b = 84, .a = 255 },
        .rail => .{ .r = 123, .g = 170, .b = 170, .a = 255 },
    };
}

fn shapeFacing(shape: u8) ?Facing {
    return switch (shape) {
        6, 0x0A => .top,
        7, 0x0B => .bottom,
        8, 0x0C => .left,
        9, 0x0D => .right,
        else => null,
    };
}

pub fn lightenColor(color: sdl.Color, amount: u8) sdl.Color {
    return .{
        .r = saturatingAdd(color.r, amount),
        .g = saturatingAdd(color.g, amount),
        .b = saturatingAdd(color.b, amount),
        .a = color.a,
    };
}

pub fn darkenColor(color: sdl.Color, amount: u8) sdl.Color {
    return .{
        .r = saturatingSub(color.r, amount),
        .g = saturatingSub(color.g, amount),
        .b = saturatingSub(color.b, amount),
        .a = color.a,
    };
}

fn saturatingAdd(base: u8, amount: u8) u8 {
    return @intCast(@min(@as(u16, 255), @as(u16, base) + @as(u16, amount)));
}

fn saturatingSub(base: u8, amount: u8) u8 {
    return @intCast(@max(@as(i16, 0), @as(i16, base) - @as(i16, amount)));
}

pub fn withAlpha(color: sdl.Color, alpha: u8) sdl.Color {
    return .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = alpha,
    };
}

pub fn drawMarker(canvas: *sdl.Canvas, point: layout.ScreenPoint, size: i32, color: sdl.Color) !void {
    const half = @divTrunc(size, 2);
    try canvas.fillRect(.{
        .x = point.x - half,
        .y = point.y - half,
        .w = size,
        .h = size,
    }, color);
}

pub fn drawCrosshair(canvas: *sdl.Canvas, point: layout.ScreenPoint, radius: i32, color: sdl.Color) !void {
    try canvas.drawLine(point.x - radius, point.y, point.x + radius, point.y, color);
    try canvas.drawLine(point.x, point.y - radius, point.x, point.y + radius, color);
    try canvas.drawLine(point.x - radius, point.y - radius, point.x + radius, point.y + radius, color);
    try canvas.drawLine(point.x - radius, point.y + radius, point.x + radius, point.y - radius, color);
}

pub fn findBrickPreview(previews: []const background_data.BrickPreview, brick_index: u16) ?background_data.BrickPreview {
    for (previews) |preview| {
        if (preview.brick_index == brick_index) return preview;
    }
    return null;
}

pub fn requireBrickPreview(
    previews: []const background_data.BrickPreview,
    brick_index: u16,
) !background_data.BrickPreview {
    if (brick_index == 0) return error.ViewerBrickPreviewMissing;
    return findBrickPreview(previews, brick_index) orelse error.ViewerBrickPreviewMissing;
}

pub fn findFirstNonEmptyFragmentCell(cells: []const state.FragmentZoneCellSnapshot) ?state.FragmentZoneCellSnapshot {
    for (cells) |cell| {
        if (cell.has_non_empty) return cell;
    }
    return null;
}

fn glyphRows(raw_char: u8) [glyph_height]u8 {
    const char = if (raw_char >= 'a' and raw_char <= 'z') raw_char - 32 else raw_char;
    return switch (char) {
        'A' => .{ 0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        'B' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110 },
        'C' => .{ 0b01111, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b01111 },
        'D' => .{ 0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110 },
        'E' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 },
        'F' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000 },
        'G' => .{ 0b01111, 0b10000, 0b10000, 0b10011, 0b10001, 0b10001, 0b01111 },
        'H' => .{ 0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        'I' => .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111 },
        'J' => .{ 0b00111, 0b00010, 0b00010, 0b00010, 0b10010, 0b10010, 0b01100 },
        'K' => .{ 0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001 },
        'L' => .{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 },
        'M' => .{ 0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001 },
        'N' => .{ 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001 },
        'O' => .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        'P' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000 },
        'Q' => .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101 },
        'R' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 },
        'S' => .{ 0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110 },
        'T' => .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 },
        'U' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        'V' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100 },
        'W' => .{ 0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010 },
        'X' => .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001 },
        'Y' => .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100 },
        'Z' => .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111 },
        '0' => .{ 0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110 },
        '1' => .{ 0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        '2' => .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111 },
        '3' => .{ 0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110 },
        '4' => .{ 0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010 },
        '5' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b00001, 0b00001, 0b11110 },
        '6' => .{ 0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110 },
        '7' => .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000 },
        '8' => .{ 0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110 },
        '9' => .{ 0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100 },
        ' ' => .{ 0, 0, 0, 0, 0, 0, 0 },
        '/' => .{ 0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000 },
        '\\' => .{ 0b10000, 0b01000, 0b01000, 0b00100, 0b00010, 0b00010, 0b00001 },
        '-' => .{ 0, 0, 0, 0b11111, 0, 0, 0 },
        '+' => .{ 0, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0 },
        '=' => .{ 0, 0, 0b11111, 0, 0b11111, 0, 0 },
        ':' => .{ 0, 0b00100, 0b00100, 0, 0b00100, 0b00100, 0 },
        '.' => .{ 0, 0, 0, 0, 0, 0b01100, 0b01100 },
        ',' => .{ 0, 0, 0, 0, 0b00100, 0b00100, 0b01000 },
        '_' => .{ 0, 0, 0, 0, 0, 0, 0b11111 },
        '|' => .{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 },
        '@' => .{ 0b01110, 0b10001, 0b10111, 0b10101, 0b10111, 0b10000, 0b01110 },
        '<' => .{ 0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010 },
        '>' => .{ 0b01000, 0b00100, 0b00010, 0b00001, 0b00010, 0b00100, 0b01000 },
        '(' => .{ 0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010 },
        ')' => .{ 0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000 },
        '?' => .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0, 0b00100 },
        else => .{ 0b11111, 0b10001, 0b00010, 0b00100, 0b00010, 0, 0b00100 },
    };
}
