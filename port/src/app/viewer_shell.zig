const std = @import("std");
const diagnostics = @import("../foundation/diagnostics.zig");
const paths_mod = @import("../foundation/paths.zig");
const sdl = @import("../platform/sdl.zig");
const runtime_session = @import("../runtime/session.zig");
const runtime_query = @import("../runtime/world_query.zig");
const world_geometry = @import("../runtime/world_geometry.zig");
const render = @import("viewer/render.zig");
const state = @import("../runtime/room_state.zig");
const layout = @import("viewer/layout.zig");
const fragment_compare = @import("viewer/fragment_compare.zig");

pub const window_width: i32 = 1440;
pub const window_height: i32 = 900;

pub const ParsedArgs = struct {
    asset_root_override: ?[]u8,
    scene_entry: usize,
    background_entry: usize,

    pub fn deinit(self: ParsedArgs, allocator: std.mem.Allocator) void {
        if (self.asset_root_override) |value| allocator.free(value);
    }
};

pub const HeroStartSnapshot = state.HeroStartSnapshot;
pub const ObjectPositionSnapshot = state.ObjectPositionSnapshot;
pub const TrackPointSnapshot = state.TrackPointSnapshot;
pub const ZoneBoundsSnapshot = state.ZoneBoundsSnapshot;
pub const SceneSnapshot = state.SceneSnapshot;
pub const BackgroundLinkageSnapshot = state.BackgroundLinkageSnapshot;
pub const ColumnTableSnapshot = state.ColumnTableSnapshot;
pub const CompositionBoundsSnapshot = state.CompositionBoundsSnapshot;
pub const SurfaceShapeClass = state.SurfaceShapeClass;
pub const CompositionTileSnapshot = state.CompositionTileSnapshot;
pub const CompositionSnapshot = state.CompositionSnapshot;
pub const CompositionRenderSnapshot = state.CompositionRenderSnapshot;
pub const FragmentLibrarySnapshot = state.FragmentLibrarySnapshot;
pub const FragmentZoneCellSnapshot = state.FragmentZoneCellSnapshot;
pub const FragmentZoneSnapshot = state.FragmentZoneSnapshot;
pub const FragmentRenderSnapshot = state.FragmentRenderSnapshot;
pub const BackgroundSnapshot = state.BackgroundSnapshot;
pub const RoomSnapshot = state.RoomSnapshot;
pub const WorldPointSnapshot = world_geometry.WorldPointSnapshot;
pub const WorldBounds = world_geometry.WorldBounds;
pub const GridCell = world_geometry.GridCell;
pub const CardinalDirection = world_geometry.CardinalDirection;
pub const RenderSnapshot = state.RenderSnapshot;
pub const Session = runtime_session.Session;
pub const FrameUpdate = runtime_session.FrameUpdate;
pub const HeroWorldDelta = runtime_session.HeroWorldDelta;
pub const DebugLayout = layout.DebugLayout;
pub const FragmentComparisonCatalog = fragment_compare.FragmentComparisonCatalog;
pub const FragmentComparisonEntry = fragment_compare.FragmentComparisonEntry;
pub const FragmentComparisonPanel = fragment_compare.FragmentComparisonPanel;
pub const FragmentComparisonSelection = fragment_compare.FragmentComparisonSelection;
pub const SchematicLayout = layout.SchematicLayout;
pub const ScreenPoint = layout.ScreenPoint;
pub const ViewerLocomotionStepStatus = enum {
    moved,
    origin_invalid,
    target_rejected,
};
pub const ViewerLocomotionStepAttempt = struct {
    status: ViewerLocomotionStepStatus,
    origin: runtime_query.MoveTargetEvaluation,
    target: runtime_query.MoveTargetEvaluation,
};

pub const locomotion_fixture_scene_entry: usize = 19;
pub const locomotion_fixture_background_entry: usize = 19;
pub const locomotion_fixture_cell = GridCell{ .x = 39, .z = 6 };

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
    return state.loadRoomSnapshot(allocator, resolved, scene_entry_index, background_entry_index);
}

pub fn initSession(room: *const RoomSnapshot) Session {
    return runtime_session.Session.init(state.heroStartWorldPoint(room));
}

pub fn buildRenderSnapshot(room: RoomSnapshot, current_session: Session) RenderSnapshot {
    return state.buildRenderSnapshotWithHeroPosition(room, current_session.heroWorldPosition());
}

pub fn seedSessionToLocomotionFixture(room: *const RoomSnapshot, current_session: *Session) !WorldPointSnapshot {
    if (room.scene.entry_index != locomotion_fixture_scene_entry or
        room.background.entry_index != locomotion_fixture_background_entry)
    {
        return error.ViewerLocomotionFixtureUnavailable;
    }

    const query = runtime_query.init(room);
    const surface = try query.cellTopSurface(locomotion_fixture_cell.x, locomotion_fixture_cell.z);
    if (try query.standabilityAtCell(locomotion_fixture_cell.x, locomotion_fixture_cell.z) != .standable) {
        return error.ViewerLocomotionFixtureUnavailable;
    }

    const position = runtime_query.gridCellCenterWorldPosition(
        locomotion_fixture_cell.x,
        locomotion_fixture_cell.z,
        surface.top_y,
    );
    current_session.setHeroWorldPosition(position);
    return position;
}

pub fn attemptLocomotionStep(
    room: *const RoomSnapshot,
    current_session: *Session,
    direction: CardinalDirection,
) ViewerLocomotionStepAttempt {
    const query = runtime_query.init(room);
    const origin_position = current_session.heroWorldPosition();
    const origin = query.evaluateHeroMoveTarget(origin_position);
    if (!origin.isAllowed()) {
        return .{
            .status = .origin_invalid,
            .origin = origin,
            .target = origin,
        };
    }

    const delta = stepDeltaForDirection(direction);
    const target_position = WorldPointSnapshot{
        .x = origin_position.x + delta.x,
        .y = origin_position.y + delta.y,
        .z = origin_position.z + delta.z,
    };
    const target = query.evaluateHeroMoveTarget(target_position);
    if (!target.isAllowed()) {
        return .{
            .status = .target_rejected,
            .origin = origin,
            .target = target,
        };
    }

    current_session.setHeroWorldPosition(target_position);
    return .{
        .status = .moved,
        .origin = origin,
        .target = target,
    };
}

pub fn computeSchematicLayout(
    canvas_width: i32,
    canvas_height: i32,
    grid_width: usize,
    grid_depth: usize,
) SchematicLayout {
    return layout.computeSchematicLayout(canvas_width, canvas_height, grid_width, grid_depth);
}

pub fn computeDebugLayout(
    canvas_width: i32,
    canvas_height: i32,
    grid_width: usize,
    grid_depth: usize,
    show_fragment_panel: bool,
) DebugLayout {
    return layout.computeDebugLayout(canvas_width, canvas_height, grid_width, grid_depth, show_fragment_panel);
}

pub fn projectWorldPoint(snapshot: RenderSnapshot, schematic: sdl.Rect, world_x: i32, world_z: i32) ScreenPoint {
    return layout.projectWorldPoint(snapshot, schematic, world_x, world_z);
}

pub fn projectZoneBounds(snapshot: RenderSnapshot, schematic: sdl.Rect, zone: ZoneBoundsSnapshot) sdl.Rect {
    return layout.projectZoneBounds(snapshot, schematic, zone);
}

pub fn renderDebugView(canvas: *sdl.Canvas, snapshot: RenderSnapshot) !void {
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(std.heap.page_allocator, snapshot);
    defer catalog.deinit(std.heap.page_allocator);
    return render.renderDebugView(canvas, snapshot, catalog, fragment_compare.initialFragmentComparisonSelection(catalog));
}

pub fn buildFragmentComparisonCatalog(
    allocator: std.mem.Allocator,
    snapshot: RenderSnapshot,
) !FragmentComparisonCatalog {
    return fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
}

pub fn initialFragmentComparisonSelection(catalog: FragmentComparisonCatalog) FragmentComparisonSelection {
    return fragment_compare.initialFragmentComparisonSelection(catalog);
}

pub fn stepRankedFragmentComparisonSelection(
    catalog: FragmentComparisonCatalog,
    selection: FragmentComparisonSelection,
    delta: i32,
) FragmentComparisonSelection {
    return fragment_compare.stepRankedSelection(catalog, selection, delta);
}

pub fn stepCellFragmentComparisonSelection(
    catalog: FragmentComparisonCatalog,
    selection: FragmentComparisonSelection,
    delta: i32,
) FragmentComparisonSelection {
    return fragment_compare.stepCellSelection(catalog, selection, delta);
}

pub fn renderDebugViewWithSelection(
    canvas: *sdl.Canvas,
    snapshot: RenderSnapshot,
    catalog: FragmentComparisonCatalog,
    selection: FragmentComparisonSelection,
) !void {
    return render.renderDebugView(canvas, snapshot, catalog, selection);
}

pub fn printLocomotionSeedDiagnostic(writer: anytype, position: WorldPointSnapshot) !void {
    try writer.print(
        "event=hero_seed status=seeded fixture_cell={d}/{d} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            locomotion_fixture_cell.x,
            locomotion_fixture_cell.z,
            position.x,
            position.y,
            position.z,
        },
    );
}

pub fn printLocomotionAttemptDiagnostic(
    writer: anytype,
    direction: CardinalDirection,
    attempt: ViewerLocomotionStepAttempt,
) !void {
    var origin_cell_buffer: [16]u8 = undefined;
    const origin_cell = formatOptionalCell(&origin_cell_buffer, attempt.origin.raw_cell.cell);
    var target_cell_buffer: [16]u8 = undefined;
    const target_cell = formatOptionalCell(&target_cell_buffer, attempt.target.raw_cell.cell);
    try writer.print(
        "event=hero_move direction={s} status={s} origin_status={s} target_status={s} origin_cell={s} target_cell={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            directionLabel(direction),
            locomotionAttemptStatusLabel(attempt.status),
            @tagName(attempt.origin.status),
            @tagName(attempt.target.status),
            origin_cell,
            target_cell,
            attempt.target.target_world_position.x,
            attempt.target.target_world_position.y,
            attempt.target.target_world_position.z,
        },
    );
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
    try writer.print(
        "fragments={d} footprint_cells={d} non_empty_cells={d} fragment_zones={d} brick_previews={d}\n",
        .{
            room.background.fragments.fragment_count,
            room.background.fragments.footprint_cell_count,
            room.background.fragments.non_empty_cell_count,
            room.fragment_zones.len,
            room.background.bricks.previews.len,
        },
    );
    try printUsedBlockSummary(writer, room.background.used_block_ids);
}

pub fn formatWindowTitleZ(allocator: std.mem.Allocator, room: RoomSnapshot) ![:0]u8 {
    const used_blocks = try formatUsedBlockSummaryAlloc(allocator, room.background.used_block_ids, 6);
    defer allocator.free(used_blocks);

    const title = try std.fmt.allocPrint(
        allocator,
        "Little Big Adventure 2 viewer scene={d} background={d} kind={s} loader={any} hero={d},{d},{d} objects={d} zones={d} tracks={d} cube={d} gri={d}(grm={d},bll={d}) grm={d} bll={d} fragments={d}/{d} blocks={s} columns={d}x{d} comp={d}",
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
            room.fragment_zones.len,
            room.background.fragments.fragment_count,
            used_blocks,
            room.background.column_table.width,
            room.background.column_table.depth,
            room.background.composition.occupied_cell_count,
        },
    );
    defer allocator.free(title);

    return allocator.dupeZ(u8, title);
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

fn stepDeltaForDirection(direction: CardinalDirection) HeroWorldDelta {
    return switch (direction) {
        .north => .{ .z = -runtime_query.world_grid_span_xz },
        .east => .{ .x = runtime_query.world_grid_span_xz },
        .south => .{ .z = runtime_query.world_grid_span_xz },
        .west => .{ .x = -runtime_query.world_grid_span_xz },
    };
}

fn directionLabel(direction: CardinalDirection) []const u8 {
    return switch (direction) {
        .north => "north",
        .east => "east",
        .south => "south",
        .west => "west",
    };
}

fn locomotionAttemptStatusLabel(status: ViewerLocomotionStepStatus) []const u8 {
    return switch (status) {
        .moved => "moved",
        .origin_invalid => "origin_invalid",
        .target_rejected => "target_rejected",
    };
}

fn formatOptionalCell(buffer: []u8, cell: ?GridCell) []const u8 {
    if (cell) |resolved| {
        return std.fmt.bufPrint(buffer, "{d}/{d}", .{ resolved.x, resolved.z }) catch unreachable;
    }
    return "none";
}
