const background_data = @import("../game_data/background.zig");
const room_state = @import("room_state.zig");
const world_geometry = @import("world_geometry.zig");

pub const CompositionRenderSnapshot = struct {
    occupied_cell_count: usize,
    occupied_bounds: ?room_state.CompositionBoundsSnapshot,
    floor_type_counts: [16]usize,
    max_total_height: u8,
    max_stack_depth: u8,
    height_grid: []const u8,
    tiles: []const room_state.CompositionTileSnapshot,
};

pub const FragmentRenderSnapshot = struct {
    library: room_state.FragmentLibrarySnapshot,
    zones: []const room_state.FragmentZoneSnapshot,
};

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
    world_bounds: world_geometry.WorldBounds,
    hero_position: world_geometry.WorldPointSnapshot,
    objects: []const room_state.ObjectPositionSnapshot,
    zones: []const room_state.ZoneBoundsSnapshot,
    tracks: []const room_state.TrackPointSnapshot,
    composition: CompositionRenderSnapshot,
    fragments: FragmentRenderSnapshot,
    brick_previews: []const background_data.BrickPreview,
    metadata: Metadata = .{},
};

const world_grid_span_xz = 512;

pub fn buildRenderSnapshot(room: *const room_state.RoomSnapshot) RenderSnapshot {
    return buildRenderSnapshotWithHeroPosition(room, room_state.heroStartWorldPoint(room));
}

pub fn buildRenderSnapshotWithHeroPosition(
    room: *const room_state.RoomSnapshot,
    hero_position: world_geometry.WorldPointSnapshot,
) RenderSnapshot {
    const world_bounds = world_geometry.WorldBounds{
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
