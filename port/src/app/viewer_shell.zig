const std = @import("std");
const diagnostics = @import("../foundation/diagnostics.zig");
const paths_mod = @import("../foundation/paths.zig");
const sdl = @import("../platform/sdl.zig");
const runtime_locomotion = @import("../runtime/locomotion.zig");
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
pub const DebugLayout = layout.DebugLayout;
pub const FragmentComparisonCatalog = fragment_compare.FragmentComparisonCatalog;
pub const FragmentComparisonEntry = fragment_compare.FragmentComparisonEntry;
pub const FragmentComparisonPanel = fragment_compare.FragmentComparisonPanel;
pub const FragmentComparisonSelection = fragment_compare.FragmentComparisonSelection;
pub const SchematicLayout = layout.SchematicLayout;
pub const ScreenPoint = layout.ScreenPoint;
pub const ViewerLocomotionStatusDisplay = render.LocomotionStatusDisplay;
pub const ViewerLocomotionStatusDisplayBuffer = render.LocomotionStatusDisplayBuffer;
pub const ViewerLocomotionSchematicCue = render.LocomotionSchematicCue;
pub const ViewerLocomotionSchematicMoveOption = render.LocomotionSchematicMoveOption;
pub const ViewerLocomotionRejectedStage = runtime_locomotion.LocomotionRejectedStage;
pub const ViewerCardinalMoveOption = runtime_locomotion.CardinalMoveOption;
pub const ViewerMoveOptions = runtime_locomotion.MoveOptions;
pub const ViewerLocalNeighborTopology = runtime_locomotion.LocalNeighborTopology;
pub const ViewerRawInvalidStartCandidate = runtime_locomotion.RawInvalidStartCandidate;
pub const ViewerRawInvalidStartStatus = runtime_locomotion.RawInvalidStartStatus;
pub const ViewerSeededValidStatus = runtime_locomotion.SeededValidStatus;
pub const ViewerMoveAcceptedStatus = runtime_locomotion.MoveAcceptedStatus;
pub const ViewerMoveRejectedStatus = runtime_locomotion.MoveRejectedStatus;
pub const ViewerLocomotionStatus = runtime_locomotion.LocomotionStatus;

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

pub fn buildRenderSnapshot(room: *const RoomSnapshot, current_session: Session) RenderSnapshot {
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

pub fn formatLocomotionStatusDisplay(
    buffer: *ViewerLocomotionStatusDisplayBuffer,
    status: ViewerLocomotionStatus,
) ViewerLocomotionStatusDisplay {
    return switch (status) {
        .raw_invalid_start => |value| .{
            .line_count = 6,
            .lines = .{
                "RAW START INVALID",
                formatRawStartLine(&buffer.line_0, value.raw_cell, value.exact_status),
                formatDiagnosticStatusLine(&buffer.line_1, value.diagnostic_status),
                formatCoverageLine(&buffer.line_2, value.occupied_coverage),
                formatRawInvalidStartCandidateLine(&buffer.line_3, "NEAR OCC", value.nearest_occupied),
                formatRawInvalidStartCandidateLine(&buffer.line_4, "NEAR STAND", value.nearest_standable),
                "",
            },
        },
        .seeded_valid => |value| .{
            .line_count = 7,
            .lines = .{
                "FIXTURE SEEDED VALID",
                formatAllowedCellLine(&buffer.line_0, value.cell),
                formatMoveOptionPairLine(&buffer.line_1, value.move_options.options[0], value.move_options.options[1]),
                formatMoveOptionPairLine(&buffer.line_2, value.move_options.options[2], value.move_options.options[3]),
                formatZoneSummary(&buffer.line_3, value.zone_membership),
                formatLocalTopologyHudLine(&buffer.line_4, value.local_topology),
                formatCurrentFootingHudLine(&buffer.line_5, value.local_topology),
            },
            .schematic = locomotionSchematicCue(value.move_options),
        },
        .last_move_accepted => |value| .{
            .line_count = 7,
            .lines = .{
                formatAcceptedMoveLine(&buffer.line_0, value.direction),
                formatAllowedCellLine(&buffer.line_1, value.cell),
                formatMoveOptionPairLine(&buffer.line_2, value.move_options.options[0], value.move_options.options[1]),
                formatMoveOptionPairLine(&buffer.line_3, value.move_options.options[2], value.move_options.options[3]),
                formatZoneSummary(&buffer.line_4, value.zone_membership),
                formatLocalTopologyHudLine(&buffer.line_5, value.local_topology),
                formatCurrentFootingHudLine(&buffer.line_6, value.local_topology),
            },
            .schematic = locomotionSchematicCue(value.move_options),
            .attempt = .{
                .accepted = .{
                    .direction = value.direction,
                    .origin_cell = value.origin_cell,
                    .destination_cell = value.cell,
                },
            },
        },
        .last_move_rejected => |value| if (value.move_options) |move_options| .{
            .line_count = 7,
            .lines = .{
                formatRejectedMoveLine(&buffer.line_0, value.direction),
                formatRejectedCurrentCellAndReasonLine(&buffer.line_1, value.current_cell, value.reason),
                formatMoveOptionPairLine(&buffer.line_2, move_options.options[0], move_options.options[1]),
                formatMoveOptionPairLine(&buffer.line_3, move_options.options[2], move_options.options[3]),
                formatZoneSummary(&buffer.line_4, value.zone_membership),
                formatLocalTopologyHudLine(&buffer.line_5, value.local_topology orelse unreachable),
                formatCurrentFootingHudLine(&buffer.line_6, value.local_topology orelse unreachable),
            },
            .schematic = locomotionSchematicCue(move_options),
            .attempt = .{
                .rejected = .{
                    .direction = value.direction,
                    .current_cell = value.current_cell orelse unreachable,
                    .target_cell = value.target_cell orelse unreachable,
                },
            },
        } else .{
            .line_count = 3,
            .lines = .{
                formatRejectedMoveLine(&buffer.line_0, value.direction),
                formatCurrentCellLine(&buffer.line_1, value.current_cell),
                formatRejectedReasonLine(&buffer.line_2, value.reason),
                "",
                "",
                "",
                "",
            },
        },
    };
}

fn locomotionSchematicCue(move_options: ViewerMoveOptions) ViewerLocomotionSchematicCue {
    var rendered_options: [move_options.options.len]ViewerLocomotionSchematicMoveOption = undefined;
    for (move_options.options, 0..) |move_option, index| {
        rendered_options[index] = .{
            .direction = move_option.direction,
            .target_cell = move_option.target_cell,
            .status = move_option.status,
        };
    }

    return .{
        .admitted_path = .{
            .current_cell = move_options.current_cell,
            .move_options = rendered_options,
        },
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

pub fn renderDebugView(
    canvas: *sdl.Canvas,
    snapshot: RenderSnapshot,
    locomotion_status: ViewerLocomotionStatus,
) !void {
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(std.heap.page_allocator, snapshot);
    defer catalog.deinit(std.heap.page_allocator);
    var status_buffer: ViewerLocomotionStatusDisplayBuffer = .{};
    return render.renderDebugView(
        canvas,
        snapshot,
        catalog,
        fragment_compare.initialFragmentComparisonSelection(catalog),
        formatLocomotionStatusDisplay(&status_buffer, locomotion_status),
    );
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
    locomotion_status: ViewerLocomotionStatus,
) !void {
    var status_buffer: ViewerLocomotionStatusDisplayBuffer = .{};
    return render.renderDebugView(
        canvas,
        snapshot,
        catalog,
        selection,
        formatLocomotionStatusDisplay(&status_buffer, locomotion_status),
    );
}

pub fn printLocomotionStatusDiagnostic(writer: anytype, status: ViewerLocomotionStatus) !void {
    switch (status) {
        .raw_invalid_start => |value| {
            var raw_cell_buffer: [16]u8 = undefined;
            var occupied_bounds_buffer: [32]u8 = undefined;
            var nearest_occupied_buffer: [48]u8 = undefined;
            var nearest_standable_buffer: [48]u8 = undefined;
            try writer.print(
                "event=hero_status status=raw_invalid_start exact_status={s} diagnostic_status={s} raw_cell={s} occupied_coverage={s} occupied_bounds={s} occupied_bounds_dx={d} occupied_bounds_dz={d} nearest_occupied={s} nearest_standable={s} move_options=unavailable hero_x={d} hero_y={d} hero_z={d}\n",
                .{
                    @tagName(value.exact_status),
                    @tagName(value.diagnostic_status),
                    formatOptionalCell(&raw_cell_buffer, value.raw_cell),
                    @tagName(value.occupied_coverage.relation),
                    formatOccupiedBoundsDiagnostic(&occupied_bounds_buffer, value.occupied_coverage),
                    value.occupied_coverage.x_cells_from_bounds,
                    value.occupied_coverage.z_cells_from_bounds,
                    formatRawInvalidStartCandidateDiagnostic(&nearest_occupied_buffer, value.nearest_occupied),
                    formatRawInvalidStartCandidateDiagnostic(&nearest_standable_buffer, value.nearest_standable),
                    value.hero_position.x,
                    value.hero_position.y,
                    value.hero_position.z,
                },
            );
        },
        .seeded_valid => |value| {
            var cell_buffer: [16]u8 = undefined;
            var move_options_buffer: [256]u8 = undefined;
            var topology_buffer: [384]u8 = undefined;
            var footing_buffer: [128]u8 = undefined;
            var zones_buffer: [128]u8 = undefined;
            try writer.print(
                "event=hero_seed status=seeded_valid cell={s} move_options={s} local_topology={s} current_footing={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
                .{
                    formatRequiredCell(&cell_buffer, value.cell),
                    formatMoveOptionsDiagnostic(&move_options_buffer, value.move_options),
                    formatLocalTopologyDiagnosticValue(&topology_buffer, value.local_topology),
                    formatCurrentFootingDiagnosticValue(&footing_buffer, value.local_topology),
                    formatZoneDiagnosticValue(&zones_buffer, value.zone_membership),
                    value.hero_position.x,
                    value.hero_position.y,
                    value.hero_position.z,
                },
            );
        },
        .last_move_accepted => |value| {
            var cell_buffer: [16]u8 = undefined;
            var move_options_buffer: [256]u8 = undefined;
            var topology_buffer: [384]u8 = undefined;
            var footing_buffer: [128]u8 = undefined;
            var zones_buffer: [128]u8 = undefined;
            try writer.print(
                "event=hero_move direction={s} status=accepted cell={s} move_options={s} local_topology={s} current_footing={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
                .{
                    directionLabel(value.direction),
                    formatRequiredCell(&cell_buffer, value.cell),
                    formatMoveOptionsDiagnostic(&move_options_buffer, value.move_options),
                    formatLocalTopologyDiagnosticValue(&topology_buffer, value.local_topology),
                    formatCurrentFootingDiagnosticValue(&footing_buffer, value.local_topology),
                    formatZoneDiagnosticValue(&zones_buffer, value.zone_membership),
                    value.hero_position.x,
                    value.hero_position.y,
                    value.hero_position.z,
                },
            );
        },
        .last_move_rejected => |value| {
            var current_cell_buffer: [16]u8 = undefined;
            var target_cell_buffer: [16]u8 = undefined;
            var move_options_buffer: [256]u8 = undefined;
            if (value.move_options) |move_options| {
                var topology_buffer: [384]u8 = undefined;
                var footing_buffer: [128]u8 = undefined;
                var target_occupied_bounds_buffer: [32]u8 = undefined;
                var zones_buffer: [128]u8 = undefined;
                const target_occupied_coverage = value.target_occupied_coverage orelse unreachable;
                try writer.print(
                    "event=hero_move direction={s} status=rejected rejection_stage={s} reason={s} current_cell={s} target_cell={s} target_occupied_coverage={s} target_occupied_bounds={s} target_occupied_bounds_dx={d} target_occupied_bounds_dz={d} move_options={s} local_topology={s} current_footing={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
                    .{
                        directionLabel(value.direction),
                        @tagName(value.rejection_stage),
                        @tagName(value.reason),
                        formatOptionalCell(&current_cell_buffer, value.current_cell),
                        formatOptionalCell(&target_cell_buffer, value.target_cell),
                        @tagName(target_occupied_coverage.relation),
                        formatOccupiedBoundsDiagnostic(&target_occupied_bounds_buffer, target_occupied_coverage),
                        target_occupied_coverage.x_cells_from_bounds,
                        target_occupied_coverage.z_cells_from_bounds,
                        formatMoveOptionsDiagnostic(&move_options_buffer, move_options),
                        formatLocalTopologyDiagnosticValue(&topology_buffer, value.local_topology orelse unreachable),
                        formatCurrentFootingDiagnosticValue(&footing_buffer, value.local_topology orelse unreachable),
                        formatZoneDiagnosticValue(&zones_buffer, value.zone_membership),
                        value.hero_position.x,
                        value.hero_position.y,
                        value.hero_position.z,
                    },
                );
            } else {
                try writer.print(
                    "event=hero_move direction={s} status=rejected rejection_stage={s} reason={s} current_cell={s} target_cell={s} move_options=unavailable hero_x={d} hero_y={d} hero_z={d}\n",
                    .{
                        directionLabel(value.direction),
                        @tagName(value.rejection_stage),
                        @tagName(value.reason),
                        formatOptionalCell(&current_cell_buffer, value.current_cell),
                        formatOptionalCell(&target_cell_buffer, value.target_cell),
                        value.hero_position.x,
                        value.hero_position.y,
                        value.hero_position.z,
                    },
                );
            }
        },
    }
}

pub fn printStartupDiagnostics(
    writer: anytype,
    resolved: paths_mod.ResolvedPaths,
    room: *const RoomSnapshot,
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

pub fn formatWindowTitleZ(allocator: std.mem.Allocator, room: *const RoomSnapshot) ![:0]u8 {
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

fn directionLabel(direction: CardinalDirection) []const u8 {
    return switch (direction) {
        .north => "north",
        .east => "east",
        .south => "south",
        .west => "west",
    };
}

fn shortDirectionLabel(direction: CardinalDirection) []const u8 {
    return switch (direction) {
        .north => "N",
        .east => "E",
        .south => "S",
        .west => "W",
    };
}

fn formatOptionalCell(buffer: []u8, cell: ?GridCell) []const u8 {
    if (cell) |resolved| {
        return std.fmt.bufPrint(buffer, "{d}/{d}", .{ resolved.x, resolved.z }) catch unreachable;
    }
    return "none";
}

fn formatRequiredCell(buffer: []u8, cell: GridCell) []const u8 {
    return std.fmt.bufPrint(buffer, "{d}/{d}", .{ cell.x, cell.z }) catch unreachable;
}

fn formatMoveOptionTargetCell(buffer: []u8, cell: ?GridCell) []const u8 {
    if (cell) |resolved| {
        return std.fmt.bufPrint(buffer, "{d}/{d}", .{ resolved.x, resolved.z }) catch unreachable;
    }
    return "NONE";
}

fn upperTag(buffer: []u8, value: []const u8) []const u8 {
    const len = @min(buffer.len, value.len);
    for (value[0..len], 0..) |char, index| {
        buffer[index] = if (char >= 'a' and char <= 'z') char - 32 else char;
    }
    return buffer[0..len];
}

fn formatRawStartLine(
    buffer: []u8,
    raw_cell: ?GridCell,
    exact_status: runtime_query.HeroStartExactStatus,
) []const u8 {
    var cell_buffer: [16]u8 = undefined;
    var status_buffer: [40]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "CELL {s} {s}",
        .{
            formatOptionalCell(&cell_buffer, raw_cell),
            upperTag(&status_buffer, @tagName(exact_status)),
        },
    ) catch unreachable;
}

fn formatCoverageLine(buffer: []u8, coverage: runtime_query.OccupiedCoverageProbe) []const u8 {
    var relation_buffer: [16]u8 = undefined;
    if (coverage.occupied_bounds) |bounds| {
        return std.fmt.bufPrint(
            buffer,
            "BOUNDS X{d}..{d} Z{d}..{d} DX{d} DZ{d} {s}",
            .{
                bounds.min_x,
                bounds.max_x,
                bounds.min_z,
                bounds.max_z,
                coverage.x_cells_from_bounds,
                coverage.z_cells_from_bounds,
                coverageHudRelationLabel(&relation_buffer, coverage.relation),
            },
        ) catch unreachable;
    }

    return std.fmt.bufPrint(
        buffer,
        "BOUNDS NONE DX{d} DZ{d} {s}",
        .{
            coverage.x_cells_from_bounds,
            coverage.z_cells_from_bounds,
            coverageHudRelationLabel(&relation_buffer, coverage.relation),
        },
    ) catch unreachable;
}

fn coverageHudRelationLabel(
    buffer: []u8,
    relation: runtime_query.OccupiedCoverageRelation,
) []const u8 {
    return upperTag(buffer, switch (relation) {
        .unmapped_world_point => "unmapped",
        .no_occupied_bounds => "no_occ",
        .within_occupied_bounds => "within",
        .outside_occupied_bounds => "outside",
    });
}

fn formatOccupiedBoundsDiagnostic(
    buffer: []u8,
    coverage: runtime_query.OccupiedCoverageProbe,
) []const u8 {
    const bounds = coverage.occupied_bounds orelse return "none";
    return std.fmt.bufPrint(
        buffer,
        "{d}..{d}:{d}..{d}",
        .{ bounds.min_x, bounds.max_x, bounds.min_z, bounds.max_z },
    ) catch unreachable;
}

fn formatDiagnosticStatusLine(
    buffer: []u8,
    diagnostic_status: runtime_query.HeroStartDiagnosticStatus,
) []const u8 {
    var diagnostic_buffer: [48]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "DIAG {s}",
        .{upperTag(&diagnostic_buffer, @tagName(diagnostic_status))},
    ) catch unreachable;
}

fn formatRawInvalidStartCandidateLine(
    buffer: []u8,
    label: []const u8,
    candidate: ?ViewerRawInvalidStartCandidate,
) []const u8 {
    const resolved = candidate orelse return std.fmt.bufPrint(buffer, "{s} NONE", .{label}) catch unreachable;

    var cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "{s} {s} DX {d} DZ {d} D2 {d}",
        .{
            label,
            formatRequiredCell(&cell_buffer, resolved.cell),
            resolved.x_distance,
            resolved.z_distance,
            resolved.distance_sq,
        },
    ) catch unreachable;
}

fn formatRawInvalidStartCandidateDiagnostic(
    buffer: []u8,
    candidate: ?ViewerRawInvalidStartCandidate,
) []const u8 {
    const resolved = candidate orelse return "none";

    var cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "{s}:{d}:{d}:{d}",
        .{
            formatRequiredCell(&cell_buffer, resolved.cell),
            resolved.x_distance,
            resolved.z_distance,
            resolved.distance_sq,
        },
    ) catch unreachable;
}

fn formatAllowedCellLine(buffer: []u8, cell: GridCell) []const u8 {
    var cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "CELL {s} STATUS ALLOWED",
        .{formatRequiredCell(&cell_buffer, cell)},
    ) catch unreachable;
}

fn formatAcceptedMoveLine(buffer: []u8, direction: CardinalDirection) []const u8 {
    var direction_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "MOVE {s} ACCEPTED",
        .{upperTag(&direction_buffer, directionLabel(direction))},
    ) catch unreachable;
}

fn formatRejectedMoveLine(buffer: []u8, direction: CardinalDirection) []const u8 {
    var direction_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "MOVE {s} REJECTED",
        .{upperTag(&direction_buffer, directionLabel(direction))},
    ) catch unreachable;
}

fn formatCurrentCellLine(buffer: []u8, cell: ?GridCell) []const u8 {
    var cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "STAY CELL {s}",
        .{formatOptionalCell(&cell_buffer, cell)},
    ) catch unreachable;
}

fn formatRejectedCurrentCellAndReasonLine(
    buffer: []u8,
    cell: ?GridCell,
    reason: runtime_query.MoveTargetStatus,
) []const u8 {
    var cell_buffer: [16]u8 = undefined;
    var reason_buffer: [40]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "STAY {s} {s}",
        .{
            formatOptionalCell(&cell_buffer, cell),
            upperTag(&reason_buffer, @tagName(reason)),
        },
    ) catch unreachable;
}

fn formatZoneSummary(buffer: []u8, zone_membership: runtime_locomotion.ZoneMembership) []const u8 {
    const zones = zone_membership.slice();
    if (zones.len == 0) return "ZONES NONE";

    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    writer.writeAll("ZONES ") catch unreachable;
    for (zones, 0..) |zone, index| {
        if (index != 0) writer.writeAll("|") catch unreachable;
        writer.print("{d}", .{zone.index}) catch unreachable;
    }
    return stream.getWritten();
}

fn formatZoneDiagnosticValue(buffer: []u8, zone_membership: runtime_locomotion.ZoneMembership) []const u8 {
    const zones = zone_membership.slice();
    if (zones.len == 0) return "none";

    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    for (zones, 0..) |zone, index| {
        if (index != 0) writer.writeAll("|") catch unreachable;
        writer.print("{d}", .{zone.index}) catch unreachable;
    }
    return stream.getWritten();
}

fn formatLocalTopologyHudLine(
    buffer: []u8,
    local_topology: ViewerLocalNeighborTopology,
) []const u8 {
    var token_buffers: [4][16]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    writer.writeAll("TOPO ") catch unreachable;
    for (local_topology.neighbors, 0..) |neighbor, index| {
        if (index != 0) writer.writeAll(" ") catch unreachable;
        writer.print(
            "{s}:{s}",
            .{
                shortDirectionLabel(neighbor.direction),
                localTopologyHudToken(&token_buffers[index], neighbor),
            },
        ) catch unreachable;
    }
    return stream.getWritten();
}

fn formatLocalTopologyDiagnosticValue(
    buffer: []u8,
    local_topology: ViewerLocalNeighborTopology,
) []const u8 {
    var cell_buffers: [4][16]u8 = undefined;
    var standability_buffers: [4][16]u8 = undefined;
    var delta_buffers: [4][16]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    for (local_topology.neighbors, 0..) |neighbor, index| {
        if (index != 0) writer.writeAll(",") catch unreachable;
        writer.print(
            "{s}:{s}:{s}:{s}:{s}",
            .{
                directionLabel(neighbor.direction),
                formatOptionalCell(&cell_buffers[index], neighbor.cell),
                @tagName(neighbor.status),
                formatOptionalStandability(&standability_buffers[index], neighbor.standability),
                formatOptionalSignedDelta(&delta_buffers[index], neighbor.top_y_delta),
            },
        ) catch unreachable;
    }
    return stream.getWritten();
}

fn formatCurrentFootingHudLine(
    buffer: []u8,
    local_topology: ViewerLocalNeighborTopology,
) []const u8 {
    var standability_buffer: [24]u8 = undefined;
    var shape_buffer: [32]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "SURF {s} Y {d} H {d} D {d} F {d} {s}",
        .{
            upperTag(&standability_buffer, @tagName(local_topology.origin_standability)),
            local_topology.origin_surface.top_y,
            local_topology.origin_surface.total_height,
            local_topology.origin_surface.stack_depth,
            local_topology.origin_surface.top_floor_type,
            upperTag(&shape_buffer, @tagName(local_topology.origin_surface.top_shape_class)),
        },
    ) catch unreachable;
}

fn formatCurrentFootingDiagnosticValue(
    buffer: []u8,
    local_topology: ViewerLocalNeighborTopology,
) []const u8 {
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    writer.print(
        "{s}:{d}:{d}:{d}:{d}:{s}",
        .{
            @tagName(local_topology.origin_standability),
            local_topology.origin_surface.top_y,
            local_topology.origin_surface.total_height,
            local_topology.origin_surface.stack_depth,
            local_topology.origin_surface.top_floor_type,
            @tagName(local_topology.origin_surface.top_shape_class),
        },
    ) catch unreachable;
    return stream.getWritten();
}

fn formatMoveOptionPairLine(
    buffer: []u8,
    first: ViewerCardinalMoveOption,
    second: ViewerCardinalMoveOption,
) []const u8 {
    var first_cell_buffer: [16]u8 = undefined;
    var second_cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "{s} {s} {s} {s} {s} {s}",
        .{
            shortDirectionLabel(first.direction),
            formatMoveOptionTargetCell(&first_cell_buffer, first.target_cell),
            moveOptionStatusHudLabel(first.status),
            shortDirectionLabel(second.direction),
            formatMoveOptionTargetCell(&second_cell_buffer, second.target_cell),
            moveOptionStatusHudLabel(second.status),
        },
    ) catch unreachable;
}

fn formatMoveOptionsDiagnostic(buffer: []u8, move_options: ViewerMoveOptions) []const u8 {
    var cell_buffers: [4][16]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    for (move_options.options, 0..) |option, index| {
        if (index != 0) writer.writeAll(",") catch unreachable;
        writer.print(
            "{s}:{s}:{s}:{s}:{d}:{d}",
            .{
                directionLabel(option.direction),
                formatOptionalCell(&cell_buffers[index], option.target_cell),
                @tagName(option.status),
                @tagName(option.occupied_coverage.relation),
                option.occupied_coverage.x_cells_from_bounds,
                option.occupied_coverage.z_cells_from_bounds,
            },
        ) catch unreachable;
    }
    return stream.getWritten();
}

fn formatRejectedReasonLine(buffer: []u8, reason: runtime_query.MoveTargetStatus) []const u8 {
    var reason_buffer: [40]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "REASON {s}",
        .{upperTag(&reason_buffer, @tagName(reason))},
    ) catch unreachable;
}

fn moveOptionStatusHudLabel(status: runtime_query.MoveTargetStatus) []const u8 {
    return switch (status) {
        .allowed => "ALLOWED",
        .target_out_of_bounds => "OOB",
        .target_empty => "EMPTY",
        .target_missing_top_surface => "NO_TOP",
        .target_blocked => "BLOCKED",
        .target_height_mismatch => "HEIGHT",
    };
}

fn localTopologyHudToken(buffer: []u8, neighbor: runtime_query.CellNeighborProbe) []const u8 {
    if (neighbor.top_y_delta) |delta| return formatSignedDelta(buffer, delta);

    return switch (neighbor.status) {
        .out_of_bounds => "OOB",
        .empty => "EMPTY",
        .missing_top_surface => "NO_TOP",
        .occupied_surface => "OCC",
    };
}

fn formatOptionalStandability(buffer: []u8, standability: ?runtime_query.Standability) []const u8 {
    if (standability) |resolved| {
        return std.fmt.bufPrint(buffer, "{s}", .{@tagName(resolved)}) catch unreachable;
    }
    return "none";
}

fn formatOptionalSignedDelta(buffer: []u8, delta: ?i32) []const u8 {
    if (delta) |resolved| return formatSignedDelta(buffer, resolved);
    return "none";
}

fn formatSignedDelta(buffer: []u8, delta: i32) []const u8 {
    return if (delta >= 0)
        std.fmt.bufPrint(buffer, "+{d}", .{delta}) catch unreachable
    else
        std.fmt.bufPrint(buffer, "{d}", .{delta}) catch unreachable;
}
