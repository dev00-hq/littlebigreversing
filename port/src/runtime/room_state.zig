const builtin = @import("builtin");
const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const background_data = @import("../game_data/background.zig");
const scene_data = @import("../game_data/scene.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const track_program = @import("../game_data/scene/track_program.zig");
const world_geometry = @import("world_geometry.zig");

pub const UnsupportedSceneLifeHit = life_audit.UnsupportedSceneLifeHit;

pub const HeroStartSnapshot = struct {
    x: i16,
    y: i16,
    z: i16,
    track_byte_length: u16,
    life_byte_length: u16,
    track_bytes: []u8,
    track_instructions: []scene_data.TrackInstruction,
    life_bytes: []u8,

    pub fn deinit(self: HeroStartSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.track_instructions);
        allocator.free(self.track_bytes);
        allocator.free(self.life_bytes);
    }
};

pub const ObjectPositionSnapshot = struct {
    index: usize,
    x: i32,
    y: i32,
    z: i32,
};

pub const ObjectBehaviorSeedSnapshot = struct {
    index: usize,
    sprite: i16,
    option_flags: i16 = 0,
    bonus_quantity: u8 = 0,
    track_bytes: []u8,
    track_instructions: []track_program.TrackInstruction,
    life_bytes: []u8,
    life_instructions: []life_program.LifeInstruction,

    pub fn deinit(self: ObjectBehaviorSeedSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.track_instructions);
        allocator.free(self.track_bytes);
        allocator.free(self.life_instructions);
        allocator.free(self.life_bytes);
    }
};

pub const TrackPointSnapshot = struct {
    index: usize,
    x: i32,
    y: i32,
    z: i32,
};

pub const ZoneBoundsSnapshot = struct {
    index: usize,
    num: i16 = -1,
    kind: scene_data.ZoneType,
    raw_info: [8]i32,
    semantics: scene_data.ZoneSemantics,
    x0: i32,
    y0: i32,
    z0: i32,
    x1: i32,
    y1: i32,
    z1: i32,
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
    object_behavior_seeds: []ObjectBehaviorSeedSnapshot,
    zones: []ZoneBoundsSnapshot,
    tracks: []TrackPointSnapshot,

    pub fn deinit(self: SceneSnapshot, allocator: std.mem.Allocator) void {
        self.hero_start.deinit(allocator);
        allocator.free(self.objects);
        for (self.object_behavior_seeds) |seed| seed.deinit(allocator);
        allocator.free(self.object_behavior_seeds);
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
    level_occupancy_grid: []u32,
    level_floor_type_grid: []u8,
    level_shape_grid: []u8,
    level_shape_class_grid: []SurfaceShapeClass,
    level_brick_index_grid: []u16,
    tiles: []CompositionTileSnapshot,

    pub fn deinit(self: CompositionSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.height_grid);
        allocator.free(self.level_occupancy_grid);
        allocator.free(self.level_floor_type_grid);
        allocator.free(self.level_shape_grid);
        allocator.free(self.level_shape_class_grid);
        allocator.free(self.level_brick_index_grid);
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

pub const RoomIntelligenceAugmentation = struct {
    composition: CompositionSnapshot,
    fragment_zones: []FragmentZoneSnapshot,

    pub fn deinit(self: RoomIntelligenceAugmentation, allocator: std.mem.Allocator) void {
        self.composition.deinit(allocator);
        for (self.fragment_zones) |zone| zone.deinit(allocator);
        allocator.free(self.fragment_zones);
    }
};

pub const FragmentZoneAxisDiagnostic = struct {
    min_value: i32,
    max_value: i32,
    unit: i32,
    origin_alignment_required: bool,
    origin_aligned: ?bool,
    origin_remainder: ?i32,
    origin_cell: ?usize,
    span_non_negative: bool,
    span_aligned: bool,
    span_remainder: ?i32,
    cell_count: ?usize,
};

pub const FragmentDimensionsSnapshot = struct {
    width: usize,
    height: usize,
    depth: usize,
};

pub const FragmentZoneCompatibilityIssue = enum {
    compatible,
    invalid_fragment_zone_index,
    fragment_zone_index_out_of_range,
    invalid_x_axis_origin,
    invalid_z_axis_origin,
    invalid_x_axis_span,
    invalid_y_axis_span,
    invalid_z_axis_span,
    footprint_mismatch,
};

pub const FragmentZoneCompatibilityDiagnostic = struct {
    zone_index: usize,
    zone_num: i16,
    grm_index: i32,
    initially_on: bool,
    x_axis: FragmentZoneAxisDiagnostic,
    y_axis: FragmentZoneAxisDiagnostic,
    z_axis: FragmentZoneAxisDiagnostic,
    fragment_entry_index: ?usize,
    fragment_dimensions: ?FragmentDimensionsSnapshot,
    issue: FragmentZoneCompatibilityIssue,
};

pub const RoomFragmentZoneDiagnostics = struct {
    scene_entry_index: usize,
    background_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    fragment_count: usize,
    grm_zone_count: usize,
    compatible_zone_count: usize,
    invalid_zone_count: usize,
    first_invalid_zone_index: ?usize,
    zones: []FragmentZoneCompatibilityDiagnostic,

    pub fn deinit(self: RoomFragmentZoneDiagnostics, allocator: std.mem.Allocator) void {
        allocator.free(self.zones);
    }
};

pub const ResolvedRoomEntries = struct {
    scene_entry_index: usize,
    background_entry_index: usize,
};

const WorldPointSnapshot = world_geometry.WorldPointSnapshot;

pub fn heroStartWorldPoint(room: *const RoomSnapshot) WorldPointSnapshot {
    return .{
        .x = room.scene.hero_start.x,
        .y = room.scene.hero_start.y,
        .z = room.scene.hero_start.z,
    };
}

fn copyHeroStartSnapshot(
    allocator: std.mem.Allocator,
    hero_start: scene_data.HeroStart,
) !HeroStartSnapshot {
    const track_bytes = try allocator.dupe(u8, hero_start.track.bytes);
    errdefer allocator.free(track_bytes);
    const track_instructions = try allocator.dupe(scene_data.TrackInstruction, hero_start.track_instructions);
    errdefer allocator.free(track_instructions);
    const life_bytes = try allocator.dupe(u8, hero_start.life.bytes);
    errdefer allocator.free(life_bytes);

    return .{
        .x = hero_start.x,
        .y = hero_start.y,
        .z = hero_start.z,
        .track_byte_length = hero_start.trackByteLength(),
        .life_byte_length = hero_start.lifeByteLength(),
        .track_bytes = track_bytes,
        .track_instructions = track_instructions,
        .life_bytes = life_bytes,
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

pub fn resolveGuardedTransitionRoomEntriesForCube(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    destination_cube: i16,
) !ResolvedRoomEntries {
    if (destination_cube < 0) return error.UnsupportedDestinationCube;

    const cube_index = std.math.cast(usize, destination_cube) orelse return error.UnsupportedDestinationCube;
    const mapping = guardedTransitionRoomEntryForCube(cube_index) orelse return error.UnsupportedDestinationCube;

    var room = loadRoomSnapshot(allocator, resolved, mapping.entries.scene_entry_index, mapping.entries.background_entry_index) catch |err| switch (err) {
        error.ViewerUnsupportedSceneLife,
        error.ViewerSceneMustBeInterior,
        error.InvalidFragmentZoneBounds,
        error.InvalidFragmentZoneIndex,
        error.FragmentZoneIndexOutOfRange,
        error.FragmentZoneFootprintMismatch,
        => return error.UnsupportedDestinationCube,
        else => return err,
    };
    defer room.deinit(allocator);

    const classic_loader_scene_number = room.scene.classic_loader_scene_number orelse return error.UnsupportedDestinationCube;
    if (classic_loader_scene_number != mapping.classic_loader_scene_number) return error.UnsupportedDestinationCube;
    if (room.background.entry_index != mapping.entries.background_entry_index) return error.UnsupportedDestinationCube;

    return mapping.entries;
}

const GuardedTransitionRoomEntryMapping = struct {
    destination_cube: usize,
    entries: ResolvedRoomEntries,
    classic_loader_scene_number: usize,
};

fn guardedTransitionRoomEntryForCube(destination_cube: usize) ?GuardedTransitionRoomEntryMapping {
    const mappings = [_]GuardedTransitionRoomEntryMapping{
        .{
            .destination_cube = 0,
            .entries = .{ .scene_entry_index = 2, .background_entry_index = 0 },
            .classic_loader_scene_number = 0,
        },
        .{
            .destination_cube = 1,
            .entries = .{ .scene_entry_index = 2, .background_entry_index = 1 },
            .classic_loader_scene_number = 0,
        },
        .{
            .destination_cube = 17,
            .entries = .{ .scene_entry_index = 19, .background_entry_index = 19 },
            .classic_loader_scene_number = 17,
        },
        .{
            .destination_cube = 19,
            .entries = .{ .scene_entry_index = 21, .background_entry_index = 19 },
            .classic_loader_scene_number = 19,
        },
        .{
            .destination_cube = 20,
            .entries = .{ .scene_entry_index = 22, .background_entry_index = 20 },
            .classic_loader_scene_number = 20,
        },
        .{
            .destination_cube = 34,
            .entries = .{ .scene_entry_index = 36, .background_entry_index = 36 },
            .classic_loader_scene_number = 34,
        },
    };

    for (mappings) |mapping| {
        if (mapping.destination_cube == destination_cube) return mapping;
    }
    return null;
}

pub fn inspectRoomFragmentZoneDiagnostics(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
) !RoomFragmentZoneDiagnostics {
    const scene_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);

    var scene = try scene_data.loadSceneMetadata(allocator, scene_path, scene_entry_index);
    defer scene.deinit(allocator);

    switch (try life_audit.validateSceneLifeBoundary(scene)) {
        .decoded => {},
        .unsupported_life_blob => return error.ViewerUnsupportedSceneLife,
    }

    if (scene.cube_mode != 0) return error.ViewerSceneMustBeInterior;

    const background_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "LBA_BKG.HQR" });
    defer allocator.free(background_path);

    const background = try background_data.loadBackgroundMetadata(allocator, background_path, background_entry_index);
    defer background.deinit(allocator);

    return inspectRoomFragmentZoneDiagnosticsFromMetadata(allocator, scene, background);
}

pub fn inspectRoomFragmentZoneDiagnosticsFromMetadata(
    allocator: std.mem.Allocator,
    scene: scene_data.SceneMetadata,
    background: background_data.BackgroundMetadata,
) !RoomFragmentZoneDiagnostics {
    switch (try life_audit.validateSceneLifeBoundary(scene)) {
        .decoded => {},
        .unsupported_life_blob => return error.ViewerUnsupportedSceneLife,
    }

    if (scene.cube_mode != 0) return error.ViewerSceneMustBeInterior;

    return buildRoomFragmentZoneDiagnosticsFromMetadataAssumingSupportedScene(allocator, scene, background);
}

pub fn buildRoomFragmentZoneDiagnosticsFromMetadataAssumingSupportedScene(
    allocator: std.mem.Allocator,
    scene: scene_data.SceneMetadata,
    background: background_data.BackgroundMetadata,
) !RoomFragmentZoneDiagnostics {
    const zones = try buildFragmentZoneCompatibilityDiagnostics(allocator, scene.zones, background.composition.fragments);
    errdefer allocator.free(zones);

    var compatible_zone_count: usize = 0;
    var invalid_zone_count: usize = 0;
    var first_invalid_zone_index: ?usize = null;
    for (zones) |zone| {
        if (zone.issue == .compatible) {
            compatible_zone_count += 1;
        } else {
            invalid_zone_count += 1;
            if (first_invalid_zone_index == null) first_invalid_zone_index = zone.zone_index;
        }
    }

    return .{
        .scene_entry_index = scene.entry_index,
        .background_entry_index = background.entry_index,
        .classic_loader_scene_number = scene.classicLoaderSceneNumber(),
        .scene_kind = scene.sceneKind(),
        .fragment_count = background.composition.fragments.fragments.len,
        .grm_zone_count = zones.len,
        .compatible_zone_count = compatible_zone_count,
        .invalid_zone_count = invalid_zone_count,
        .first_invalid_zone_index = first_invalid_zone_index,
        .zones = zones,
    };
}

pub fn buildRoomIntelligenceAugmentation(
    allocator: std.mem.Allocator,
    scene: scene_data.SceneMetadata,
    background: background_data.BackgroundMetadata,
) !RoomIntelligenceAugmentation {
    const composition = try buildCompositionSnapshot(allocator, background.composition);
    errdefer composition.deinit(allocator);

    const fragment_zones = try buildFragmentZoneSnapshots(
        allocator,
        scene.zones,
        background.composition.fragments,
        background.composition.library,
    );
    errdefer {
        for (fragment_zones) |zone| zone.deinit(allocator);
        allocator.free(fragment_zones);
    }

    return .{
        .composition = composition,
        .fragment_zones = fragment_zones,
    };
}

pub fn inspectUnsupportedSceneLifeHit(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
) !UnsupportedSceneLifeHit {
    const scene_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);

    return switch (try life_audit.validateSceneLifeBoundaryForEntry(allocator, scene_path, scene_entry_index)) {
        .unsupported_life_blob => |hit| hit,
        .decoded => error.UnsupportedSceneLifeHitUnavailable,
    };
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
        .hero_start = try copyHeroStartSnapshot(allocator, scene.hero_start),
        .object_count = scene.object_count,
        .zone_count = scene.zone_count,
        .track_count = scene.track_count,
        .patch_count = scene.patch_count,
        .objects = try copyObjectSnapshots(allocator, scene.objects),
        .object_behavior_seeds = try copySupportedObjectBehaviorSeeds(allocator, scene),
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

pub fn buildRenderSnapshot(room: *const RoomSnapshot) RenderSnapshot {
    return buildRenderSnapshotWithHeroPosition(room, heroStartWorldPoint(room));
}

pub fn buildRenderSnapshotWithHeroPosition(
    room: *const RoomSnapshot,
    hero_position: WorldPointSnapshot,
) RenderSnapshot {
    const world_bounds = WorldBounds{
        .min_x = 0,
        .max_x = if (room.background.column_table.width == 0)
            0
        else
            @as(i32, @intCast(room.background.column_table.width * world_grid_span_xz)) - 1,
        .min_z = 0,
        .max_z = if (room.background.column_table.depth == 0)
            0
        else
            @as(i32, @intCast(room.background.column_table.depth * world_grid_span_xz)) - 1,
    };

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

fn copySupportedObjectBehaviorSeeds(
    allocator: std.mem.Allocator,
    scene: scene_data.SceneMetadata,
) ![]ObjectBehaviorSeedSnapshot {
    var seeds: std.ArrayList(ObjectBehaviorSeedSnapshot) = .empty;
    errdefer {
        for (seeds.items) |seed| seed.deinit(allocator);
        seeds.deinit(allocator);
    }

    if (scene.entry_index == 19 or scene.entry_index == 36) {
        try appendObjectBehaviorSeed(allocator, &seeds, scene, 2);
    }

    return seeds.toOwnedSlice(allocator);
}

fn appendObjectBehaviorSeed(
    allocator: std.mem.Allocator,
    seeds: *std.ArrayList(ObjectBehaviorSeedSnapshot),
    scene: scene_data.SceneMetadata,
    object_index: usize,
) !void {
    const object = findSceneObjectByIndex(scene.objects, object_index) orelse return error.MissingSupportedObjectBehaviorSeed;
    const track_bytes = try allocator.dupe(u8, object.track.bytes);
    errdefer allocator.free(track_bytes);
    const track_instructions = try track_program.decodeTrackProgram(allocator, track_bytes);
    errdefer allocator.free(track_instructions);
    const life_bytes = try allocator.dupe(u8, object.life.bytes);
    errdefer allocator.free(life_bytes);
    const life_instructions = try life_program.decodeLifeProgram(allocator, life_bytes);
    errdefer allocator.free(life_instructions);

    try seeds.append(allocator, .{
        .index = object.index,
        .sprite = object.sprite,
        .option_flags = object.option_flags,
        .bonus_quantity = std.math.cast(u8, object.bonus_count) orelse return error.UnsupportedObjectBehaviorBonusQuantityRange,
        .track_bytes = track_bytes,
        .track_instructions = track_instructions,
        .life_bytes = life_bytes,
        .life_instructions = life_instructions,
    });
}

fn findSceneObjectByIndex(
    objects: []const scene_data.SceneObject,
    object_index: usize,
) ?scene_data.SceneObject {
    for (objects) |object| {
        if (object.index == object_index) return object;
    }
    return null;
}

fn copyZoneSnapshots(
    allocator: std.mem.Allocator,
    zones: []const scene_data.SceneZone,
) ![]ZoneBoundsSnapshot {
    const copied = try allocator.alloc(ZoneBoundsSnapshot, zones.len);
    for (zones, copied, 0..) |zone, *slot, index| {
        slot.* = .{
            .index = index,
            .num = zone.num,
            .kind = zone.zone_type,
            .raw_info = zone.raw_info,
            .semantics = zone.semantics,
            .x0 = zone.x0,
            .y0 = zone.y0,
            .z0 = zone.z0,
            .x1 = zone.x1,
            .y1 = zone.y1,
            .z1 = zone.z1,
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

pub fn buildFragmentZoneCompatibilityDiagnostics(
    allocator: std.mem.Allocator,
    zones: []const scene_data.SceneZone,
    fragments: background_data.FragmentLibrary,
) ![]FragmentZoneCompatibilityDiagnostic {
    var copied: std.ArrayList(FragmentZoneCompatibilityDiagnostic) = .empty;
    errdefer copied.deinit(allocator);

    for (zones, 0..) |zone, zone_index| {
        if (zone.zone_type != .grm) continue;

        const semantics = zone.semantics.grm;
        const x_min = @min(zone.x0, zone.x1);
        const x_max = @max(zone.x0, zone.x1);
        const y_min = @min(zone.y0, zone.y1);
        const y_max = @max(zone.y0, zone.y1);
        const z_min = @min(zone.z0, zone.z1);
        const z_max = @max(zone.z0, zone.z1);

        var diagnostic = FragmentZoneCompatibilityDiagnostic{
            .zone_index = zone_index,
            .zone_num = zone.num,
            .grm_index = semantics.grm_index,
            .initially_on = semantics.initially_on,
            .x_axis = describeFragmentZoneAxis(x_min, x_max, world_grid_span_xz, true),
            .y_axis = describeFragmentZoneAxis(y_min, y_max, world_grid_span_y, false),
            .z_axis = describeFragmentZoneAxis(z_min, z_max, world_grid_span_xz, true),
            .fragment_entry_index = null,
            .fragment_dimensions = null,
            .issue = .compatible,
        };

        if (semantics.grm_index < 0) {
            diagnostic.issue = .invalid_fragment_zone_index;
            try copied.append(allocator, diagnostic);
            continue;
        }

        const grm_index: usize = @intCast(semantics.grm_index);
        if (grm_index >= fragments.fragments.len) {
            diagnostic.issue = .fragment_zone_index_out_of_range;
            try copied.append(allocator, diagnostic);
            continue;
        }

        const fragment = fragments.fragments[grm_index];
        diagnostic.fragment_entry_index = fragment.entry_index;
        diagnostic.fragment_dimensions = .{
            .width = fragment.width,
            .height = fragment.height,
            .depth = fragment.depth,
        };

        if (!(diagnostic.x_axis.origin_aligned orelse true)) {
            diagnostic.issue = .invalid_x_axis_origin;
        } else if (!(diagnostic.z_axis.origin_aligned orelse true)) {
            diagnostic.issue = .invalid_z_axis_origin;
        } else if (!diagnostic.x_axis.span_aligned) {
            diagnostic.issue = .invalid_x_axis_span;
        } else if (!diagnostic.y_axis.span_aligned) {
            diagnostic.issue = .invalid_y_axis_span;
        } else if (!diagnostic.z_axis.span_aligned) {
            diagnostic.issue = .invalid_z_axis_span;
        } else if (diagnostic.x_axis.cell_count.? != fragment.width or
            diagnostic.y_axis.cell_count.? != fragment.height or
            diagnostic.z_axis.cell_count.? != fragment.depth)
        {
            diagnostic.issue = .footprint_mismatch;
        }

        try copied.append(allocator, diagnostic);
    }

    return copied.toOwnedSlice(allocator);
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

pub fn buildCompositionSnapshot(
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
    const level_grid_cell_count = grid_cell_count * @as(usize, 25);
    const level_occupancy_grid = try allocator.alloc(u32, grid_cell_count);
    errdefer allocator.free(level_occupancy_grid);
    @memset(level_occupancy_grid, 0);
    const level_floor_type_grid = try allocator.alloc(u8, level_grid_cell_count);
    errdefer allocator.free(level_floor_type_grid);
    @memset(level_floor_type_grid, 0);
    const level_shape_grid = try allocator.alloc(u8, level_grid_cell_count);
    errdefer allocator.free(level_shape_grid);
    @memset(level_shape_grid, 0);
    const level_shape_class_grid = try allocator.alloc(SurfaceShapeClass, level_grid_cell_count);
    errdefer allocator.free(level_shape_class_grid);
    @memset(level_shape_class_grid, .open);
    const level_brick_index_grid = try allocator.alloc(u16, level_grid_cell_count);
    errdefer allocator.free(level_brick_index_grid);
    @memset(level_brick_index_grid, 0);

    var max_total_height: u8 = 0;
    var max_stack_depth: u8 = 0;

    for (composition.grid.cells, 0..) |cell, index| {
        try fillCompositionLevelGrids(
            composition,
            cell,
            index,
            level_occupancy_grid,
            level_floor_type_grid,
            level_shape_grid,
            level_shape_class_grid,
            level_brick_index_grid,
        );
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
        .level_occupancy_grid = level_occupancy_grid,
        .level_floor_type_grid = level_floor_type_grid,
        .level_shape_grid = level_shape_grid,
        .level_shape_class_grid = level_shape_class_grid,
        .level_brick_index_grid = level_brick_index_grid,
        .tiles = try tiles.toOwnedSlice(allocator),
    };
}

fn fillCompositionLevelGrids(
    composition: background_data.BackgroundComposition,
    cell: background_data.GridCell,
    cell_index: usize,
    level_occupancy_grid: []u32,
    level_floor_type_grid: []u8,
    level_shape_grid: []u8,
    level_shape_class_grid: []SurfaceShapeClass,
    level_brick_index_grid: []u16,
) !void {
    var level: usize = 0;
    const spans = composition.grid.spans[cell.span_start .. cell.span_start + cell.span_count];
    for (spans) |span| {
        switch (span.encoding) {
            .empty => {},
            .explicit => {
                for (0..span.height) |span_level| {
                    const block_ref = composition.grid.block_refs[span.block_ref_start + span_level];
                    if (block_ref.layout_index == 0) continue;
                    const block = try resolveCompositionLayoutBlock(composition, block_ref);
                    fillCompositionLevel(
                        cell_index,
                        level + span_level,
                        block,
                        level_occupancy_grid,
                        level_floor_type_grid,
                        level_shape_grid,
                        level_shape_class_grid,
                        level_brick_index_grid,
                    );
                }
            },
            .repeated => {
                const block_ref = composition.grid.block_refs[span.block_ref_start];
                if (block_ref.layout_index != 0) {
                    const block = try resolveCompositionLayoutBlock(composition, block_ref);
                    for (0..span.height) |span_level| {
                        fillCompositionLevel(
                            cell_index,
                            level + span_level,
                            block,
                            level_occupancy_grid,
                            level_floor_type_grid,
                            level_shape_grid,
                            level_shape_class_grid,
                            level_brick_index_grid,
                        );
                    }
                }
            },
        }
        level += span.height;
    }
}

fn fillCompositionLevel(
    cell_index: usize,
    level: usize,
    block: background_data.LayoutBlock,
    level_occupancy_grid: []u32,
    level_floor_type_grid: []u8,
    level_shape_grid: []u8,
    level_shape_class_grid: []SurfaceShapeClass,
    level_brick_index_grid: []u16,
) void {
    const level_index = (cell_index * 25) + level;
    level_occupancy_grid[cell_index] |= @as(u32, 1) << @intCast(level);
    level_floor_type_grid[level_index] = block.floorType();
    level_shape_grid[level_index] = block.shape;
    level_shape_class_grid[level_index] = classifySurfaceShape(block.shape);
    level_brick_index_grid[level_index] = block.brick_index;
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

fn describeFragmentZoneAxis(
    min_value: i32,
    max_value: i32,
    unit: i32,
    origin_alignment_required: bool,
) FragmentZoneAxisDiagnostic {
    const span_non_negative = max_value >= min_value;
    const delta = if (span_non_negative) max_value - min_value else 0;
    const origin_aligned = if (origin_alignment_required)
        min_value >= 0 and @mod(min_value, unit) == 0
    else
        null;
    const origin_remainder = if (origin_alignment_required and min_value >= 0)
        @as(i32, @mod(min_value, unit))
    else
        null;
    const origin_cell = if (origin_alignment_required and origin_aligned.?)
        @as(usize, @intCast(@divTrunc(min_value, unit)))
    else
        null;
    const span_aligned = span_non_negative and @mod(delta, unit) == 0;
    const span_remainder = if (span_non_negative)
        @as(i32, @mod(delta, unit))
    else
        null;
    const cell_count = if (span_aligned)
        @as(usize, @intCast(@divTrunc(delta, unit) + 1))
    else
        null;

    return .{
        .min_value = min_value,
        .max_value = max_value,
        .unit = unit,
        .origin_alignment_required = origin_alignment_required,
        .origin_aligned = origin_aligned,
        .origin_remainder = origin_remainder,
        .origin_cell = origin_cell,
        .span_non_negative = span_non_negative,
        .span_aligned = span_aligned,
        .span_remainder = span_remainder,
        .cell_count = cell_count,
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

test "inspectRoomFragmentZoneDiagnostics explains the 219 219 invalid fragment-zone blocker" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const diagnostics = try inspectRoomFragmentZoneDiagnostics(allocator, resolved, 219, 219);
    defer diagnostics.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 219), diagnostics.scene_entry_index);
    try std.testing.expectEqual(@as(usize, 219), diagnostics.background_entry_index);
    try std.testing.expectEqual(@as(?usize, 217), diagnostics.classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", diagnostics.scene_kind);
    try std.testing.expectEqual(@as(usize, 3), diagnostics.fragment_count);
    try std.testing.expectEqual(@as(usize, 6), diagnostics.grm_zone_count);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.compatible_zone_count);
    try std.testing.expectEqual(@as(usize, 6), diagnostics.invalid_zone_count);
    try std.testing.expectEqual(@as(?usize, 1), diagnostics.first_invalid_zone_index);

    const first = diagnostics.zones[0];
    try std.testing.expectEqual(@as(usize, 1), first.zone_index);
    try std.testing.expectEqual(@as(i16, 0), first.zone_num);
    try std.testing.expectEqual(@as(i32, 0), first.grm_index);
    try std.testing.expectEqual(false, first.initially_on);
    try std.testing.expectEqual(.invalid_z_axis_origin, first.issue);
    try std.testing.expectEqual(@as(?usize, 159), first.fragment_entry_index);
    try std.testing.expect(first.fragment_dimensions != null);
    try std.testing.expectEqual(true, first.x_axis.origin_aligned.?);
    try std.testing.expectEqual(@as(?i32, 0), first.x_axis.origin_remainder);
    try std.testing.expectEqual(@as(?usize, 27), first.x_axis.origin_cell);
    try std.testing.expectEqual(false, first.z_axis.origin_aligned.?);
    try std.testing.expectEqual(@as(?i32, 112), first.z_axis.origin_remainder);
    try std.testing.expectEqual(@as(?usize, null), first.z_axis.origin_cell);

    const third = diagnostics.zones[2];
    try std.testing.expectEqual(@as(usize, 11), third.zone_index);
    try std.testing.expectEqual(@as(i16, 11), third.zone_num);
    try std.testing.expectEqual(@as(i32, 1), third.grm_index);
    try std.testing.expectEqual(.invalid_x_axis_origin, third.issue);
    try std.testing.expectEqual(@as(?usize, 160), third.fragment_entry_index);
    try std.testing.expectEqual(false, third.x_axis.origin_aligned.?);
    try std.testing.expectEqual(@as(?i32, 80), third.x_axis.origin_remainder);
    try std.testing.expectEqual(false, third.z_axis.origin_aligned.?);
    try std.testing.expectEqual(@as(?i32, 320), third.z_axis.origin_remainder);
}

test "resolveGuardedTransitionRoomEntriesForCube keeps the bounded current-state cube mapping explicit" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectEqual(
        ResolvedRoomEntries{ .scene_entry_index = 2, .background_entry_index = 0 },
        try resolveGuardedTransitionRoomEntriesForCube(allocator, resolved, 0),
    );
    try std.testing.expectEqual(
        ResolvedRoomEntries{ .scene_entry_index = 2, .background_entry_index = 1 },
        try resolveGuardedTransitionRoomEntriesForCube(allocator, resolved, 1),
    );
    try std.testing.expectEqual(
        ResolvedRoomEntries{ .scene_entry_index = 19, .background_entry_index = 19 },
        try resolveGuardedTransitionRoomEntriesForCube(allocator, resolved, 17),
    );
    try std.testing.expectEqual(
        ResolvedRoomEntries{ .scene_entry_index = 21, .background_entry_index = 19 },
        try resolveGuardedTransitionRoomEntriesForCube(allocator, resolved, 19),
    );
    try std.testing.expectEqual(
        ResolvedRoomEntries{ .scene_entry_index = 22, .background_entry_index = 20 },
        try resolveGuardedTransitionRoomEntriesForCube(allocator, resolved, 20),
    );
    try std.testing.expectEqual(
        ResolvedRoomEntries{ .scene_entry_index = 36, .background_entry_index = 36 },
        try resolveGuardedTransitionRoomEntriesForCube(allocator, resolved, 34),
    );
    try std.testing.expectError(
        error.UnsupportedDestinationCube,
        resolveGuardedTransitionRoomEntriesForCube(allocator, resolved, 45),
    );
}

test "resolveGuardedTransitionRoomEntriesForCube rejects negative cubes" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(
        error.UnsupportedDestinationCube,
        resolveGuardedTransitionRoomEntriesForCube(allocator, resolved, -1),
    );
}
