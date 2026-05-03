const std = @import("std");
const diagnostics = @import("../foundation/diagnostics.zig");
const paths_mod = @import("../foundation/paths.zig");
const sdl = @import("../platform/sdl.zig");
const runtime_locomotion = @import("../runtime/locomotion.zig");
const runtime_object_behavior = @import("../runtime/object_behavior.zig");
const room_projection = @import("../runtime/room_projection.zig");
const room_entry_state = @import("../runtime/room_entry_state.zig");
const runtime_session = @import("../runtime/session.zig");
const runtime_query = @import("../runtime/world_query.zig");
const world_geometry = @import("../runtime/world_geometry.zig");
const render = @import("viewer/render.zig");
const state = @import("../runtime/room_state.zig");
const layout = @import("viewer/layout.zig");
const fragment_compare = @import("viewer/fragment_compare.zig");
const controller = @import("viewer/controller.zig");

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
pub const CompositionRenderSnapshot = room_projection.CompositionRenderSnapshot;
pub const FragmentLibrarySnapshot = state.FragmentLibrarySnapshot;
pub const FragmentZoneCellSnapshot = state.FragmentZoneCellSnapshot;
pub const FragmentZoneSnapshot = state.FragmentZoneSnapshot;
pub const FragmentRenderSnapshot = room_projection.FragmentRenderSnapshot;
pub const BackgroundSnapshot = state.BackgroundSnapshot;
pub const RoomSnapshot = state.RoomSnapshot;
pub const WorldPointSnapshot = world_geometry.WorldPointSnapshot;
pub const WorldBounds = world_geometry.WorldBounds;
pub const GridCell = world_geometry.GridCell;
pub const CardinalDirection = world_geometry.CardinalDirection;
pub const RenderSnapshot = room_projection.RenderSnapshot;
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
pub const ViewerDialogOverlayDisplay = render.DialogOverlayDisplay;
pub const ViewerDialogOverlayDisplayBuffer = struct {
    line_0: [160]u8 = undefined,
    line_1: [160]u8 = undefined,
    line_2: [160]u8 = undefined,
    line_3: [160]u8 = undefined,
    aux_0: [8]u8 = undefined,
    aux_1: [64]u8 = undefined,
    aux_2: [64]u8 = undefined,
    aux_3: [96]u8 = undefined,
};
pub const ViewerLocomotionSchematicCue = render.LocomotionSchematicCue;
pub const ViewerLocomotionSchematicMoveOption = render.LocomotionSchematicMoveOption;
pub const ViewerLocomotionRejectedStage = runtime_locomotion.LocomotionRejectedStage;
pub const ViewerCardinalMoveOption = runtime_locomotion.CardinalMoveOption;
pub const ViewerMoveOptions = runtime_locomotion.MoveOptions;
pub const ViewerLocalNeighborTopology = runtime_locomotion.LocalNeighborTopology;
pub const ViewerRawInvalidStartCandidate = runtime_locomotion.RawInvalidStartCandidate;
pub const ViewerRawInvalidStartMappingHint = runtime_locomotion.RawInvalidStartMappingHint;
pub const ViewerRawInvalidStartStatus = runtime_locomotion.RawInvalidStartStatus;
pub const ViewerSeededValidStatus = runtime_locomotion.SeededValidStatus;
pub const ViewerMoveAcceptedStatus = runtime_locomotion.MoveAcceptedStatus;
pub const ViewerRawZoneRecoveryAcceptedStatus = runtime_locomotion.RawZoneRecoveryAcceptedStatus;
pub const ViewerMoveRejectedStatus = runtime_locomotion.MoveRejectedStatus;
pub const ViewerLocomotionStatus = runtime_locomotion.LocomotionStatus;
pub const ViewerKey = sdl.Key;
pub const ViewerControlMode = render.ControlMode;
pub const ViewerSidebarTab = render.SidebarTab;
pub const ViewerZoomLevel = render.ZoomLevel;
pub const ViewerViewMode = render.ViewMode;
pub const ViewerObjectState = runtime_session.ObjectState;

pub const ViewerInteractionState = controller.InteractionState;
pub const ViewerPostKeyAction = controller.PostKeyAction;
pub const ViewerRuntimeCommand = controller.RuntimeCommand;
pub const ViewerKeyDownResult = controller.KeyDownResult;

pub const locomotion_fixture_scene_entry: usize = 19;
pub const locomotion_fixture_background_entry: usize = 19;
pub const locomotion_fixture_cell = GridCell{ .x = 39, .z = 6 };
const sendell_scene_entry: usize = 36;
const sendell_background_entry: usize = 36;
const sendell_object_index: usize = 2;
const sendell_first_dialog_id: i16 = 3;
const secret_room_scene_entry: usize = 2;
const secret_room_background_entry: usize = 1;
const secret_room_cellar_background_entry: usize = 0;
const secret_room_key_var_game_index: u8 = 0;
const secret_room_key_source_position = WorldPointSnapshot{ .x = 1280, .y = 2048, .z = 5376 };
const secret_room_key_pickup_x: i32 = 3768;
const secret_room_key_pickup_z: i32 = 4366;
const secret_room_house_door_unlock_position = WorldPointSnapshot{ .x = 3050, .y = 2048, .z = 4034 };
const secret_room_house_to_cellar_position = WorldPointSnapshot{ .x = 9730, .y = 1024, .z = 762 };
const secret_room_cellar_return_position = WorldPointSnapshot{ .x = 9730, .y = 1025, .z = 1126 };
const reward_scene_entry: usize = 19;
const reward_background_entry: usize = 19;
const reward_object_index: usize = 2;

const SecretRoomValidationTarget = enum {
    key_source,
    key_pickup,
    house_door,
    cellar_return,
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

pub fn initSession(allocator: std.mem.Allocator, room: *const RoomSnapshot) !Session {
    var current_session = try runtime_session.Session.initWithObjects(
        allocator,
        state.heroStartWorldPoint(room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
    room_entry_state.applyRoomEntryState(room, &current_session);
    return current_session;
}

pub fn buildRenderSnapshot(room: *const RoomSnapshot, current_session: Session) RenderSnapshot {
    var snapshot = room_projection.buildRenderSnapshotWithHeroPosition(room, current_session.heroWorldPosition());
    const runtime_objects = current_session.objectSnapshots();
    std.debug.assert(runtime_objects.len == 0 or runtime_objects.len == room.scene.objects.len);
    if (runtime_objects.len != 0) snapshot.objects = runtime_objects;
    return snapshot;
}

pub fn seedSessionToLocomotionFixture(room: *const RoomSnapshot, current_session: *Session) !WorldPointSnapshot {
    const query = runtime_query.init(room);
    if (room.scene.entry_index != locomotion_fixture_scene_entry or
        room.background.entry_index != locomotion_fixture_background_entry)
    {
        return runtime_locomotion.seedSessionToNearestStandableStart(room, current_session);
    }

    const position = try positionForExplicitLocomotionFixture(query, locomotion_fixture_cell);
    current_session.setHeroWorldPosition(position);
    return position;
}

fn secretRoomValidationTargetPosition(
    room: *const RoomSnapshot,
    current_session: Session,
    target: SecretRoomValidationTarget,
) !?WorldPointSnapshot {
    if (room.scene.entry_index != secret_room_scene_entry) return null;
    return switch (target) {
        .key_source => if (room.background.entry_index == secret_room_background_entry)
            secret_room_key_source_position
        else
            null,
        .key_pickup => if (room.background.entry_index == secret_room_background_entry)
            try secretRoomKeyPickupPosition(room)
        else
            null,
        .house_door => if (room.background.entry_index == secret_room_background_entry)
            if (current_session.secretRoomHouseDoorUnlocked())
                secret_room_house_to_cellar_position
            else
                secret_room_house_door_unlock_position
        else
            null,
        .cellar_return => if (room.background.entry_index == secret_room_cellar_background_entry)
            secret_room_cellar_return_position
        else
            null,
    };
}

fn secretRoomKeyPickupPosition(room: *const RoomSnapshot) !WorldPointSnapshot {
    const query = runtime_query.init(room);
    const cell = try query.gridCellAtWorldPoint(secret_room_key_pickup_x, secret_room_key_pickup_z);
    const surface = try query.cellTopSurface(cell.x, cell.z);
    return .{
        .x = secret_room_key_pickup_x,
        .y = surface.top_y,
        .z = secret_room_key_pickup_z,
    };
}

pub fn formatLocomotionStatusDisplay(
    buffer: *ViewerLocomotionStatusDisplayBuffer,
    status: ViewerLocomotionStatus,
) ViewerLocomotionStatusDisplay {
    return switch (status) {
        .raw_invalid_start => |value| .{
            .line_count = 7,
            .lines = .{
                "RAW START INVALID",
                formatRawStartLine(&buffer.line_0, value.raw_cell, value.exact_status),
                formatDiagnosticStatusLine(&buffer.line_1, value.diagnostic_status),
                formatCoverageLine(&buffer.line_2, value.occupied_coverage),
                formatRawInvalidStartCandidateLine(&buffer.line_3, "NEAR OCC", value.nearest_occupied),
                formatRawInvalidStartCandidateLine(&buffer.line_4, "NEAR STAND", value.nearest_standable),
                formatRawInvalidStartMappingHintLine(&buffer.line_5, value.best_alt_mapping),
            },
        },
        .raw_invalid_current => |value| .{
            .line_count = 5,
            .lines = .{
                "RAW POSITION INVALID",
                formatCurrentCellLine(&buffer.line_0, value.raw_cell),
                formatRejectedReasonLine(&buffer.line_1, value.reason),
                formatCoverageLine(&buffer.line_2, value.occupied_coverage),
                formatZoneSummary(&buffer.line_3, value.zone_membership),
                "",
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
        .last_zone_recovery_accepted => |value| .{
            .line_count = 3,
            .lines = .{
                formatAcceptedRawZoneRecoveryMoveLine(&buffer.line_0, value.direction),
                formatZoneSummary(&buffer.line_1, value.zone_membership),
                "RAW START ZONE RECOVERY",
                "",
                "",
                "",
                "",
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
            .attempt = rejectedAttemptCue(value),
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

fn rejectedAttemptCue(value: ViewerMoveRejectedStatus) render.LocomotionAttemptCue {
    const current_cell = value.current_cell orelse return .none;
    const target_cell = value.target_cell orelse return .none;
    return .{
        .rejected = .{
            .direction = value.direction,
            .current_cell = current_cell,
            .target_cell = target_cell,
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

pub fn initialInteractionState(catalog: FragmentComparisonCatalog) ViewerInteractionState {
    return controller.initialInteractionState(catalog);
}

pub fn zoomIn(zoom_level: ViewerZoomLevel) ViewerZoomLevel {
    return controller.zoomIn(zoom_level);
}

pub fn zoomOut(zoom_level: ViewerZoomLevel) ViewerZoomLevel {
    return controller.zoomOut(zoom_level);
}

pub fn stepRankedFragmentComparisonSelection(
    catalog: FragmentComparisonCatalog,
    selection: FragmentComparisonSelection,
    delta: i32,
) FragmentComparisonSelection {
    return controller.stepRankedFragmentComparisonSelection(catalog, selection, delta);
}

pub fn stepCellFragmentComparisonSelection(
    catalog: FragmentComparisonCatalog,
    selection: FragmentComparisonSelection,
    delta: i32,
) FragmentComparisonSelection {
    return controller.stepCellFragmentComparisonSelection(catalog, selection, delta);
}

pub fn handleKeyDown(
    room: *const RoomSnapshot,
    current_session: *Session,
    catalog: FragmentComparisonCatalog,
    interaction: ViewerInteractionState,
    locomotion_status: ViewerLocomotionStatus,
    key: ViewerKey,
) !ViewerKeyDownResult {
    if (controller.handleInteractionKeyDown(catalog, interaction, locomotion_status, key)) |result| {
        return result;
    }

    switch (key) {
        .enter => {
            if (runtime_object_behavior.sendellStoryAwaitsAdvance(room, current_session.*) or
                runtime_object_behavior.cellarMessageAwaitsAdvance(room, current_session.*))
            {
                try current_session.submitHeroIntent(.advance_story);
                return .{
                    .interaction = interaction,
                    .locomotion_status = locomotion_status,
                    .post_key_action = .advance_world,
                };
            }

            return .{
                .interaction = .{
                    .control_mode = .locomotion,
                    .sidebar_tab = interaction.sidebar_tab,
                    .zoom_level = interaction.zoom_level,
                    .view_mode = interaction.view_mode,
                    .fragment_selection = interaction.fragment_selection,
                },
                .locomotion_status = locomotion_status,
                .should_print_locomotion_diagnostic = true,
                .runtime_command = .seed_locomotion,
            };
        },
        .left, .right, .up, .down => {
            const direction: CardinalDirection = switch (key) {
                .left => .west,
                .right => .east,
                .up => .north,
                .down => .south,
                else => unreachable,
            };
            try current_session.submitHeroIntent(.{ .move_cardinal = direction });
            return .{
                .interaction = interaction,
                .locomotion_status = locomotion_status,
                .post_key_action = .advance_world,
            };
        },
        .f => {
            try current_session.submitHeroIntent(.cast_lightning);
            return .{
                .interaction = interaction,
                .locomotion_status = locomotion_status,
                .post_key_action = .advance_world,
            };
        },
        .behavior_normal,
        .behavior_sporty,
        .behavior_aggressive,
        .behavior_discreet,
        => {
            const mode: runtime_session.BehaviorMode = switch (key) {
                .behavior_normal => .normal,
                .behavior_sporty => .sporty,
                .behavior_aggressive => .aggressive,
                .behavior_discreet => .discreet,
                else => unreachable,
            };
            try current_session.submitHeroIntent(.{ .select_behavior_mode = mode });
            return .{
                .interaction = interaction,
                .locomotion_status = locomotion_status,
                .post_key_action = .advance_world,
            };
        },
        .magic_ball_select => {
            try current_session.submitHeroIntent(.select_magic_ball);
            return .{
                .interaction = interaction,
                .locomotion_status = locomotion_status,
                .post_key_action = .advance_world,
            };
        },
        .magic_ball_throw => {
            try current_session.submitHeroIntent(.{ .throw_magic_ball = current_session.magicBallThrowMode() });
            return .{
                .interaction = interaction,
                .locomotion_status = locomotion_status,
                .post_key_action = .advance_world,
            };
        },
        .space => {
            return .{
                .interaction = interaction,
                .locomotion_status = locomotion_status,
                .post_key_action = .advance_world,
            };
        },
        .proof_key_source, .proof_key_pickup, .proof_house_door, .proof_cellar_return => {
            const target: SecretRoomValidationTarget = switch (key) {
                .proof_key_source => .key_source,
                .proof_key_pickup => .key_pickup,
                .proof_house_door => .house_door,
                .proof_cellar_return => .cellar_return,
                else => unreachable,
            };
            const jump_position = try secretRoomValidationTargetPosition(room, current_session.*, target);
            return .{
                .interaction = .{
                    .control_mode = .locomotion,
                    .sidebar_tab = interaction.sidebar_tab,
                    .zoom_level = interaction.zoom_level,
                    .view_mode = interaction.view_mode,
                    .fragment_selection = interaction.fragment_selection,
                },
                .locomotion_status = locomotion_status,
                .should_print_locomotion_diagnostic = jump_position != null,
                .post_key_action = switch (target) {
                    .house_door,
                    .cellar_return,
                    => if (jump_position != null) .apply_validation_zone_effects else .none,
                    .key_source,
                    .key_pickup,
                    => .none,
                },
                .runtime_command = if (jump_position) |position| .{ .set_hero_world_position = position } else .none,
            };
        },
        .w => {
            try current_session.submitHeroIntent(.default_action);
            return .{
                .interaction = interaction,
                .locomotion_status = locomotion_status,
                .post_key_action = .advance_world,
            };
        },
        .tab,
        .c,
        .v,
        .zoom_in,
        .zoom_out,
        .zoom_reset,
        => unreachable,
    }
}

pub fn renderDebugViewWithSelection(
    canvas: *sdl.Canvas,
    snapshot: RenderSnapshot,
    catalog: FragmentComparisonCatalog,
    selection: FragmentComparisonSelection,
    locomotion_status: ViewerLocomotionStatus,
    control_mode: ViewerControlMode,
    sidebar_tab: ViewerSidebarTab,
    zoom_level: ViewerZoomLevel,
    view_mode: ViewerViewMode,
    dialog_overlay: ViewerDialogOverlayDisplay,
    reward_collectibles: []const runtime_session.RewardCollectible,
) !void {
    var status_buffer: ViewerLocomotionStatusDisplayBuffer = .{};
    return render.renderDebugView(
        canvas,
        snapshot,
        catalog,
        selection,
        formatLocomotionStatusDisplay(&status_buffer, locomotion_status),
        control_mode,
        sidebar_tab,
        zoom_level,
        view_mode,
        dialog_overlay,
        reward_collectibles,
    );
}

pub fn formatGameplayOverlayDisplay(
    buffer: *ViewerDialogOverlayDisplayBuffer,
    room: *const RoomSnapshot,
    current_session: Session,
) ViewerDialogOverlayDisplay {
    const sendell_overlay = formatSendellDialogOverlayDisplay(room, current_session);
    if (sendell_overlay.line_count != 0) return sendell_overlay;
    const cellar_message_overlay = formatCellarMessageOverlayDisplay(buffer, room, current_session);
    if (cellar_message_overlay.line_count != 0) return cellar_message_overlay;
    const secret_room_overlay = formatSecretRoomKeyOverlayDisplay(buffer, room, current_session);
    if (secret_room_overlay.line_count != 0) return secret_room_overlay;
    const reward_overlay = formatScene1919RewardOverlayDisplay(buffer, room, current_session);
    if (reward_overlay.line_count != 0) return reward_overlay;
    return formatZoneProbeOverlayDisplay(buffer, room, current_session);
}

pub fn formatSendellDialogOverlayDisplay(
    room: *const RoomSnapshot,
    current_session: Session,
) ViewerDialogOverlayDisplay {
    if (room.scene.entry_index != sendell_scene_entry or room.background.entry_index != sendell_background_entry) {
        return .{};
    }

    const object_behavior = current_session.objectBehaviorStateByIndex(sendell_object_index) orelse return .{};
    const dialog_id = current_session.currentDialogId();
    const dialog_slice = runtime_object_behavior.currentSendellDialogSlice(current_session);

    return switch (object_behavior.sendell_ball_phase) {
        .awaiting_first_dialog_ack => blk: {
            const stable_dialog_id = dialog_id orelse break :blk .{};
            const slice = dialog_slice orelse break :blk .{};
            if (stable_dialog_id != sendell_first_dialog_id or slice.page_number != 1) break :blk .{};
            break :blk .{
                .title = "SENDELL DIAL",
                .nav_title = "NAV / DIAL",
                .line_count = 4,
                .lines = .{
                    "CURRENT DIAL 3",
                    slice.visible_text,
                    slice.next_text,
                    "ENTER ACK NOW",
                },
            };
        },
        .awaiting_second_dialog_ack => blk: {
            const stable_dialog_id = dialog_id orelse break :blk .{};
            const slice = dialog_slice orelse break :blk .{};
            if (stable_dialog_id != sendell_first_dialog_id or slice.page_number != 2) break :blk .{};
            break :blk .{
                .title = "SENDELL DIAL",
                .nav_title = "NAV / DIAL",
                .line_count = 4,
                .lines = .{
                    "CURRENT DIAL 3",
                    slice.visible_text,
                    "<END>",
                    "ENTER CLAIM BALL",
                },
            };
        },
        else => .{},
    };
}

pub fn formatCellarMessageOverlayDisplay(
    buffer: *ViewerDialogOverlayDisplayBuffer,
    room: *const RoomSnapshot,
    current_session: Session,
) ViewerDialogOverlayDisplay {
    if (!runtime_object_behavior.cellarMessageAwaitsAdvance(room, current_session)) return .{};
    const dialog_id = current_session.currentDialogId() orelse return .{};
    const hero_position = current_session.heroWorldPosition();
    const zones = runtime_query.init(room).containingZonesAtWorldPoint(hero_position) catch return .{};
    const message_zone = currentCellarMessageZone(zones, dialog_id);
    const line_0 = std.fmt.bufPrint(
        &buffer.line_0,
        "DIALOG {d}",
        .{dialog_id},
    ) catch unreachable;
    const line_1 = if (message_zone) |zone|
        std.fmt.bufPrint(
            &buffer.line_1,
            "ZONE {d} FACING {s}",
            .{ zone.index, cellarMessageFacingLabel(zone) },
        ) catch unreachable
    else
        "ZONE NONE";
    const line_2 = std.fmt.bufPrint(
        &buffer.line_2,
        "POS {d} {d} {d}",
        .{ hero_position.x, hero_position.y, hero_position.z },
    ) catch unreachable;

    return .{
        .title = "CELLAR MESSAGE",
        .nav_title = "NAV / MESSAGE",
        .line_count = 4,
        .lines = .{
            line_0,
            line_1,
            line_2,
            "ENTER ACK",
        },
        .accent = .{ .r = 112, .g = 196, .b = 255, .a = 255 },
    };
}

pub fn formatSecretRoomKeyOverlayDisplay(
    buffer: *ViewerDialogOverlayDisplayBuffer,
    room: *const RoomSnapshot,
    current_session: Session,
) ViewerDialogOverlayDisplay {
    if (room.scene.entry_index != secret_room_scene_entry or
        (room.background.entry_index != secret_room_background_entry and
            room.background.entry_index != secret_room_cellar_background_entry))
    {
        return .{};
    }

    const events = current_session.bonusSpawnEvents();
    const collectibles = current_session.rewardCollectibles();
    const pickup_events = current_session.rewardPickupEvents();
    const key_count = current_session.littleKeyCount();
    const key_var = current_session.gameVar(secret_room_key_var_game_index);
    if (events.len == 0 and
        collectibles.len == 0 and
        pickup_events.len == 0 and
        key_count == 0 and
        key_var == 0 and
        room.background.entry_index != secret_room_background_entry)
    {
        return .{};
    }

    const latest_event = if (events.len == 0) null else events[events.len - 1];
    const latest_pickup_event = if (pickup_events.len == 0) null else pickup_events[pickup_events.len - 1];

    const line_0 = std.fmt.bufPrint(
        &buffer.line_0,
        "ROOM 2/{d} KEYS {d} VAR0 {d}",
        .{
            room.background.entry_index,
            key_count,
            key_var,
        },
    ) catch unreachable;
    const line_1 = std.fmt.bufPrint(
        &buffer.line_1,
        "{s}",
        .{secretRoomKeyStatusLabel(room.background.entry_index, collectibles.len, pickup_events.len, key_count, key_var)},
    ) catch unreachable;
    const line_2 = std.fmt.bufPrint(
        &buffer.line_2,
        "POS {d} {d} {d} {s}",
        .{
            current_session.heroWorldPosition().x,
            current_session.heroWorldPosition().y,
            current_session.heroWorldPosition().z,
            formatExactZonesWithProjectedFallback(buffer, room, current_session),
        },
    ) catch unreachable;
    const line_3 = if (latest_pickup_event) |event|
        std.fmt.bufPrint(
            &buffer.line_3,
            "PICK {s} {d}@{d}",
            .{
                runtimeBonusKindLabel(event.kind),
                event.quantity,
                event.pickup_frame_index,
            },
        ) catch unreachable
    else if (latest_event) |event|
        std.fmt.bufPrint(
            &buffer.line_3,
            "LAST {s} {d}@{d}",
            .{
                runtimeBonusKindLabel(event.kind),
                event.quantity,
                event.frame_index,
            },
        ) catch unreachable
    else
        "LAST NONE";
    const validation_line = secretRoomValidationChecklistLine(buffer, room, current_session);

    return .{
        .title = "0013 KEY",
        .nav_title = "NAV / KEY",
        .line_count = 4,
        .lines = .{
            line_0,
            line_1,
            line_2,
            if (std.mem.eql(u8, line_3, "LAST NONE")) validation_line else line_3,
        },
        .accent = .{ .r = 245, .g = 216, .b = 95, .a = 255 },
    };
}

fn secretRoomValidationChecklistLine(
    buffer: *ViewerDialogOverlayDisplayBuffer,
    room: *const RoomSnapshot,
    current_session: Session,
) []const u8 {
    const hero_position = current_session.heroWorldPosition();
    const exact_zones = runtime_query.init(room).containingZonesAtWorldPoint(hero_position) catch {
        return "1 SRC 2 PICK 3 DOOR 4 RET";
    };
    const source_exact = room.background.entry_index == secret_room_background_entry and
        hasScenarioZoneNum(exact_zones, 0);
    const door_exact = room.background.entry_index == secret_room_background_entry and
        ((hero_position.x >= 3000 and hero_position.x <= 3128 and
            hero_position.y == 2048 and
            hero_position.z >= 3984 and hero_position.z <= 4096) or
            hasZoneIndex(exact_zones, 0));
    const cellar_return_exact = room.background.entry_index == secret_room_cellar_background_entry and
        hero_position.x >= 9680 and hero_position.x <= 9780 and
        hero_position.y >= 1024 and hero_position.y <= 1025 and
        hero_position.z >= 1040 and hero_position.z <= 1180;
    return std.fmt.bufPrint(
        &buffer.aux_3,
        "SRC {s} PICK {s} DOOR {s} RET {s}",
        .{
            yesNo(source_exact),
            yesNo(current_session.rewardCollectibles().len != 0),
            yesNo(door_exact),
            yesNo(cellar_return_exact),
        },
    ) catch unreachable;
}

fn hasZoneIndex(zone_membership: runtime_locomotion.ZoneMembership, index: usize) bool {
    for (zone_membership.slice()) |zone| {
        if (zone.index == index) return true;
    }
    return false;
}

fn hasScenarioZoneNum(zone_membership: runtime_locomotion.ZoneMembership, num: i16) bool {
    for (zone_membership.slice()) |zone| {
        if (zone.kind == .scenario and zone.num == num) return true;
    }
    return false;
}

fn currentCellarMessageZone(
    zone_membership: runtime_locomotion.ZoneMembership,
    dialog_id: i16,
) ?ZoneBoundsSnapshot {
    for (zone_membership.slice()) |zone| switch (zone.semantics) {
        .message => |message| if (message.dialog_id == dialog_id) return zone,
        else => {},
    };
    return null;
}

fn cellarMessageFacingLabel(zone: ZoneBoundsSnapshot) []const u8 {
    return switch (zone.semantics) {
        .message => |message| @tagName(message.facing_direction),
        else => "unknown",
    };
}

fn yesNo(value: bool) []const u8 {
    return if (value) "Y" else "N";
}

pub fn formatScene1919RewardOverlayDisplay(
    buffer: *ViewerDialogOverlayDisplayBuffer,
    room: *const RoomSnapshot,
    current_session: Session,
) ViewerDialogOverlayDisplay {
    if (room.scene.entry_index != reward_scene_entry or room.background.entry_index != reward_background_entry) {
        return .{};
    }

    const object_behavior = current_session.objectBehaviorStateByIndex(reward_object_index) orelse return .{};
    const events = current_session.bonusSpawnEvents();
    const collectibles = current_session.rewardCollectibles();
    const pickup_events = current_session.rewardPickupEvents();
    if (events.len == 0 and object_behavior.emitted_bonus_count == 0 and pickup_events.len == 0) return .{};

    const latest_event = if (events.len == 0) null else events[events.len - 1];
    const latest_pickup_event = if (pickup_events.len == 0) null else pickup_events[pickup_events.len - 1];

    const line_0 = std.fmt.bufPrint(
        &buffer.line_0,
        "TRACK {s} SPR {d}",
        .{
            formatOptionalTrackLabel(&buffer.aux_0, object_behavior.current_track_label),
            object_behavior.current_sprite,
        },
    ) catch unreachable;
    const line_1 = std.fmt.bufPrint(
        &buffer.line_1,
        "{s} {d} {s}",
        .{
            if (collectibles.len != 0) "DROP" else "BONUS",
            if (collectibles.len != 0) collectibles.len else object_behavior.emitted_bonus_count,
            if (collectibles.len != 0)
                "LIVE"
            else if (pickup_events.len != 0)
                "TAKEN"
            else if (object_behavior.bonus_exhausted)
                "SPENT"
            else
                "READY",
        },
    ) catch unreachable;
    const line_2 = std.fmt.bufPrint(
        &buffer.line_2,
        "CUBE0 {d} CUBE1 {d}",
        .{
            current_session.cubeVar(0),
            current_session.cubeVar(1),
        },
    ) catch unreachable;
    const line_3 = if (latest_pickup_event) |event|
        std.fmt.bufPrint(
            &buffer.line_3,
            "PICK {s} {d}@{d}",
            .{
                runtimeBonusKindLabel(event.kind),
                event.quantity,
                event.pickup_frame_index,
            },
        ) catch unreachable
    else if (latest_event) |event|
        std.fmt.bufPrint(
            &buffer.line_3,
            "LAST {s} {d}@{d}",
            .{
                runtimeBonusKindLabel(event.kind),
                event.quantity,
                event.frame_index,
            },
        ) catch unreachable
    else
        "LAST NONE";

    return .{
        .title = "OBJ2 LOOP",
        .nav_title = "NAV / REWARD",
        .line_count = 4,
        .lines = .{
            line_0,
            line_1,
            line_2,
            line_3,
        },
        .accent = .{ .r = 160, .g = 220, .b = 120, .a = 255 },
    };
}

pub fn formatZoneProbeOverlayDisplay(
    buffer: *ViewerDialogOverlayDisplayBuffer,
    room: *const RoomSnapshot,
    current_session: Session,
) ViewerDialogOverlayDisplay {
    if (room.scene.zones.len == 0) return .{};

    const hero_position = current_session.heroWorldPosition();
    const exact_zones = runtime_query.init(room).containingZonesAtWorldPoint(hero_position) catch return .{};
    const projected_zones = containingZonesAtWorldXZ(room, hero_position) catch return .{};
    if (exact_zones.slice().len == 0 and projected_zones.slice().len == 0) return .{};

    const line_0 = std.fmt.bufPrint(
        &buffer.line_0,
        "POS {d} {d} {d}",
        .{ hero_position.x, hero_position.y, hero_position.z },
    ) catch unreachable;
    const line_1 = formatZoneSummary(&buffer.line_1, exact_zones);
    const line_2 = std.fmt.bufPrint(
        &buffer.line_2,
        "XZ {s}",
        .{formatZoneSummary(&buffer.aux_1, projected_zones)},
    ) catch unreachable;
    const line_3 = formatZoneYDiagnosticLine(&buffer.line_3, hero_position.y, projected_zones);

    return .{
        .title = "ZONE PROBE",
        .nav_title = "NAV / ZONE",
        .line_count = 4,
        .lines = .{
            line_0,
            line_1,
            line_2,
            line_3,
        },
        .accent = .{ .r = 177, .g = 139, .b = 255, .a = 255 },
    };
}

fn secretRoomKeyStatusLabel(
    background_entry_index: usize,
    collectible_count: usize,
    pickup_event_count: usize,
    key_count: u8,
    key_var: i16,
) []const u8 {
    if (collectible_count != 0) return "KEY DROP LIVE";
    if (background_entry_index == secret_room_cellar_background_entry) {
        if (key_count != 0) return "CELLAR RETURN KEY";
        return "CELLAR RETURN READY";
    }
    if (pickup_event_count != 0) return "KEY TAKEN";
    if (key_var != 0) return "KEY SPAWNED";
    return "KEY SOURCE READY";
}

fn formatExactZonesWithProjectedFallback(
    buffer: *ViewerDialogOverlayDisplayBuffer,
    room: *const RoomSnapshot,
    current_session: Session,
) []const u8 {
    const hero_position = current_session.heroWorldPosition();
    const exact_zones = runtime_query.init(room).containingZonesAtWorldPoint(hero_position) catch {
        return "ZONES ERR";
    };
    const exact_summary = formatZoneSummary(&buffer.aux_1, exact_zones);
    if (exact_zones.slice().len != 0) return exact_summary;

    const projected_zones = containingZonesAtWorldXZ(room, hero_position) catch {
        return exact_summary;
    };
    if (projected_zones.slice().len == 0) return exact_summary;

    return std.fmt.bufPrint(
        &buffer.aux_3,
        "ZONES NONE XZ {s}",
        .{formatZoneDiagnosticValue(&buffer.aux_2, projected_zones)},
    ) catch unreachable;
}

fn containingZonesAtWorldXZ(
    room: *const RoomSnapshot,
    world_position: WorldPointSnapshot,
) !runtime_query.ContainingZoneSet {
    var containing: runtime_query.ContainingZoneSet = .{};
    for (room.scene.zones) |zone| {
        if (!zoneContainsWorldXZ(zone, world_position)) continue;
        try containing.append(zone);
    }
    return containing;
}

fn zoneContainsWorldXZ(zone: ZoneBoundsSnapshot, world_position: WorldPointSnapshot) bool {
    return world_position.x >= zone.x_min and
        world_position.x <= zone.x_max and
        world_position.z >= zone.z_min and
        world_position.z <= zone.z_max;
}

fn formatZoneYDiagnosticLine(
    buffer: []u8,
    hero_y: i32,
    projected_zones: runtime_query.ContainingZoneSet,
) []const u8 {
    const zones = projected_zones.slice();
    if (zones.len == 0) return "XZ ZONES NONE";

    var min_y = zones[0].y_min;
    var max_y = zones[0].y_max;
    for (zones[1..]) |zone| {
        min_y = @min(min_y, zone.y_min);
        max_y = @max(max_y, zone.y_max);
    }

    return std.fmt.bufPrint(
        buffer,
        "Y {d} ZONE Y {d}..{d}",
        .{ hero_y, min_y, max_y },
    ) catch unreachable;
}

fn positionForExplicitLocomotionFixture(
    query: runtime_query.WorldQuery,
    fixture_cell: GridCell,
) !WorldPointSnapshot {
    const surface = try query.cellTopSurface(fixture_cell.x, fixture_cell.z);
    if (try query.standabilityAtCell(fixture_cell.x, fixture_cell.z) != .standable) {
        return error.ViewerLocomotionFixtureUnavailable;
    }

    return runtime_query.gridCellCenterWorldPosition(
        fixture_cell.x,
        fixture_cell.z,
        surface.top_y,
    );
}

pub fn printLocomotionStatusDiagnostic(writer: anytype, status: ViewerLocomotionStatus) !void {
    switch (status) {
        .raw_invalid_start => |value| {
            var raw_cell_buffer: [16]u8 = undefined;
            var occupied_bounds_buffer: [32]u8 = undefined;
            var nearest_occupied_buffer: [48]u8 = undefined;
            var nearest_standable_buffer: [48]u8 = undefined;
            var best_alt_mapping_buffer: [160]u8 = undefined;
            try writer.print(
                "event=hero_status status=raw_invalid_start exact_status={s} diagnostic_status={s} raw_cell={s} occupied_coverage={s} occupied_bounds={s} occupied_bounds_dx={d} occupied_bounds_dz={d} nearest_occupied={s} nearest_standable={s} best_alt_mapping={s} move_options=unavailable hero_x={d} hero_y={d} hero_z={d}\n",
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
                    formatRawInvalidStartMappingHintDiagnostic(&best_alt_mapping_buffer, value.best_alt_mapping),
                    value.hero_position.x,
                    value.hero_position.y,
                    value.hero_position.z,
                },
            );
        },
        .raw_invalid_current => |value| {
            var raw_cell_buffer: [16]u8 = undefined;
            var occupied_bounds_buffer: [32]u8 = undefined;
            var zones_buffer: [128]u8 = undefined;
            try writer.print(
                "event=hero_status status=raw_invalid_current reason={s} raw_cell={s} occupied_coverage={s} occupied_bounds={s} occupied_bounds_dx={d} occupied_bounds_dz={d} zones={s} move_options=unavailable hero_x={d} hero_y={d} hero_z={d}\n",
                .{
                    @tagName(value.reason),
                    formatOptionalCell(&raw_cell_buffer, value.raw_cell),
                    @tagName(value.occupied_coverage.relation),
                    formatOccupiedBoundsDiagnostic(&occupied_bounds_buffer, value.occupied_coverage),
                    value.occupied_coverage.x_cells_from_bounds,
                    value.occupied_coverage.z_cells_from_bounds,
                    formatZoneDiagnosticValue(&zones_buffer, value.zone_membership),
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
        .last_zone_recovery_accepted => |value| {
            var zones_buffer: [128]u8 = undefined;
            try writer.print(
                "event=hero_move direction={s} status=accepted_raw_zone_recovery recovery_step_xz={d} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
                .{
                    directionLabel(value.direction),
                    runtime_locomotion.raw_invalid_zone_entry_step_xz,
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
    allocator: std.mem.Allocator,
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
    try printObservedNeighborPatternSummary(writer, allocator, room);
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

fn printObservedNeighborPatternSummary(
    writer: anytype,
    allocator: std.mem.Allocator,
    room: *const RoomSnapshot,
) !void {
    const query = runtime_query.init(room);
    const summary = try query.summarizeObservedNeighborPatterns(allocator);
    defer summary.deinit(allocator);

    try writer.print(
        "event=neighbor_pattern_summary origin_cell_count={d} occupied_surface_count={d} empty_count={d} out_of_bounds_count={d} missing_top_surface_count={d} standable_neighbor_count={d} blocked_neighbor_count={d} top_y_delta_buckets=",
        .{
            summary.origin_cell_count,
            summary.occupied_surface_count,
            summary.empty_count,
            summary.out_of_bounds_count,
            summary.missing_top_surface_count,
            summary.standable_neighbor_count,
            summary.blocked_neighbor_count,
        },
    );
    try printObservedNeighborPatternBuckets(writer, summary.top_y_delta_buckets);
    try writer.writeAll("\n");
}

fn printObservedNeighborPatternBuckets(
    writer: anytype,
    buckets: []const runtime_query.ObservedTopYDeltaBucket,
) !void {
    if (buckets.len == 0) {
        try writer.writeAll("none");
        return;
    }

    for (buckets, 0..) |bucket, index| {
        if (index != 0) try writer.writeAll("|");
        try writer.print("{d}:{d}", .{ bucket.delta, bucket.count });
    }
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
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    const writer = &output.writer;
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

    return output.toOwnedSlice();
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

fn formatOptionalTrackLabel(buffer: []u8, track_label: ?u8) []const u8 {
    return if (track_label) |value|
        std.fmt.bufPrint(buffer, "{d}", .{value}) catch unreachable
    else
        "NONE";
}

fn runtimeBonusKindLabel(kind: runtime_session.RuntimeBonusKind) []const u8 {
    return switch (kind) {
        .magic => "MAG",
        .little_key => "KEY",
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

fn formatRawInvalidStartMappingHintLine(
    buffer: []u8,
    hint: ?ViewerRawInvalidStartMappingHint,
) []const u8 {
    const resolved = hint orelse return "ALT MAP NONE";

    var hypothesis_buffer: [48]u8 = undefined;
    var cell_buffer: [16]u8 = undefined;
    var exact_buffer: [48]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "ALT MAP {s} CELL {s} {s}",
        .{
            upperTag(&hypothesis_buffer, @tagName(resolved.hypothesis)),
            formatOptionalCell(&cell_buffer, resolved.raw_cell),
            upperTag(&exact_buffer, @tagName(resolved.exact_status)),
        },
    ) catch unreachable;
}

fn formatRawInvalidStartMappingHintDiagnostic(
    buffer: []u8,
    hint: ?ViewerRawInvalidStartMappingHint,
) []const u8 {
    const resolved = hint orelse return "none";

    var cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "{s}:{d}:{s}:{s}:{s}:{d}:{d}",
        .{
            @tagName(resolved.hypothesis),
            resolved.cell_span_xz,
            formatOptionalCell(&cell_buffer, resolved.raw_cell),
            @tagName(resolved.exact_status),
            @tagName(resolved.disposition),
            resolved.better_metric_count,
            resolved.worse_metric_count,
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

fn formatAcceptedRawZoneRecoveryMoveLine(buffer: []u8, direction: CardinalDirection) []const u8 {
    var direction_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "RAW MOVE {s} ACCEPTED",
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

    var writer = std.Io.Writer.fixed(buffer);
    writer.writeAll("ZONES ") catch unreachable;
    for (zones, 0..) |zone, index| {
        if (index != 0) writer.writeAll("|") catch unreachable;
        writer.print("{d}", .{zone.index}) catch unreachable;
    }
    return writer.buffered();
}

fn formatZoneDiagnosticValue(buffer: []u8, zone_membership: runtime_locomotion.ZoneMembership) []const u8 {
    const zones = zone_membership.slice();
    if (zones.len == 0) return "none";

    var writer = std.Io.Writer.fixed(buffer);
    for (zones, 0..) |zone, index| {
        if (index != 0) writer.writeAll("|") catch unreachable;
        writer.print("{d}", .{zone.index}) catch unreachable;
    }
    return writer.buffered();
}

fn formatLocalTopologyHudLine(
    buffer: []u8,
    local_topology: ViewerLocalNeighborTopology,
) []const u8 {
    var token_buffers: [4][16]u8 = undefined;
    var writer = std.Io.Writer.fixed(buffer);
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
    return writer.buffered();
}

fn formatLocalTopologyDiagnosticValue(
    buffer: []u8,
    local_topology: ViewerLocalNeighborTopology,
) []const u8 {
    var cell_buffers: [4][16]u8 = undefined;
    var standability_buffers: [4][16]u8 = undefined;
    var delta_buffers: [4][16]u8 = undefined;
    var writer = std.Io.Writer.fixed(buffer);
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
    return writer.buffered();
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
    var writer = std.Io.Writer.fixed(buffer);
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
    return writer.buffered();
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
    var writer = std.Io.Writer.fixed(buffer);
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
    return writer.buffered();
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
