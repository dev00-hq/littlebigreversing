const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const state = @import("../../runtime/room_state.zig");
const world_geometry = @import("../../runtime/world_geometry.zig");

pub const DebugLayout = struct {
    frame: sdl.Rect,
    schematic_frame: sdl.Rect,
    schematic: sdl.Rect,
    sidebar: sdl.Rect,
};

pub const SchematicLayout = struct {
    frame: sdl.Rect,
    schematic: sdl.Rect,
};

pub const ZoomLevel = enum(u8) {
    fit,
    room,
    detail,
};

pub const GridViewport = struct {
    origin_x: usize,
    origin_z: usize,
    width: usize,
    depth: usize,
};

pub const ScreenPoint = struct {
    x: i32,
    y: i32,
};

const world_grid_span_xz: i32 = 512;

fn computeFrame(canvas_width: i32, canvas_height: i32) struct { frame: sdl.Rect, available: sdl.Rect } {
    const outer_margin = 24;
    const inner_margin = 18;
    const frame = sdl.Rect{
        .x = outer_margin,
        .y = outer_margin,
        .w = @max(1, canvas_width - (outer_margin * 2)),
        .h = @max(1, canvas_height - (outer_margin * 2)),
    };
    return .{
        .frame = frame,
        .available = frame.inset(inner_margin),
    };
}

pub fn computeSchematicLayout(
    canvas_width: i32,
    canvas_height: i32,
    grid_width: usize,
    grid_depth: usize,
) SchematicLayout {
    const frame = computeFrame(canvas_width, canvas_height);
    return .{
        .frame = frame.frame,
        .schematic = fitSchematicRect(frame.available, grid_width, grid_depth),
    };
}

pub fn computeDebugLayout(
    canvas_width: i32,
    canvas_height: i32,
    grid_width: usize,
    grid_depth: usize,
    _: bool,
) DebugLayout {
    const frame = computeFrame(canvas_width, canvas_height);
    const available = frame.available;
    const sidebar_gap = 16;
    const sidebar_width = std.math.clamp(@divTrunc(available.w, 3), 320, 420);
    const content_width = @max(1, available.w - sidebar_width - sidebar_gap);
    const content = sdl.Rect{
        .x = available.x,
        .y = available.y,
        .w = content_width,
        .h = available.h,
    };
    const sidebar = sdl.Rect{
        .x = content.x + content.w + sidebar_gap,
        .y = available.y,
        .w = sidebar_width,
        .h = available.h,
    };

    const schematic_frame = fitSchematicRect(content, grid_width, grid_depth);
    return .{
        .frame = frame.frame,
        .schematic_frame = schematic_frame,
        .schematic = schematic_frame.inset(10),
        .sidebar = sidebar,
    };
}

fn fitSchematicRect(available: sdl.Rect, grid_width: usize, grid_depth: usize) sdl.Rect {
    const target_ratio = @as(f64, @floatFromInt(grid_width)) / @as(f64, @floatFromInt(@max(grid_depth, 1)));
    const available_ratio = @as(f64, @floatFromInt(available.w)) / @as(f64, @floatFromInt(available.h));

    if (available_ratio > target_ratio) {
        const schematic_width = @max(1, @as(i32, @intFromFloat(@floor(@as(f64, @floatFromInt(available.h)) * target_ratio))));
        return .{
            .x = available.x + @divTrunc(available.w - schematic_width, 2),
            .y = available.y,
            .w = schematic_width,
            .h = available.h,
        };
    }

    const schematic_height = @max(1, @as(i32, @intFromFloat(@floor(@as(f64, @floatFromInt(available.w)) / target_ratio))));
    return .{
        .x = available.x,
        .y = available.y + @divTrunc(available.h - schematic_height, 2),
        .w = available.w,
        .h = schematic_height,
    };
}

pub fn projectWorldPoint(snapshot: state.RenderSnapshot, schematic: sdl.Rect, world_x: i32, world_z: i32) ScreenPoint {
    return projectWorldPointInBounds(schematic, snapshot.world_bounds, world_x, world_z);
}

pub fn computeGridViewport(snapshot: state.RenderSnapshot, zoom_level: ZoomLevel) GridViewport {
    if (zoom_level == .fit) return fullGridViewport(snapshot.grid_width, snapshot.grid_depth);
    const occupied = snapshot.composition.occupied_bounds orelse return fullGridViewport(snapshot.grid_width, snapshot.grid_depth);
    const margin: usize = switch (zoom_level) {
        .fit => unreachable,
        .room => 4,
        .detail => 1,
    };

    return boundsViewport(snapshot.grid_width, snapshot.grid_depth, occupied, margin);
}

pub fn projectWorldPointInViewport(
    schematic: sdl.Rect,
    viewport: GridViewport,
    world_x: i32,
    world_z: i32,
) ?ScreenPoint {
    const bounds = viewportWorldBounds(viewport);
    if (world_x < bounds.min_x or world_x > bounds.max_x or world_z < bounds.min_z or world_z > bounds.max_z) return null;
    return projectWorldPointInBounds(schematic, bounds, world_x, world_z);
}

pub fn projectZoneBoundsInViewport(
    schematic: sdl.Rect,
    viewport: GridViewport,
    zone: state.ZoneBoundsSnapshot,
) ?sdl.Rect {
    const bounds = viewportWorldBounds(viewport);
    if (zone.x_max < bounds.min_x or zone.x_min > bounds.max_x or zone.z_max < bounds.min_z or zone.z_min > bounds.max_z) return null;

    const first = projectWorldPointInBounds(
        schematic,
        bounds,
        std.math.clamp(zone.x_min, bounds.min_x, bounds.max_x),
        std.math.clamp(zone.z_min, bounds.min_z, bounds.max_z),
    );
    const second = projectWorldPointInBounds(
        schematic,
        bounds,
        std.math.clamp(zone.x_max, bounds.min_x, bounds.max_x),
        std.math.clamp(zone.z_max, bounds.min_z, bounds.max_z),
    );

    return rectFromPoints(first, second);
}

pub fn projectGridCellRectInViewport(rect: sdl.Rect, viewport: GridViewport, x: usize, z: usize) ?sdl.Rect {
    if (x < viewport.origin_x or z < viewport.origin_z) return null;
    if (x >= viewport.origin_x + viewport.width or z >= viewport.origin_z + viewport.depth) return null;
    return projectGridCellRect(rect, viewport.width, viewport.depth, x - viewport.origin_x, z - viewport.origin_z);
}

pub fn projectGridAreaRectInViewport(
    rect: sdl.Rect,
    viewport: GridViewport,
    origin_x: usize,
    origin_z: usize,
    cell_width: usize,
    cell_depth: usize,
) ?sdl.Rect {
    const area_right = origin_x + cell_width;
    const area_bottom = origin_z + cell_depth;
    const view_right = viewport.origin_x + viewport.width;
    const view_bottom = viewport.origin_z + viewport.depth;
    const clipped_left = @max(origin_x, viewport.origin_x);
    const clipped_top = @max(origin_z, viewport.origin_z);
    const clipped_right = @min(area_right, view_right);
    const clipped_bottom = @min(area_bottom, view_bottom);
    if (clipped_left >= clipped_right or clipped_top >= clipped_bottom) return null;

    return projectGridAreaRect(
        rect,
        viewport.width,
        viewport.depth,
        clipped_left - viewport.origin_x,
        clipped_top - viewport.origin_z,
        clipped_right - clipped_left,
        clipped_bottom - clipped_top,
    );
}

fn fullGridViewport(grid_width: usize, grid_depth: usize) GridViewport {
    return .{
        .origin_x = 0,
        .origin_z = 0,
        .width = @max(1, grid_width),
        .depth = @max(1, grid_depth),
    };
}

fn boundsViewport(
    grid_width: usize,
    grid_depth: usize,
    bounds: state.CompositionBoundsSnapshot,
    margin: usize,
) GridViewport {
    const min_x = bounds.min_x -| margin;
    const min_z = bounds.min_z -| margin;
    const max_x = @min(grid_width -| 1, bounds.max_x + margin);
    const max_z = @min(grid_depth -| 1, bounds.max_z + margin);
    return .{
        .origin_x = min_x,
        .origin_z = min_z,
        .width = @max(1, (max_x - min_x) + 1),
        .depth = @max(1, (max_z - min_z) + 1),
    };
}

fn viewportWorldBounds(viewport: GridViewport) world_geometry.WorldBounds {
    return .{
        .min_x = @as(i32, @intCast(viewport.origin_x)) * world_grid_span_xz,
        .max_x = @as(i32, @intCast(viewport.origin_x + viewport.width)) * world_grid_span_xz - 1,
        .min_z = @as(i32, @intCast(viewport.origin_z)) * world_grid_span_xz,
        .max_z = @as(i32, @intCast(viewport.origin_z + viewport.depth)) * world_grid_span_xz - 1,
    };
}

fn projectWorldPointInBounds(schematic: sdl.Rect, bounds: world_geometry.WorldBounds, world_x: i32, world_z: i32) ScreenPoint {
    const clamped_x = std.math.clamp(world_x, bounds.min_x, bounds.max_x);
    const clamped_z = std.math.clamp(world_z, bounds.min_z, bounds.max_z);

    const span_x = bounds.spanX();
    const span_z = bounds.spanZ();
    const left = schematic.x;
    const right = schematic.right();
    const top = schematic.y;
    const bottom = schematic.bottom();
    const screen_span_x = @max(0, right - left);
    const screen_span_z = @max(0, bottom - top);
    const normalized_x = @as(f64, @floatFromInt(clamped_x - bounds.min_x)) / @as(f64, @floatFromInt(span_x));
    const normalized_z = @as(f64, @floatFromInt(clamped_z - bounds.min_z)) / @as(f64, @floatFromInt(span_z));

    return .{
        .x = left + @as(i32, @intFromFloat(@round(normalized_x * @as(f64, @floatFromInt(screen_span_x))))),
        .y = top + @as(i32, @intFromFloat(@round(normalized_z * @as(f64, @floatFromInt(screen_span_z))))),
    };
}

pub fn projectZoneBounds(snapshot: state.RenderSnapshot, schematic: sdl.Rect, zone: state.ZoneBoundsSnapshot) sdl.Rect {
    const first = projectWorldPoint(snapshot, schematic, zone.x_min, zone.z_min);
    const second = projectWorldPoint(snapshot, schematic, zone.x_max, zone.z_max);
    return rectFromPoints(first, second);
}

fn rectFromPoints(first: ScreenPoint, second: ScreenPoint) sdl.Rect {
    const left = @min(first.x, second.x);
    const right = @max(first.x, second.x);
    const top = @min(first.y, second.y);
    const bottom = @max(first.y, second.y);

    return .{
        .x = left,
        .y = top,
        .w = @max(1, (right - left) + 1),
        .h = @max(1, (bottom - top) + 1),
    };
}

pub fn projectGridCellRect(rect: sdl.Rect, width: usize, depth: usize, x: usize, z: usize) sdl.Rect {
    const left = interpolateAxis(rect.x, rect.right(), x, width);
    const right = interpolateAxis(rect.x, rect.right(), x + 1, width);
    const top = interpolateAxis(rect.y, rect.bottom(), z, depth);
    const bottom = interpolateAxis(rect.y, rect.bottom(), z + 1, depth);

    return .{
        .x = @min(left, right),
        .y = @min(top, bottom),
        .w = @max(1, @max(left, right) - @min(left, right)),
        .h = @max(1, @max(top, bottom) - @min(top, bottom)),
    };
}

pub fn projectGridAreaRect(rect: sdl.Rect, width: usize, depth: usize, origin_x: usize, origin_z: usize, cell_width: usize, cell_depth: usize) sdl.Rect {
    const start = projectGridCellRect(rect, width, depth, origin_x, origin_z);
    const finish = projectGridCellRect(rect, width, depth, origin_x + cell_width -| 1, origin_z + cell_depth -| 1);
    const left = @min(start.x, finish.x);
    const top = @min(start.y, finish.y);
    const right = @max(start.right(), finish.right());
    const bottom = @max(start.bottom(), finish.bottom());

    return .{
        .x = left,
        .y = top,
        .w = @max(1, right - left),
        .h = @max(1, bottom - top),
    };
}

pub fn interpolateAxis(start: i32, finish: i32, index: usize, divisions: usize) i32 {
    if (divisions == 0) return start;
    const span = finish - start;
    const ratio = @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(divisions));
    return start + @as(i32, @intFromFloat(@round(ratio * @as(f64, @floatFromInt(span)))));
}
