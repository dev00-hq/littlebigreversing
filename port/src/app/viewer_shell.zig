const std = @import("std");
const diagnostics = @import("../foundation/diagnostics.zig");
const paths_mod = @import("../foundation/paths.zig");
const sdl = @import("../platform/sdl.zig");
const background_data = @import("../game_data/background.zig");
const scene_data = @import("../game_data/scene.zig");

pub const window_width: i32 = 960;
pub const window_height: i32 = 540;

pub const ParsedArgs = struct {
    asset_root_override: ?[]u8,
    scene_entry: usize,
    background_entry: usize,

    pub fn deinit(self: ParsedArgs, allocator: std.mem.Allocator) void {
        if (self.asset_root_override) |value| allocator.free(value);
    }
};

pub const HeroStartSnapshot = struct {
    x: i16,
    y: i16,
    z: i16,
};

pub const ObjectPositionSnapshot = struct {
    index: usize,
    x: i32,
    y: i32,
    z: i32,
};

pub const TrackPointSnapshot = struct {
    index: usize,
    x: i32,
    y: i32,
    z: i32,
};

pub const ZoneBoundsSnapshot = struct {
    index: usize,
    kind: scene_data.ZoneType,
    x_min: i32,
    y_min: i32,
    z_min: i32,
    x_max: i32,
    y_max: i32,
    z_max: i32,
};

pub const SceneSnapshot = struct {
    entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    hero_start: HeroStartSnapshot,
    object_count: usize,
    zone_count: usize,
    track_count: usize,
    objects: []ObjectPositionSnapshot,
    zones: []ZoneBoundsSnapshot,
    tracks: []TrackPointSnapshot,

    pub fn deinit(self: SceneSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.objects);
        allocator.free(self.zones);
        allocator.free(self.tracks);
    }
};

pub const BackgroundLinkageSnapshot = struct {
    remapped_cube_index: usize,
    gri_entry_index: usize,
    gri_my_grm: u8,
    grm_entry_index: usize,
    gri_my_bll: u8,
    bll_entry_index: usize,
};

pub const ColumnTableSnapshot = struct {
    width: usize,
    depth: usize,
    offset_count: usize,
    table_byte_length: usize,
    data_byte_length: usize,
    min_offset: u16,
    max_offset: u16,
};

pub const BackgroundSnapshot = struct {
    entry_index: usize,
    linkage: BackgroundLinkageSnapshot,
    used_block_ids: []u8,
    column_table: ColumnTableSnapshot,

    pub fn deinit(self: BackgroundSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.used_block_ids);
    }
};

pub const RoomSnapshot = struct {
    scene: SceneSnapshot,
    background: BackgroundSnapshot,

    pub fn deinit(self: RoomSnapshot, allocator: std.mem.Allocator) void {
        self.scene.deinit(allocator);
        self.background.deinit(allocator);
    }
};

pub const WorldPointSnapshot = struct {
    x: i32,
    y: i32,
    z: i32,
};

pub const WorldBounds = struct {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,

    pub fn init(x: i32, z: i32) WorldBounds {
        return .{
            .min_x = x,
            .max_x = x,
            .min_z = z,
            .max_z = z,
        };
    }

    pub fn include(self: *WorldBounds, x: i32, z: i32) void {
        self.min_x = @min(self.min_x, x);
        self.max_x = @max(self.max_x, x);
        self.min_z = @min(self.min_z, z);
        self.max_z = @max(self.max_z, z);
    }

    pub fn spanX(self: WorldBounds) i32 {
        return @max(1, self.max_x - self.min_x);
    }

    pub fn spanZ(self: WorldBounds) i32 {
        return @max(1, self.max_z - self.min_z);
    }
};

pub const RenderSnapshot = struct {
    grid_width: usize,
    grid_depth: usize,
    world_bounds: WorldBounds,
    hero_start: WorldPointSnapshot,
    objects: []const ObjectPositionSnapshot,
    zones: []const ZoneBoundsSnapshot,
    tracks: []const TrackPointSnapshot,
};

pub const SchematicLayout = struct {
    frame: sdl.Rect,
    schematic: sdl.Rect,
};

pub const ScreenPoint = struct {
    x: i32,
    y: i32,
};

pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    var asset_root_override: ?[]u8 = null;
    errdefer if (asset_root_override) |value| allocator.free(value);

    var scene_entry: ?usize = null;
    var background_entry: ?usize = null;

    var index: usize = 0;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--asset-root")) {
            if (asset_root_override != null) return error.DuplicateAssetRootOverride;
            if (index + 1 >= args.len) return error.MissingAssetRoot;
            asset_root_override = try allocator.dupe(u8, args[index + 1]);
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--scene-entry")) {
            if (scene_entry != null) return error.DuplicateSceneEntry;
            if (index + 1 >= args.len) return error.MissingSceneEntry;
            scene_entry = try std.fmt.parseInt(usize, args[index + 1], 10);
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--background-entry")) {
            if (background_entry != null) return error.DuplicateBackgroundEntry;
            if (index + 1 >= args.len) return error.MissingBackgroundEntry;
            background_entry = try std.fmt.parseInt(usize, args[index + 1], 10);
            index += 2;
            continue;
        }
        return error.UnknownOption;
    }

    return .{
        .asset_root_override = asset_root_override,
        .scene_entry = scene_entry orelse return error.MissingSceneEntry,
        .background_entry = background_entry orelse return error.MissingBackgroundEntry,
    };
}

pub fn loadRoomSnapshot(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
) !RoomSnapshot {
    const scene_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);

    var scene = try scene_data.loadSceneMetadata(allocator, scene_path, scene_entry_index);
    defer scene.deinit(allocator);
    if (scene.cube_mode != 0) return error.ViewerSceneMustBeInterior;

    var scene_snapshot = SceneSnapshot{
        .entry_index = scene.entry_index,
        .classic_loader_scene_number = scene.classicLoaderSceneNumber(),
        .scene_kind = scene.sceneKind(),
        .hero_start = .{
            .x = scene.hero_start.x,
            .y = scene.hero_start.y,
            .z = scene.hero_start.z,
        },
        .object_count = scene.object_count,
        .zone_count = scene.zone_count,
        .track_count = scene.track_count,
        .objects = try copyObjectSnapshots(allocator, scene.objects),
        .zones = try copyZoneSnapshots(allocator, scene.zones),
        .tracks = try copyTrackSnapshots(allocator, scene.tracks),
    };
    errdefer scene_snapshot.deinit(allocator);

    const background_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "LBA_BKG.HQR" });
    defer allocator.free(background_path);

    const background = try background_data.loadBackgroundMetadata(allocator, background_path, background_entry_index);
    defer background.deinit(allocator);

    const background_snapshot = BackgroundSnapshot{
        .entry_index = background.entry_index,
        .linkage = .{
            .remapped_cube_index = background.remapped_cube_index,
            .gri_entry_index = background.gri_entry_index,
            .gri_my_grm = background.gri_header.my_grm,
            .grm_entry_index = background.grm_entry_index,
            .gri_my_bll = background.gri_header.my_bll,
            .bll_entry_index = background.bll_entry_index,
        },
        .used_block_ids = try allocator.dupe(u8, background.used_blocks.used_block_ids),
        .column_table = .{
            .width = background.column_table.width,
            .depth = background.column_table.depth,
            .offset_count = background.column_table.offset_count,
            .table_byte_length = background.column_table.table_byte_length,
            .data_byte_length = background.column_table.data_byte_length,
            .min_offset = background.column_table.min_offset,
            .max_offset = background.column_table.max_offset,
        },
    };
    errdefer background_snapshot.deinit(allocator);

    return .{
        .scene = scene_snapshot,
        .background = background_snapshot,
    };
}

pub fn buildRenderSnapshot(room: RoomSnapshot) RenderSnapshot {
    var world_bounds = WorldBounds.init(room.scene.hero_start.x, room.scene.hero_start.z);
    for (room.scene.objects) |object| world_bounds.include(object.x, object.z);
    for (room.scene.tracks) |track| world_bounds.include(track.x, track.z);
    for (room.scene.zones) |zone| {
        world_bounds.include(zone.x_min, zone.z_min);
        world_bounds.include(zone.x_max, zone.z_max);
    }

    return .{
        .grid_width = room.background.column_table.width,
        .grid_depth = room.background.column_table.depth,
        .world_bounds = world_bounds,
        .hero_start = .{
            .x = room.scene.hero_start.x,
            .y = room.scene.hero_start.y,
            .z = room.scene.hero_start.z,
        },
        .objects = room.scene.objects,
        .zones = room.scene.zones,
        .tracks = room.scene.tracks,
    };
}

pub fn computeSchematicLayout(
    canvas_width: i32,
    canvas_height: i32,
    grid_width: usize,
    grid_depth: usize,
) SchematicLayout {
    const outer_margin = 24;
    const inner_margin = 18;
    const frame = sdl.Rect{
        .x = outer_margin,
        .y = outer_margin,
        .w = @max(1, canvas_width - (outer_margin * 2)),
        .h = @max(1, canvas_height - (outer_margin * 2)),
    };
    const available = frame.inset(inner_margin);
    const target_ratio = @as(f64, @floatFromInt(grid_width)) / @as(f64, @floatFromInt(@max(grid_depth, 1)));
    const available_ratio = @as(f64, @floatFromInt(available.w)) / @as(f64, @floatFromInt(available.h));

    if (available_ratio > target_ratio) {
        const schematic_width = @max(1, @as(i32, @intFromFloat(@floor(@as(f64, @floatFromInt(available.h)) * target_ratio))));
        return .{
            .frame = frame,
            .schematic = .{
                .x = available.x + @divTrunc(available.w - schematic_width, 2),
                .y = available.y,
                .w = schematic_width,
                .h = available.h,
            },
        };
    }

    const schematic_height = @max(1, @as(i32, @intFromFloat(@floor(@as(f64, @floatFromInt(available.w)) / target_ratio))));
    return .{
        .frame = frame,
        .schematic = .{
            .x = available.x,
            .y = available.y + @divTrunc(available.h - schematic_height, 2),
            .w = available.w,
            .h = schematic_height,
        },
    };
}

pub fn projectWorldPoint(snapshot: RenderSnapshot, schematic: sdl.Rect, world_x: i32, world_z: i32) ScreenPoint {
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
        .y = bottom - @as(i32, @intFromFloat(@round(normalized_z * @as(f64, @floatFromInt(screen_span_z))))),
    };
}

pub fn projectZoneBounds(snapshot: RenderSnapshot, schematic: sdl.Rect, zone: ZoneBoundsSnapshot) sdl.Rect {
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

pub fn renderDebugView(canvas: *sdl.Canvas, snapshot: RenderSnapshot) !void {
    const layout = computeSchematicLayout(canvas.width, canvas.height, snapshot.grid_width, snapshot.grid_depth);
    const panel = layout.schematic.inset(10);

    try canvas.clear(.{ .r = 13, .g = 20, .b = 26, .a = 255 });
    try canvas.fillRect(layout.frame, .{ .r = 22, .g = 32, .b = 41, .a = 255 });
    try canvas.drawRect(layout.frame, .{ .r = 96, .g = 123, .b = 142, .a = 255 });
    try canvas.fillRect(panel, .{ .r = 10, .g = 14, .b = 19, .a = 255 });
    try canvas.drawRect(panel, .{ .r = 56, .g = 80, .b = 92, .a = 255 });
    try drawGrid(canvas, panel, snapshot.grid_width, snapshot.grid_depth);

    for (snapshot.zones) |zone| {
        const rect = projectZoneBounds(snapshot, panel, zone);
        const zone_color = zoneColor(zone.kind);
        try canvas.fillRect(rect, withAlpha(zone_color, 40));
        try canvas.drawRect(rect, zone_color);
    }

    for (snapshot.tracks[0 .. snapshot.tracks.len -| 1], 0..) |track, index| {
        const next = snapshot.tracks[index + 1];
        const start = projectWorldPoint(snapshot, panel, track.x, track.z);
        const finish = projectWorldPoint(snapshot, panel, next.x, next.z);
        try canvas.drawLine(start.x, start.y, finish.x, finish.y, .{ .r = 59, .g = 201, .b = 255, .a = 192 });
    }

    for (snapshot.tracks) |track| {
        const point = projectWorldPoint(snapshot, panel, track.x, track.z);
        try drawMarker(canvas, point, 4, .{ .r = 76, .g = 226, .b = 255, .a = 255 });
    }

    for (snapshot.objects) |object| {
        const point = projectWorldPoint(snapshot, panel, object.x, object.z);
        try drawMarker(canvas, point, 6, .{ .r = 255, .g = 194, .b = 92, .a = 255 });
    }

    const hero = projectWorldPoint(snapshot, panel, snapshot.hero_start.x, snapshot.hero_start.z);
    try drawCrosshair(canvas, hero, 8, .{ .r = 255, .g = 86, .b = 86, .a = 255 });
    try drawMarker(canvas, hero, 6, .{ .r = 255, .g = 240, .b = 148, .a = 255 });
    canvas.present();
}

pub fn printStartupDiagnostics(
    writer: anytype,
    resolved: paths_mod.ResolvedPaths,
    room: RoomSnapshot,
) !void {
    try diagnostics.printLine(writer, &.{
        .{ .key = "event", .value = "startup" },
        .{ .key = "repo_root", .value = resolved.repo_root },
        .{ .key = "asset_root", .value = resolved.asset_root },
        .{ .key = "work_root", .value = resolved.work_root },
    });
    try diagnostics.printLine(writer, &.{
        .{ .key = "event", .value = "room_snapshot" },
        .{ .key = "scene_kind", .value = room.scene.scene_kind },
    });
    try writer.print(
        "scene_entry_index={d} background_entry_index={d} classic_loader_scene_number={any} hero_x={d} hero_y={d} hero_z={d} object_count={d} zone_count={d} track_count={d}\n",
        .{
            room.scene.entry_index,
            room.background.entry_index,
            room.scene.classic_loader_scene_number,
            room.scene.hero_start.x,
            room.scene.hero_start.y,
            room.scene.hero_start.z,
            room.scene.object_count,
            room.scene.zone_count,
            room.scene.track_count,
        },
    );
    try writer.print(
        "render_snapshot=objects:{d} zones:{d} tracks:{d}\n",
        .{
            room.scene.objects.len,
            room.scene.zones.len,
            room.scene.tracks.len,
        },
    );
    try writer.print(
        "remapped_cube_index={d} gri_entry_index={d} gri_my_grm={d} grm_entry_index={d} gri_my_bll={d} bll_entry_index={d}\n",
        .{
            room.background.linkage.remapped_cube_index,
            room.background.linkage.gri_entry_index,
            room.background.linkage.gri_my_grm,
            room.background.linkage.grm_entry_index,
            room.background.linkage.gri_my_bll,
            room.background.linkage.bll_entry_index,
        },
    );
    try writer.print(
        "column_table={d}x{d} offsets={d} table_bytes={d} min_offset={d} max_offset={d} data_bytes={d}\n",
        .{
            room.background.column_table.width,
            room.background.column_table.depth,
            room.background.column_table.offset_count,
            room.background.column_table.table_byte_length,
            room.background.column_table.min_offset,
            room.background.column_table.max_offset,
            room.background.column_table.data_byte_length,
        },
    );
    try printUsedBlockSummary(writer, room.background.used_block_ids);
}

pub fn formatWindowTitleZ(allocator: std.mem.Allocator, room: RoomSnapshot) ![:0]u8 {
    const used_blocks = try formatUsedBlockSummaryAlloc(allocator, room.background.used_block_ids, 6);
    defer allocator.free(used_blocks);

    const title = try std.fmt.allocPrint(
        allocator,
        "Little Big Adventure 2 viewer scene={d} background={d} kind={s} loader={any} hero={d},{d},{d} objects={d} zones={d} tracks={d} cube={d} gri={d}(grm={d},bll={d}) grm={d} bll={d} blocks={s} columns={d}x{d}",
        .{
            room.scene.entry_index,
            room.background.entry_index,
            room.scene.scene_kind,
            room.scene.classic_loader_scene_number,
            room.scene.hero_start.x,
            room.scene.hero_start.y,
            room.scene.hero_start.z,
            room.scene.object_count,
            room.scene.zone_count,
            room.scene.track_count,
            room.background.linkage.remapped_cube_index,
            room.background.linkage.gri_entry_index,
            room.background.linkage.gri_my_grm,
            room.background.linkage.gri_my_bll,
            room.background.linkage.grm_entry_index,
            room.background.linkage.bll_entry_index,
            used_blocks,
            room.background.column_table.width,
            room.background.column_table.depth,
        },
    );
    defer allocator.free(title);

    return allocator.dupeZ(u8, title);
}

fn copyObjectSnapshots(
    allocator: std.mem.Allocator,
    objects: []const scene_data.SceneObject,
) ![]ObjectPositionSnapshot {
    const copied = try allocator.alloc(ObjectPositionSnapshot, objects.len);
    for (objects, copied) |object, *slot| {
        slot.* = .{
            .index = object.index,
            .x = object.x,
            .y = object.y,
            .z = object.z,
        };
    }
    return copied;
}

fn copyZoneSnapshots(
    allocator: std.mem.Allocator,
    zones: []const scene_data.SceneZone,
) ![]ZoneBoundsSnapshot {
    const copied = try allocator.alloc(ZoneBoundsSnapshot, zones.len);
    for (zones, copied, 0..) |zone, *slot, index| {
        slot.* = .{
            .index = index,
            .kind = zone.zone_type,
            .x_min = @min(zone.x0, zone.x1),
            .y_min = @min(zone.y0, zone.y1),
            .z_min = @min(zone.z0, zone.z1),
            .x_max = @max(zone.x0, zone.x1),
            .y_max = @max(zone.y0, zone.y1),
            .z_max = @max(zone.z0, zone.z1),
        };
    }
    return copied;
}

fn copyTrackSnapshots(
    allocator: std.mem.Allocator,
    tracks: []const scene_data.TrackPoint,
) ![]TrackPointSnapshot {
    const copied = try allocator.alloc(TrackPointSnapshot, tracks.len);
    for (tracks, copied) |track, *slot| {
        slot.* = .{
            .index = track.index,
            .x = track.x,
            .y = track.y,
            .z = track.z,
        };
    }
    return copied;
}

fn drawGrid(canvas: *sdl.Canvas, rect: sdl.Rect, width: usize, depth: usize) !void {
    const left = rect.x;
    const right = rect.right();
    const top = rect.y;
    const bottom = rect.bottom();

    for (0..(width + 1)) |column| {
        const x = interpolateAxis(left, right, column, width);
        const color = if (column % 8 == 0)
            sdl.Color{ .r = 42, .g = 61, .b = 74, .a = 255 }
        else
            sdl.Color{ .r = 25, .g = 36, .b = 45, .a = 255 };
        try canvas.drawLine(x, top, x, bottom, color);
    }

    for (0..(depth + 1)) |row| {
        const y = interpolateAxis(top, bottom, row, depth);
        const color = if (row % 8 == 0)
            sdl.Color{ .r = 42, .g = 61, .b = 74, .a = 255 }
        else
            sdl.Color{ .r = 25, .g = 36, .b = 45, .a = 255 };
        try canvas.drawLine(left, y, right, y, color);
    }
}

fn drawMarker(canvas: *sdl.Canvas, point: ScreenPoint, size: i32, color: sdl.Color) !void {
    const half = @divTrunc(size, 2);
    try canvas.fillRect(.{
        .x = point.x - half,
        .y = point.y - half,
        .w = size,
        .h = size,
    }, color);
}

fn drawCrosshair(canvas: *sdl.Canvas, point: ScreenPoint, radius: i32, color: sdl.Color) !void {
    try canvas.drawLine(point.x - radius, point.y, point.x + radius, point.y, color);
    try canvas.drawLine(point.x, point.y - radius, point.x, point.y + radius, color);
    try canvas.drawLine(point.x - radius, point.y - radius, point.x + radius, point.y + radius, color);
    try canvas.drawLine(point.x - radius, point.y + radius, point.x + radius, point.y - radius, color);
}

fn interpolateAxis(start: i32, finish: i32, index: usize, divisions: usize) i32 {
    if (divisions == 0) return start;
    const span = finish - start;
    const ratio = @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(divisions));
    return start + @as(i32, @intFromFloat(@round(ratio * @as(f64, @floatFromInt(span)))));
}

fn zoneColor(kind: scene_data.ZoneType) sdl.Color {
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

fn withAlpha(color: sdl.Color, alpha: u8) sdl.Color {
    return .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = alpha,
    };
}

fn printUsedBlockSummary(writer: anytype, used_block_ids: []const u8) !void {
    try writer.print("used_block_ids={d} values=", .{used_block_ids.len});
    for (used_block_ids, 0..) |block_id, index| {
        if (index != 0) try writer.writeAll("|");
        try writer.print("{d}", .{block_id});
    }
    try writer.writeAll("\n");
}

fn formatUsedBlockSummaryAlloc(
    allocator: std.mem.Allocator,
    used_block_ids: []const u8,
    max_items: usize,
) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    const writer = output.writer(allocator);
    try writer.print("{d}[", .{used_block_ids.len});

    const item_count = @min(max_items, used_block_ids.len);
    for (used_block_ids[0..item_count], 0..) |block_id, index| {
        if (index != 0) try writer.writeAll("|");
        try writer.print("{d}", .{block_id});
    }
    if (item_count < used_block_ids.len) {
        if (item_count != 0) try writer.writeAll("|");
        try writer.writeAll("...");
    }
    try writer.writeAll("]");

    return output.toOwnedSlice(allocator);
}

test "viewer argument parsing requires explicit scene and background entries" {
    const parsed = try parseArgs(std.testing.allocator, &.{
        "--scene-entry",
        "2",
        "--background-entry",
        "2",
        "--asset-root",
        "D:/assets",
    });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.scene_entry);
    try std.testing.expectEqual(@as(usize, 2), parsed.background_entry);
    try std.testing.expectEqualStrings("D:/assets", parsed.asset_root_override.?);
}

test "viewer room snapshot keeps the canonical interior pair stable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(?usize, 0), room.scene.classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", room.scene.scene_kind);
    try std.testing.expectEqual(@as(i16, 9724), room.scene.hero_start.x);
    try std.testing.expectEqual(@as(i16, 1024), room.scene.hero_start.y);
    try std.testing.expectEqual(@as(i16, 782), room.scene.hero_start.z);
    try std.testing.expectEqual(@as(usize, 9), room.scene.object_count);
    try std.testing.expectEqual(@as(usize, 10), room.scene.zone_count);
    try std.testing.expectEqual(@as(usize, 4), room.scene.track_count);
    try std.testing.expectEqual(@as(usize, 8), room.scene.objects.len);
    try std.testing.expectEqual(@as(usize, 10), room.scene.zones.len);
    try std.testing.expectEqual(@as(usize, 4), room.scene.tracks.len);
    try std.testing.expectEqual(@as(usize, 1), room.scene.objects[0].index);
    try std.testing.expectEqual(@as(i32, 0), room.scene.objects[0].x);
    try std.testing.expectEqual(@as(i32, 0), room.scene.objects[0].z);
    try std.testing.expectEqual(scene_data.ZoneType.change_cube, room.scene.zones[0].kind);
    try std.testing.expectEqual(@as(i32, 9728), room.scene.zones[0].x_min);
    try std.testing.expectEqual(@as(i32, 10239), room.scene.zones[0].x_max);
    try std.testing.expectEqual(@as(i32, 512), room.scene.zones[0].z_min);
    try std.testing.expectEqual(@as(i32, 1535), room.scene.zones[0].z_max);
    try std.testing.expectEqual(@as(usize, 0), room.scene.tracks[0].index);
    try std.testing.expectEqual(@as(i32, 512), room.scene.tracks[0].x);
    try std.testing.expectEqual(@as(i32, 2432), room.scene.tracks[0].z);

    try std.testing.expectEqual(@as(usize, 2), room.background.entry_index);
    try std.testing.expectEqual(@as(usize, 2), room.background.linkage.remapped_cube_index);
    try std.testing.expectEqual(@as(usize, 3), room.background.linkage.gri_entry_index);
    try std.testing.expectEqual(@as(u8, 0), room.background.linkage.gri_my_grm);
    try std.testing.expectEqual(@as(usize, 149), room.background.linkage.grm_entry_index);
    try std.testing.expectEqual(@as(u8, 1), room.background.linkage.gri_my_bll);
    try std.testing.expectEqual(@as(usize, 180), room.background.linkage.bll_entry_index);
    try std.testing.expectEqual(@as(usize, 105), room.background.used_block_ids.len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 7 }, room.background.used_block_ids[0..6]);
    try std.testing.expectEqual(@as(usize, 64), room.background.column_table.width);
    try std.testing.expectEqual(@as(usize, 64), room.background.column_table.depth);
    try std.testing.expectEqual(@as(usize, 4096), room.background.column_table.offset_count);
    try std.testing.expectEqual(@as(usize, 8192), room.background.column_table.table_byte_length);
    try std.testing.expect(room.background.column_table.data_byte_length > 0);
}

test "viewer render snapshot derives a deterministic schematic from the canonical room" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    const render = buildRenderSnapshot(room);
    try std.testing.expectEqual(@as(usize, 64), render.grid_width);
    try std.testing.expectEqual(@as(usize, 64), render.grid_depth);
    try std.testing.expectEqual(@as(i32, 0), render.world_bounds.min_x);
    try std.testing.expectEqual(@as(i32, 10239), render.world_bounds.max_x);
    try std.testing.expectEqual(@as(i32, 0), render.world_bounds.min_z);
    try std.testing.expectEqual(@as(i32, 11264), render.world_bounds.max_z);
    try std.testing.expectEqual(@as(i32, 9724), render.hero_start.x);
    try std.testing.expectEqual(@as(usize, 8), render.objects.len);
    try std.testing.expectEqual(@as(usize, 10), render.zones.len);
    try std.testing.expectEqual(@as(usize, 4), render.tracks.len);
}

test "viewer projection keeps the canonical schematic fit stable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    const render = buildRenderSnapshot(room);
    const layout = computeSchematicLayout(window_width, window_height, render.grid_width, render.grid_depth);
    try std.testing.expectEqual(sdl.Rect{ .x = 24, .y = 24, .w = 912, .h = 492 }, layout.frame);
    try std.testing.expectEqual(sdl.Rect{ .x = 252, .y = 42, .w = 456, .h = 456 }, layout.schematic);

    const southwest = projectWorldPoint(render, layout.schematic, render.world_bounds.min_x, render.world_bounds.min_z);
    try std.testing.expectEqual(ScreenPoint{ .x = 252, .y = 497 }, southwest);

    const northeast = projectWorldPoint(render, layout.schematic, render.world_bounds.max_x, render.world_bounds.max_z);
    try std.testing.expectEqual(ScreenPoint{ .x = 707, .y = 42 }, northeast);

    const hero = projectWorldPoint(render, layout.schematic, render.hero_start.x, render.hero_start.z);
    try std.testing.expectEqual(ScreenPoint{ .x = 684, .y = 465 }, hero);

    const first_zone = projectZoneBounds(render, layout.schematic, render.zones[0]);
    try std.testing.expectEqual(sdl.Rect{ .x = 684, .y = 435, .w = 24, .h = 42 }, first_zone);
}

test "viewer window title carries the canonical room metadata" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    const title = try formatWindowTitleZ(allocator, room);
    defer allocator.free(title);

    try std.testing.expect(std.mem.indexOf(u8, title, "scene=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "background=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "kind=interior") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "loader=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "hero=9724,1024,782") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "cube=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "gri=3(grm=0,bll=1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "grm=149") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "bll=180") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "blocks=105[1|2|3|4|5|7|...]") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "columns=64x64") != null);
}

test "viewer room snapshot rejects exterior scene entries" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(error.ViewerSceneMustBeInterior, loadRoomSnapshot(allocator, resolved, 44, 2));
}
