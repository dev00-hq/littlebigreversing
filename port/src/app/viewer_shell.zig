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

pub const CompositionBoundsSnapshot = struct {
    min_x: usize,
    max_x: usize,
    min_z: usize,
    max_z: usize,
};

pub const SurfaceShapeClass = enum(u8) {
    open,
    solid,
    single_stair,
    double_stair_corner,
    double_stair_peak,
    weird,
};

pub const CompositionTileSnapshot = struct {
    x: usize,
    z: usize,
    total_height: u8,
    stack_depth: u8,
    top_floor_type: u8,
    top_shape: u8,
    top_shape_class: SurfaceShapeClass,
};

pub const CompositionSnapshot = struct {
    occupied_cell_count: usize,
    occupied_bounds: ?CompositionBoundsSnapshot,
    floor_type_counts: [16]usize,
    max_total_height: u8,
    max_stack_depth: u8,
    height_grid: []u8,
    tiles: []CompositionTileSnapshot,

    pub fn deinit(self: CompositionSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.height_grid);
        allocator.free(self.tiles);
    }
};

pub const CompositionRenderSnapshot = struct {
    occupied_cell_count: usize,
    occupied_bounds: ?CompositionBoundsSnapshot,
    floor_type_counts: [16]usize,
    max_total_height: u8,
    max_stack_depth: u8,
    height_grid: []const u8,
    tiles: []const CompositionTileSnapshot,
};

pub const BackgroundSnapshot = struct {
    entry_index: usize,
    linkage: BackgroundLinkageSnapshot,
    used_block_ids: []u8,
    column_table: ColumnTableSnapshot,
    composition: CompositionSnapshot,

    pub fn deinit(self: BackgroundSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.used_block_ids);
        self.composition.deinit(allocator);
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
    composition: CompositionRenderSnapshot,
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

    const composition = try buildCompositionSnapshot(allocator, background.composition);

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
        .composition = composition,
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
        .composition = .{
            .occupied_cell_count = room.background.composition.occupied_cell_count,
            .occupied_bounds = room.background.composition.occupied_bounds,
            .floor_type_counts = room.background.composition.floor_type_counts,
            .max_total_height = room.background.composition.max_total_height,
            .max_stack_depth = room.background.composition.max_stack_depth,
            .height_grid = room.background.composition.height_grid,
            .tiles = room.background.composition.tiles,
        },
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
    try drawComposition(canvas, panel, snapshot);
    try drawGrid(canvas, panel, snapshot.grid_width, snapshot.grid_depth);

    for (snapshot.zones) |zone| {
        const rect = projectZoneBounds(snapshot, panel, zone);
        const zone_color = zoneColor(zone.kind);
        try canvas.fillRect(rect, withAlpha(zone_color, 40));
        try canvas.drawRect(rect, zone_color);
    }

    for (snapshot.tracks[0..snapshot.tracks.len -| 1], 0..) |track, index| {
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
    if (room.background.composition.occupied_bounds) |bounds| {
        try writer.print(
            "composition_tiles={d} floor0={d} floor1={d} bounds=x:{d}..{d} z:{d}..{d}\n",
            .{
                room.background.composition.occupied_cell_count,
                room.background.composition.floor_type_counts[0],
                room.background.composition.floor_type_counts[1],
                bounds.min_x,
                bounds.max_x,
                bounds.min_z,
                bounds.max_z,
            },
        );
    } else {
        try writer.print(
            "composition_tiles={d} floor0={d} floor1={d} bounds=none\n",
            .{
                room.background.composition.occupied_cell_count,
                room.background.composition.floor_type_counts[0],
                room.background.composition.floor_type_counts[1],
            },
        );
    }
    try printUsedBlockSummary(writer, room.background.used_block_ids);
}

pub fn formatWindowTitleZ(allocator: std.mem.Allocator, room: RoomSnapshot) ![:0]u8 {
    const used_blocks = try formatUsedBlockSummaryAlloc(allocator, room.background.used_block_ids, 6);
    defer allocator.free(used_blocks);

    const title = try std.fmt.allocPrint(
        allocator,
        "Little Big Adventure 2 viewer scene={d} background={d} kind={s} loader={any} hero={d},{d},{d} objects={d} zones={d} tracks={d} cube={d} gri={d}(grm={d},bll={d}) grm={d} bll={d} blocks={s} columns={d}x{d} comp={d}",
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
            room.background.composition.occupied_cell_count,
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

fn buildCompositionSnapshot(
    allocator: std.mem.Allocator,
    composition: background_data.BackgroundComposition,
) !CompositionSnapshot {
    var tiles: std.ArrayList(CompositionTileSnapshot) = .empty;
    errdefer tiles.deinit(allocator);

    var floor_type_counts: [16]usize = [_]usize{0} ** 16;
    const grid_cell_count = composition.grid.width * composition.grid.depth;
    const height_grid = try allocator.alloc(u8, grid_cell_count);
    errdefer allocator.free(height_grid);
    @memset(height_grid, 0);

    var max_total_height: u8 = 0;
    var max_stack_depth: u8 = 0;

    for (composition.grid.cells, 0..) |cell, index| {
        if (cell.non_empty_block_ref_count == 0) continue;
        if (cell.total_height > std.math.maxInt(u8)) return error.InvalidCompositionCell;
        if (cell.non_empty_block_ref_count > std.math.maxInt(u8)) return error.InvalidCompositionCell;

        const top_ref_index = cell.last_non_empty_block_ref_index orelse return error.InvalidCompositionCell;
        const block = try resolveCompositionLayoutBlock(composition, composition.grid.block_refs[top_ref_index]);
        const floor_type = block.floorType();
        const total_height: u8 = @intCast(cell.total_height);
        const stack_depth: u8 = @intCast(cell.non_empty_block_ref_count);
        height_grid[index] = total_height;
        max_total_height = @max(max_total_height, total_height);
        max_stack_depth = @max(max_stack_depth, stack_depth);
        floor_type_counts[floor_type] += 1;

        try tiles.append(allocator, .{
            .x = index % composition.grid.width,
            .z = index / composition.grid.width,
            .total_height = total_height,
            .stack_depth = stack_depth,
            .top_floor_type = floor_type,
            .top_shape = block.shape,
            .top_shape_class = classifySurfaceShape(block.shape),
        });
    }

    return .{
        .occupied_cell_count = composition.grid.referenced_cell_count,
        .occupied_bounds = if (composition.grid.reference_bounds) |bounds|
            .{
                .min_x = bounds.min_x,
                .max_x = bounds.max_x,
                .min_z = bounds.min_z,
                .max_z = bounds.max_z,
            }
        else
            null,
        .floor_type_counts = floor_type_counts,
        .max_total_height = max_total_height,
        .max_stack_depth = max_stack_depth,
        .height_grid = height_grid,
        .tiles = try tiles.toOwnedSlice(allocator),
    };
}

fn resolveCompositionLayoutBlock(
    composition: background_data.BackgroundComposition,
    block_ref: background_data.ColumnBlockRef,
) !background_data.LayoutBlock {
    if (block_ref.layout_index == 0) return error.InvalidCompositionCell;
    if (block_ref.layout_index > composition.library.layouts.len) return error.InvalidCompositionLayoutReference;

    const layout = composition.library.layouts[block_ref.layout_index - 1];
    if (block_ref.layout_block_index >= layout.block_count) return error.InvalidCompositionLayoutBlockReference;

    return composition.library.layout_blocks[layout.block_start + block_ref.layout_block_index];
}

fn classifySurfaceShape(shape: u8) SurfaceShapeClass {
    return switch (shape) {
        0 => .open,
        1 => .solid,
        2...5 => .single_stair,
        6...9 => .double_stair_corner,
        0x0A...0x0D => .double_stair_peak,
        else => .weird,
    };
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

fn drawComposition(canvas: *sdl.Canvas, rect: sdl.Rect, snapshot: RenderSnapshot) !void {
    for (snapshot.composition.tiles) |tile| {
        const tile_rect = projectGridCellRect(rect, snapshot.grid_width, snapshot.grid_depth, tile.x, tile.z);
        try drawCompositionTile(canvas, snapshot, tile_rect, tile);
    }
}

const TileRelief = struct {
    top_surface: sdl.Rect,
    right_wall: sdl.Rect,
    bottom_wall: sdl.Rect,
    inset_depth: i32,
};

fn drawCompositionTile(
    canvas: *sdl.Canvas,
    snapshot: RenderSnapshot,
    tile_rect: sdl.Rect,
    tile: CompositionTileSnapshot,
) !void {
    const relief = computeTileRelief(tile_rect, tile.total_height, snapshot.composition.max_total_height);
    const base_color = compositionTileColor(tile);
    const side_color = darkenColor(base_color, 28);
    const right_wall_color = darkenColor(base_color, 54);
    const bottom_wall_color = darkenColor(base_color, 42);
    const contour_color = withAlpha(lightenColor(base_color, 26), 236);

    try canvas.fillRect(tile_rect, side_color);
    if (relief.right_wall.w > 0 and relief.right_wall.h > 0) {
        try canvas.fillRect(relief.right_wall, right_wall_color);
    }
    if (relief.bottom_wall.w > 0 and relief.bottom_wall.h > 0) {
        try canvas.fillRect(relief.bottom_wall, bottom_wall_color);
    }
    try canvas.fillRect(relief.top_surface, base_color);

    const north_height = if (tile.z == 0)
        @as(u8, 0)
    else
        compositionHeightAt(snapshot, tile.x, tile.z - 1);
    const west_height = if (tile.x == 0)
        @as(u8, 0)
    else
        compositionHeightAt(snapshot, tile.x - 1, tile.z);

    try drawCompositionContour(
        canvas,
        relief.top_surface,
        .north,
        contourThickness(tile.total_height -| north_height),
        contour_color,
    );
    try drawCompositionContour(
        canvas,
        relief.top_surface,
        .west,
        contourThickness(tile.total_height -| west_height),
        contour_color,
    );
    try canvas.drawRect(relief.top_surface, withAlpha(lightenColor(base_color, 18), 212));
    try drawSurfaceMarker(canvas, relief.top_surface, tile, withAlpha(lightenColor(base_color, 64), 232));
}

fn computeTileRelief(tile_rect: sdl.Rect, total_height: u8, max_total_height: u8) TileRelief {
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

fn projectGridCellRect(rect: sdl.Rect, width: usize, depth: usize, x: usize, z: usize) sdl.Rect {
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

fn compositionTileColor(tile: CompositionTileSnapshot) sdl.Color {
    const height_boost: u8 = @intCast(@min(@as(usize, 72), (@as(usize, tile.total_height) * 2) + @as(usize, tile.stack_depth)));
    const depth_boost: u8 = @intCast(@min(@as(usize, 56), @as(usize, tile.stack_depth) * 3));
    return switch (tile.top_floor_type) {
        1, 0x0F => .{
            .r = 24,
            .g = saturatingAdd(92, depth_boost / 3),
            .b = saturatingAdd(140, height_boost),
            .a = 188,
        },
        0x09, 0x0D => .{
            .r = saturatingAdd(166, height_boost),
            .g = saturatingAdd(82, depth_boost / 3),
            .b = 44,
            .a = 196,
        },
        0x0B, 0x0E => .{
            .r = saturatingAdd(78, depth_boost / 2),
            .g = saturatingAdd(140, height_boost),
            .b = saturatingAdd(84, depth_boost / 3),
            .a = 192,
        },
        0x03...0x06 => .{
            .r = saturatingAdd(110, height_boost / 2),
            .g = saturatingAdd(112, depth_boost / 3),
            .b = saturatingAdd(54, depth_boost / 4),
            .a = 188,
        },
        8 => .{
            .r = saturatingAdd(92, depth_boost / 3),
            .g = saturatingAdd(132, height_boost),
            .b = 66,
            .a = 188,
        },
        else => switch (tile.top_shape_class) {
            .solid => .{
                .r = saturatingAdd(76, height_boost / 2),
                .g = saturatingAdd(100, depth_boost / 3),
                .b = saturatingAdd(112, depth_boost / 4),
                .a = 184,
            },
            .single_stair => .{
                .r = saturatingAdd(132, height_boost / 2),
                .g = saturatingAdd(108, depth_boost / 4),
                .b = 84,
                .a = 188,
            },
            .double_stair_corner => .{
                .r = saturatingAdd(120, height_boost / 2),
                .g = saturatingAdd(94, depth_boost / 4),
                .b = 74,
                .a = 188,
            },
            .double_stair_peak => .{
                .r = saturatingAdd(116, height_boost / 3),
                .g = saturatingAdd(118, depth_boost / 3),
                .b = 78,
                .a = 188,
            },
            .open => .{
                .r = 46,
                .g = 58,
                .b = saturatingAdd(72, depth_boost / 4),
                .a = 172,
            },
            else => .{
                .r = saturatingAdd(126, height_boost / 2),
                .g = saturatingAdd(96, depth_boost / 4),
                .b = 62,
                .a = 188,
            },
        },
    };
}

const ContourEdge = enum {
    north,
    west,
};

fn drawCompositionContour(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    edge: ContourEdge,
    thickness: i32,
    color: sdl.Color,
) !void {
    if (thickness <= 0) return;

    switch (edge) {
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

fn contourThickness(height_delta: u8) i32 {
    if (height_delta == 0) return 0;
    return std.math.clamp(1 + @divTrunc(@as(i32, height_delta) - 1, 4), 1, 3);
}

fn compositionHeightAt(snapshot: RenderSnapshot, x: usize, z: usize) u8 {
    if (x >= snapshot.grid_width or z >= snapshot.grid_depth) return 0;
    return snapshot.composition.height_grid[(z * snapshot.grid_width) + x];
}

fn drawSurfaceMarker(
    canvas: *sdl.Canvas,
    rect: sdl.Rect,
    tile: CompositionTileSnapshot,
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

const Facing = enum {
    top,
    bottom,
    left,
    right,
};

fn shapeFacing(shape: u8) ?Facing {
    return switch (shape) {
        6, 0x0A => .top,
        7, 0x0B => .bottom,
        8, 0x0C => .left,
        9, 0x0D => .right,
        else => null,
    };
}

fn lightenColor(color: sdl.Color, amount: u8) sdl.Color {
    return .{
        .r = saturatingAdd(color.r, amount),
        .g = saturatingAdd(color.g, amount),
        .b = saturatingAdd(color.b, amount),
        .a = color.a,
    };
}

fn darkenColor(color: sdl.Color, amount: u8) sdl.Color {
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

fn findCompositionTile(tiles: []const CompositionTileSnapshot, x: usize, z: usize) ?CompositionTileSnapshot {
    for (tiles) |tile| {
        if (tile.x == x and tile.z == z) return tile;
    }
    return null;
}

fn sumFloorTypeCounts(counts: [16]usize) usize {
    var total: usize = 0;
    for (counts) |count| total += count;
    return total;
}

test "viewer shape classifier stays aligned with the checked-in layout docs" {
    try std.testing.expectEqual(SurfaceShapeClass.open, classifySurfaceShape(0));
    try std.testing.expectEqual(SurfaceShapeClass.solid, classifySurfaceShape(1));
    try std.testing.expectEqual(SurfaceShapeClass.single_stair, classifySurfaceShape(2));
    try std.testing.expectEqual(SurfaceShapeClass.single_stair, classifySurfaceShape(5));
    try std.testing.expectEqual(SurfaceShapeClass.double_stair_corner, classifySurfaceShape(6));
    try std.testing.expectEqual(SurfaceShapeClass.double_stair_corner, classifySurfaceShape(9));
    try std.testing.expectEqual(SurfaceShapeClass.double_stair_peak, classifySurfaceShape(0x0A));
    try std.testing.expectEqual(SurfaceShapeClass.double_stair_peak, classifySurfaceShape(0x0D));
    try std.testing.expectEqual(SurfaceShapeClass.weird, classifySurfaceShape(0x0E));
}

test "viewer tile relief thickens with taller composition cells" {
    const tile_rect = sdl.Rect{ .x = 40, .y = 80, .w = 12, .h = 12 };
    const short_relief = computeTileRelief(tile_rect, 3, 25);
    const tall_relief = computeTileRelief(tile_rect, 18, 25);

    try std.testing.expect(short_relief.inset_depth < tall_relief.inset_depth);
    try std.testing.expectEqual(tile_rect.x, tall_relief.top_surface.x);
    try std.testing.expectEqual(tile_rect.y, tall_relief.top_surface.y);
    try std.testing.expect(tall_relief.right_wall.w > 0);
    try std.testing.expect(tall_relief.bottom_wall.h > 0);
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
    try std.testing.expectEqual(@as(usize, 2252), room.background.composition.occupied_cell_count);
    try std.testing.expectEqual(@as(?CompositionBoundsSnapshot, .{
        .min_x = 0,
        .max_x = 63,
        .min_z = 12,
        .max_z = 63,
    }), room.background.composition.occupied_bounds);
    try std.testing.expectEqual(@as(usize, 2252), sumFloorTypeCounts(room.background.composition.floor_type_counts));
    try std.testing.expect(room.background.composition.floor_type_counts[1] > 0);
    try std.testing.expectEqual(@as(usize, 4096), room.background.composition.height_grid.len);
    try std.testing.expect(room.background.composition.max_total_height >= room.background.composition.max_stack_depth);
    try std.testing.expectEqual(@as(usize, 2252), room.background.composition.tiles.len);

    const first_tile = room.background.composition.tiles[0];
    try std.testing.expectEqual(CompositionTileSnapshot{
        .x = 59,
        .z = 12,
        .total_height = first_tile.total_height,
        .stack_depth = 14,
        .top_floor_type = 0,
        .top_shape = 1,
        .top_shape_class = .solid,
    }, first_tile);
    try std.testing.expect(room.background.composition.height_grid[12 * 64 + 59] >= first_tile.stack_depth);

    const water_tile = findCompositionTile(room.background.composition.tiles, 60, 13).?;
    try std.testing.expectEqual(@as(u8, 1), water_tile.stack_depth);
    try std.testing.expectEqual(@as(u8, 1), water_tile.top_floor_type);
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
    try std.testing.expectEqual(@as(usize, 2252), render.composition.occupied_cell_count);
    try std.testing.expectEqual(@as(usize, 2252), sumFloorTypeCounts(render.composition.floor_type_counts));
    try std.testing.expect(render.composition.floor_type_counts[1] > 0);
    try std.testing.expectEqual(@as(usize, 4096), render.composition.height_grid.len);
    try std.testing.expect(render.composition.max_total_height >= render.composition.max_stack_depth);
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

    const first_tile_rect = projectGridCellRect(layout.schematic.inset(10), render.grid_width, render.grid_depth, 59, 12);
    try std.testing.expectEqual(@as(i32, 663), first_tile_rect.x);
    try std.testing.expectEqual(@as(i32, 134), first_tile_rect.y);
    try std.testing.expect(first_tile_rect.w >= 6);
    try std.testing.expect(first_tile_rect.h >= 6);

    const first_tile = findCompositionTile(render.composition.tiles, 59, 12).?;
    const low_relief = computeTileRelief(first_tile_rect, first_tile.stack_depth, render.composition.max_stack_depth);
    const high_relief = computeTileRelief(first_tile_rect, first_tile.total_height, render.composition.max_total_height);
    try std.testing.expect(high_relief.top_surface.w <= low_relief.top_surface.w);
    try std.testing.expect(high_relief.top_surface.h <= low_relief.top_surface.h);
    try std.testing.expectEqual(first_tile_rect.x, high_relief.top_surface.x);
    try std.testing.expectEqual(first_tile_rect.y, high_relief.top_surface.y);
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
    try std.testing.expect(std.mem.indexOf(u8, title, "comp=2252") != null);
}

test "viewer room snapshot rejects exterior scene entries" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(error.ViewerSceneMustBeInterior, loadRoomSnapshot(allocator, resolved, 44, 2));
}
