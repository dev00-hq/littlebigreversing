const builtin = @import("builtin");
const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const background_data = @import("../game_data/background.zig");
const scene_data = @import("../game_data/scene.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");
const world_geometry = @import("world_geometry.zig");

pub const HeroStartSnapshot = struct {
    x: i16,
    y: i16,
    z: i16,
    track_byte_length: u16,
    life_byte_length: u16,
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
    patch_count: usize,
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
    top_brick_index: u16,
};

pub const CompositionSnapshot = struct {
    occupied_cell_count: usize,
    occupied_bounds: ?CompositionBoundsSnapshot,
    layout_count: usize,
    max_layout_block_count: usize,
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

pub const FragmentLibrarySnapshot = struct {
    fragment_count: usize,
    footprint_cell_count: usize,
    non_empty_cell_count: usize,
    max_height: u8,
};

pub const FragmentZoneCellSnapshot = struct {
    x: usize,
    z: usize,
    has_non_empty: bool,
    stack_depth: u8,
    top_floor_type: u8,
    top_shape: u8,
    top_shape_class: SurfaceShapeClass,
    top_brick_index: u16,
};

pub const FragmentZoneSnapshot = struct {
    zone_index: usize,
    zone_num: i16,
    grm_index: usize,
    fragment_entry_index: usize,
    initially_on: bool,
    y_min: i32,
    y_max: i32,
    origin_x: usize,
    origin_z: usize,
    width: usize,
    height: u8,
    depth: usize,
    footprint_cell_count: usize,
    non_empty_cell_count: usize,
    cells: []FragmentZoneCellSnapshot,

    pub fn deinit(self: FragmentZoneSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
    }
};

pub const FragmentRenderSnapshot = struct {
    library: FragmentLibrarySnapshot,
    zones: []const FragmentZoneSnapshot,
};

pub const BackgroundSnapshot = struct {
    entry_index: usize,
    linkage: BackgroundLinkageSnapshot,
    used_block_ids: []u8,
    column_table: ColumnTableSnapshot,
    composition: CompositionSnapshot,
    fragments: FragmentLibrarySnapshot,
    bricks: background_data.BrickPreviewLibrary,

    pub fn deinit(self: BackgroundSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.used_block_ids);
        self.composition.deinit(allocator);
        self.bricks.deinit(allocator);
    }
};

pub const RoomSnapshot = struct {
    scene: SceneSnapshot,
    background: BackgroundSnapshot,
    fragment_zones: []FragmentZoneSnapshot,

    pub fn deinit(self: RoomSnapshot, allocator: std.mem.Allocator) void {
        self.scene.deinit(allocator);
        self.background.deinit(allocator);
        for (self.fragment_zones) |zone| zone.deinit(allocator);
        allocator.free(self.fragment_zones);
    }
};

const WorldPointSnapshot = world_geometry.WorldPointSnapshot;

pub fn heroStartWorldPoint(room: *const RoomSnapshot) WorldPointSnapshot {
    return .{
        .x = room.scene.hero_start.x,
        .y = room.scene.hero_start.y,
        .z = room.scene.hero_start.z,
    };
}

const WorldBounds = world_geometry.WorldBounds;

pub const RenderSnapshot = struct {
    pub const Metadata = struct {
        scene_entry_index: usize = 0,
        background_entry_index: usize = 0,
        classic_loader_scene_number: ?usize = null,
        scene_kind: []const u8 = "",
        object_count: usize = 0,
        zone_count: usize = 0,
        track_count: usize = 0,
        gri_entry_index: usize = 0,
        grm_entry_index: usize = 0,
        owned_fragment_count: usize = 0,
        fragment_zone_count: usize = 0,
        fragment_footprint_cell_count: usize = 0,
        fragment_non_empty_cell_count: usize = 0,
    };

    grid_width: usize,
    grid_depth: usize,
    world_bounds: WorldBounds,
    hero_position: WorldPointSnapshot,
    objects: []const ObjectPositionSnapshot,
    zones: []const ZoneBoundsSnapshot,
    tracks: []const TrackPointSnapshot,
    composition: CompositionRenderSnapshot,
    fragments: FragmentRenderSnapshot,
    brick_previews: []const background_data.BrickPreview,
    metadata: Metadata = .{},
};

const world_grid_span_xz = 512;
const world_grid_span_y = 256;
const LifeValidationMode = enum {
    enforce,
    skip,
};

pub fn loadRoomSnapshot(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
) !RoomSnapshot {
    return loadRoomSnapshotInternal(allocator, resolved, scene_entry_index, background_entry_index, .enforce);
}

pub fn loadRoomSnapshotUncheckedForTests(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
) !RoomSnapshot {
    if (!builtin.is_test) @compileError("loadRoomSnapshotUncheckedForTests is only available in test builds");
    return loadRoomSnapshotInternal(allocator, resolved, scene_entry_index, background_entry_index, .skip);
}

fn loadRoomSnapshotInternal(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
    life_validation_mode: LifeValidationMode,
) !RoomSnapshot {
    const scene_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);

    var scene = try scene_data.loadSceneMetadata(allocator, scene_path, scene_entry_index);
    defer scene.deinit(allocator);

    if (life_validation_mode == .enforce) {
        switch (try life_audit.validateSceneLifeBoundary(scene)) {
            .decoded => {},
            .unsupported_life_blob => return error.ViewerUnsupportedSceneLife,
        }
    }

    if (scene.cube_mode != 0) return error.ViewerSceneMustBeInterior;

    var scene_snapshot = SceneSnapshot{
        .entry_index = scene.entry_index,
        .classic_loader_scene_number = scene.classicLoaderSceneNumber(),
        .scene_kind = scene.sceneKind(),
        .hero_start = .{
            .x = scene.hero_start.x,
            .y = scene.hero_start.y,
            .z = scene.hero_start.z,
            .track_byte_length = scene.hero_start.trackByteLength(),
            .life_byte_length = scene.hero_start.lifeByteLength(),
        },
        .object_count = scene.object_count,
        .zone_count = scene.zone_count,
        .track_count = scene.track_count,
        .patch_count = scene.patch_count,
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
    errdefer composition.deinit(allocator);
    const fragment_zones = try buildFragmentZoneSnapshots(allocator, scene.zones, background.composition.fragments, background.composition.library);
    errdefer {
        for (fragment_zones) |zone| zone.deinit(allocator);
        allocator.free(fragment_zones);
    }

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
        .fragments = .{
            .fragment_count = background.composition.fragments.fragments.len,
            .footprint_cell_count = background.composition.fragments.footprint_cell_count,
            .non_empty_cell_count = background.composition.fragments.non_empty_cell_count,
            .max_height = background.composition.fragments.max_height,
        },
        .bricks = try copyBrickPreviewLibrary(allocator, background.composition.bricks),
    };
    errdefer background_snapshot.deinit(allocator);

    return .{
        .scene = scene_snapshot,
        .background = background_snapshot,
        .fragment_zones = fragment_zones,
    };
}

pub fn buildRenderSnapshot(room: RoomSnapshot) RenderSnapshot {
    return buildRenderSnapshotWithHeroPosition(room, heroStartWorldPoint(&room));
}

pub fn buildRenderSnapshotWithHeroPosition(
    room: RoomSnapshot,
    hero_position: WorldPointSnapshot,
) RenderSnapshot {
    var world_bounds = WorldBounds.init(hero_position.x, hero_position.z);
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
        .hero_position = hero_position,
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
        .fragments = .{
            .library = room.background.fragments,
            .zones = room.fragment_zones,
        },
        .brick_previews = room.background.bricks.previews,
        .metadata = .{
            .scene_entry_index = room.scene.entry_index,
            .background_entry_index = room.background.entry_index,
            .classic_loader_scene_number = room.scene.classic_loader_scene_number,
            .scene_kind = room.scene.scene_kind,
            .object_count = room.scene.objects.len,
            .zone_count = room.scene.zones.len,
            .track_count = room.scene.tracks.len,
            .gri_entry_index = room.background.linkage.gri_entry_index,
            .grm_entry_index = room.background.linkage.grm_entry_index,
            .owned_fragment_count = room.background.fragments.fragment_count,
            .fragment_zone_count = room.fragment_zones.len,
            .fragment_footprint_cell_count = room.background.fragments.footprint_cell_count,
            .fragment_non_empty_cell_count = room.background.fragments.non_empty_cell_count,
        },
    };
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

fn copyBrickPreviewLibrary(
    allocator: std.mem.Allocator,
    library: background_data.BrickPreviewLibrary,
) !background_data.BrickPreviewLibrary {
    return .{
        .palette_entry_index = library.palette_entry_index,
        .previews = try allocator.dupe(background_data.BrickPreview, library.previews),
        .max_preview_width = library.max_preview_width,
        .max_preview_height = library.max_preview_height,
        .total_opaque_pixel_count = library.total_opaque_pixel_count,
    };
}

pub fn buildFragmentZoneSnapshots(
    allocator: std.mem.Allocator,
    zones: []const scene_data.SceneZone,
    fragments: background_data.FragmentLibrary,
    library: background_data.LayoutLibrary,
) ![]FragmentZoneSnapshot {
    var copied: std.ArrayList(FragmentZoneSnapshot) = .empty;
    errdefer {
        for (copied.items) |zone| zone.deinit(allocator);
        copied.deinit(allocator);
    }

    for (zones, 0..) |zone, zone_index| {
        if (zone.zone_type != .grm) continue;

        const semantics = zone.semantics.grm;
        if (semantics.grm_index < 0) return error.InvalidFragmentZoneIndex;
        const grm_index: usize = @intCast(semantics.grm_index);
        if (grm_index >= fragments.fragments.len) return error.FragmentZoneIndexOutOfRange;

        const fragment = fragments.fragments[grm_index];
        const x_min = @min(zone.x0, zone.x1);
        const x_max = @max(zone.x0, zone.x1);
        const y_min = @min(zone.y0, zone.y1);
        const y_max = @max(zone.y0, zone.y1);
        const z_min = @min(zone.z0, zone.z1);
        const z_max = @max(zone.z0, zone.z1);
        const origin_x = try zoneAxisOrigin(x_min, world_grid_span_xz);
        const origin_z = try zoneAxisOrigin(z_min, world_grid_span_xz);
        const zone_width = try fragmentZoneAxisCellCount(x_min, x_max, world_grid_span_xz);
        const zone_height = try fragmentZoneAxisCellCount(y_min, y_max, world_grid_span_y);
        const zone_depth = try fragmentZoneAxisCellCount(z_min, z_max, world_grid_span_xz);

        if (zone_width != @as(usize, fragment.width) or zone_height != @as(usize, fragment.height) or zone_depth != @as(usize, fragment.depth)) {
            return error.FragmentZoneFootprintMismatch;
        }

        const cells = try allocator.alloc(FragmentZoneCellSnapshot, fragment.cells.len);
        errdefer allocator.free(cells);
        for (fragment.cells, cells) |fragment_cell, *slot| {
            if (fragment_cell.non_empty_block_ref_count > 0) {
                if (fragment_cell.non_empty_block_ref_count > std.math.maxInt(u8)) return error.InvalidFragmentZoneCell;
                const top_ref_index = fragment_cell.last_non_empty_block_ref_index orelse return error.InvalidFragmentZoneCell;
                const block = try resolveLayoutBlock(library, fragment.block_refs[top_ref_index]);
                slot.* = .{
                    .x = origin_x + fragment_cell.x,
                    .z = origin_z + fragment_cell.z,
                    .has_non_empty = true,
                    .stack_depth = @intCast(fragment_cell.non_empty_block_ref_count),
                    .top_floor_type = block.floorType(),
                    .top_shape = block.shape,
                    .top_shape_class = classifySurfaceShape(block.shape),
                    .top_brick_index = block.brick_index,
                };
            } else {
                slot.* = .{
                    .x = origin_x + fragment_cell.x,
                    .z = origin_z + fragment_cell.z,
                    .has_non_empty = false,
                    .stack_depth = 0,
                    .top_floor_type = 0,
                    .top_shape = 0,
                    .top_shape_class = .open,
                    .top_brick_index = 0,
                };
            }
        }

        try copied.append(allocator, .{
            .zone_index = zone_index,
            .zone_num = zone.num,
            .grm_index = grm_index,
            .fragment_entry_index = fragment.entry_index,
            .initially_on = semantics.initially_on,
            .y_min = y_min,
            .y_max = y_max,
            .origin_x = origin_x,
            .origin_z = origin_z,
            .width = zone_width,
            .height = fragment.height,
            .depth = zone_depth,
            .footprint_cell_count = fragment.footprint_cell_count,
            .non_empty_cell_count = fragment.non_empty_cell_count,
            .cells = cells,
        });
    }

    return copied.toOwnedSlice(allocator);
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
            .top_brick_index = block.brick_index,
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
        .layout_count = composition.library.layouts.len,
        .max_layout_block_count = composition.library.max_layout_block_count,
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
    return resolveLayoutBlock(composition.library, block_ref);
}

fn resolveLayoutBlock(
    library: background_data.LayoutLibrary,
    block_ref: background_data.ColumnBlockRef,
) !background_data.LayoutBlock {
    if (block_ref.layout_index == 0) return error.InvalidCompositionCell;
    if (block_ref.layout_index > library.layouts.len) return error.InvalidCompositionLayoutReference;

    const layout = library.layouts[block_ref.layout_index - 1];
    if (block_ref.layout_block_index >= layout.block_count) return error.InvalidCompositionLayoutBlockReference;

    return library.layout_blocks[layout.block_start + block_ref.layout_block_index];
}

pub fn classifySurfaceShape(shape: u8) SurfaceShapeClass {
    return switch (shape) {
        0 => .open,
        1 => .solid,
        2...5 => .single_stair,
        6...9 => .double_stair_corner,
        0x0A...0x0D => .double_stair_peak,
        else => .weird,
    };
}

fn zoneAxisOrigin(min_value: i32, unit: i32) !usize {
    if (min_value < 0) return error.InvalidFragmentZoneBounds;
    if (@mod(min_value, unit) != 0) return error.InvalidFragmentZoneBounds;
    return @intCast(@divTrunc(min_value, unit));
}

fn fragmentZoneAxisCellCount(min_value: i32, max_value: i32, unit: i32) !usize {
    if (max_value < min_value) return error.InvalidFragmentZoneBounds;
    const delta = max_value - min_value;
    if (@mod(delta, unit) != 0) return error.InvalidFragmentZoneBounds;
    return @intCast(@divTrunc(delta, unit) + 1);
}
