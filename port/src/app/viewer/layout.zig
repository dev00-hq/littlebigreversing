const std = @import("std");
const sdl = @import("../../platform/sdl.zig");
const state = @import("../../runtime/room_state.zig");

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

pub const ScreenPoint = struct {
    x: i32,
    y: i32,
};

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
    const clamped_x = std.math.clamp(world_x, snapshot.world_bounds.min_x, snapshot.world_bounds.max_x);
    const clamped_z = std.math.clamp(world_z, snapshot.world_bounds.min_z, snapshot.world_bounds.max_z);

    const span_x = snapshot.world_bounds.spanX();
    const span_z = snapshot.world_bounds.spanZ();
    const left = schematic.x;
    const right = schematic.right();
    const top = schematic.y;
    const bottom = schematic.bottom();
    const screen_span_x = @max(0, right - left);
    const screen_span_z = @max(0, bottom - top);
    const normalized_x = @as(f64, @floatFromInt(clamped_x - snapshot.world_bounds.min_x)) / @as(f64, @floatFromInt(span_x));
    const normalized_z = @as(f64, @floatFromInt(clamped_z - snapshot.world_bounds.min_z)) / @as(f64, @floatFromInt(span_z));

    return .{
        .x = left + @as(i32, @intFromFloat(@round(normalized_x * @as(f64, @floatFromInt(screen_span_x))))),
        .y = top + @as(i32, @intFromFloat(@round(normalized_z * @as(f64, @floatFromInt(screen_span_z))))),
    };
}

pub fn projectZoneBounds(snapshot: state.RenderSnapshot, schematic: sdl.Rect, zone: state.ZoneBoundsSnapshot) sdl.Rect {
    const first = projectWorldPoint(snapshot, schematic, zone.x_min, zone.z_min);
    const second = projectWorldPoint(snapshot, schematic, zone.x_max, zone.z_max);

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
