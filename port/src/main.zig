const std = @import("std");
const fragment_compare = @import("app/viewer/fragment_compare.zig");
const viewer_shell = @import("app/viewer_shell.zig");
const catalog = @import("assets/catalog.zig");
const diagnostics = @import("foundation/diagnostics.zig");
const paths = @import("foundation/paths.zig");
const process = @import("foundation/process.zig");
const reference_metadata = @import("generated/reference_metadata.zig");
const sdl = @import("platform/sdl.zig");
const locomotion = @import("runtime/locomotion.zig");
const runtime_object_behavior = @import("runtime/object_behavior.zig");
const runtime_query = @import("runtime/world_query.zig");
const room_state = @import("runtime/room_state.zig");
const runtime_session_mod = @import("runtime/session.zig");
const runtime_transition = @import("runtime/transition.zig");
const runtime_update = @import("runtime/update.zig");
const zone_effects = @import("runtime/zone_effects.zig");

const sendell_ball_flag_index: u8 = reference_metadata.sendell_ball_flag.index;
const lightning_spell_flag_index: u8 = reference_metadata.lightning_spell_flag.index;

pub fn main(init: std.process.Init) !void {
    return process.runWithArgs(init, run);
}

fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const parsed = viewer_shell.parseArgs(allocator, args) catch |err| {
        diagnostics.reportError(stderr, @errorName(err));
        return err;
    };
    defer parsed.deinit(allocator);

    const resolved = paths.resolveFromExecutable(allocator, parsed.asset_root_override) catch |err| {
        diagnostics.reportError(stderr, @errorName(err));
        return err;
    };
    defer resolved.deinit(allocator);

    catalog.validateExplicitRequirements(resolved.asset_root) catch |err| {
        diagnostics.reportError(stderr, @errorName(err));
        return err;
    };

    var room = room_state.loadRoomSnapshot(
        allocator,
        resolved,
        parsed.scene_entry,
        parsed.background_entry,
    ) catch |err| {
        if (err == error.ViewerUnsupportedSceneLife) {
            const hit = try room_state.inspectUnsupportedSceneLifeHit(
                allocator,
                resolved,
                parsed.scene_entry,
            );
            try printUnsupportedSceneLifeDiagnostic(
                stderr,
                parsed.scene_entry,
                parsed.background_entry,
                hit,
            );
        }
        diagnostics.reportError(stderr, @errorName(err));
        return err;
    };
    defer room.deinit(allocator);

    var runtime_session = try viewer_shell.initSession(allocator, &room);
    defer runtime_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, runtime_session);
    try viewer_shell.printStartupDiagnostics(stderr, allocator, resolved, &room);
    try viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status);
    var render = viewer_shell.buildRenderSnapshot(&room, runtime_session);
    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    var fragment_catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, render);
    defer fragment_catalog.deinit(allocator);
    var interaction = viewer_shell.initialInteractionState(fragment_catalog);
    const title = try viewer_shell.formatWindowTitleZ(allocator, &room);
    defer allocator.free(title);
    try stderr.flush();

    var canvas = sdl.Canvas.init(
        title,
        viewer_shell.window_width,
        viewer_shell.window_height,
    ) catch |err| {
        diagnostics.reportError(stderr, sdlErrorMessage(err));
        return err;
    };
    defer canvas.deinit();

    viewer_shell.renderDebugViewWithSelection(
        &canvas,
        render,
        fragment_catalog,
        interaction.fragment_selection,
        locomotion_status,
        interaction.control_mode,
        interaction.sidebar_tab,
        interaction.zoom_level,
        interaction.view_mode,
        viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &room, runtime_session),
        runtime_session.rewardCollectibles(),
    ) catch |err| {
        diagnostics.reportError(stderr, sdlErrorMessage(err));
        return err;
    };

    while (true) {
        const event = canvas.waitEvent() catch |err| {
            diagnostics.reportError(stderr, sdlErrorMessage(err));
            return err;
        };
        switch (event) {
            .quit => break,
            .redraw => try renderCurrentFrame(
                allocator,
                &canvas,
                stderr,
                &room,
                runtime_session,
                &render,
                &fragment_catalog,
                interaction,
                locomotion_status,
            ),
            .key_down => |key| try processKeyDownEvent(
                allocator,
                &canvas,
                stderr,
                &room,
                &runtime_session,
                &render,
                &fragment_catalog,
                &interaction,
                &locomotion_status,
                key,
                resolved,
            ),
            .other => {},
        }
    }

    try stderr.print(
        "status=ok event=shutdown scene_entry={d} background_entry={d}\n",
        .{ parsed.scene_entry, parsed.background_entry },
    );
    try stderr.flush();
}

fn sdlErrorMessage(err: anyerror) []const u8 {
    return if (err == error.SdlInitFailed or
        err == error.SdlCreateWindowFailed or
        err == error.SdlCreateRendererFailed or
        err == error.SdlSetRenderBlendModeFailed or
        err == error.SdlSetRenderDrawColorFailed or
        err == error.SdlRenderClearFailed or
        err == error.SdlRenderDrawLineFailed or
        err == error.SdlRenderDrawRectFailed or
        err == error.SdlRenderFillRectFailed or
        err == error.SdlWaitEventFailed)
        sdl.lastError()
    else
        @errorName(err);
}

fn printUnsupportedSceneLifeDiagnostic(
    writer: anytype,
    scene_entry_index: usize,
    background_entry_index: usize,
    hit: room_state.UnsupportedSceneLifeHit,
) !void {
    var classic_loader_scene_number_buffer: [16]u8 = undefined;
    var object_index_buffer: [16]u8 = undefined;
    try writer.print(
        "event=room_load_rejected scene_entry_index={d} background_entry_index={d} reason=unsupported_life_blob classic_loader_scene_number={s} scene_kind={s} unsupported_life_owner_kind={s} unsupported_life_object_index={s} unsupported_life_opcode_name={s} unsupported_life_opcode_id={d} unsupported_life_offset={d}\n",
        .{
            scene_entry_index,
            background_entry_index,
            formatOptionalUsize(&classic_loader_scene_number_buffer, hit.classic_loader_scene_number),
            hit.scene_kind,
            lifeOwnerKind(hit.owner),
            formatOptionalUsize(&object_index_buffer, lifeOwnerObjectIndex(hit.owner)),
            hit.unsupported_opcode_mnemonic,
            hit.unsupported_opcode_id,
            hit.byte_offset,
        },
    );
}

fn formatOptionalUsize(buffer: []u8, value: ?usize) []const u8 {
    const resolved = value orelse return "none";
    return std.fmt.bufPrint(buffer, "{d}", .{resolved}) catch unreachable;
}

fn lifeOwnerKind(owner: anytype) []const u8 {
    return switch (owner) {
        .hero => "hero",
        .object => "object",
    };
}

fn lifeOwnerObjectIndex(owner: anytype) ?usize {
    return switch (owner) {
        .hero => null,
        .object => |object_index| object_index,
    };
}

fn renderCurrentFrame(
    allocator: std.mem.Allocator,
    canvas: *sdl.Canvas,
    stderr: anytype,
    room: *const viewer_shell.RoomSnapshot,
    runtime_session: viewer_shell.Session,
    render: *viewer_shell.RenderSnapshot,
    fragment_catalog: *viewer_shell.FragmentComparisonCatalog,
    interaction: viewer_shell.ViewerInteractionState,
    locomotion_status: viewer_shell.ViewerLocomotionStatus,
) !void {
    const next_render = viewer_shell.buildRenderSnapshot(room, runtime_session);
    const next_catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, next_render);
    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    fragment_catalog.deinit(allocator);
    render.* = next_render;
    fragment_catalog.* = next_catalog;
    viewer_shell.renderDebugViewWithSelection(
        canvas,
        render.*,
        fragment_catalog.*,
        interaction.fragment_selection,
        locomotion_status,
        interaction.control_mode,
        interaction.sidebar_tab,
        interaction.zoom_level,
        interaction.view_mode,
        viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, room, runtime_session),
        runtime_session.rewardCollectibles(),
    ) catch |err| {
        diagnostics.reportError(stderr, sdlErrorMessage(err));
        return err;
    };
}

fn processKeyDownEvent(
    allocator: std.mem.Allocator,
    canvas: *sdl.Canvas,
    stderr: anytype,
    room: *viewer_shell.RoomSnapshot,
    runtime_session: *viewer_shell.Session,
    render: *viewer_shell.RenderSnapshot,
    fragment_catalog: *viewer_shell.FragmentComparisonCatalog,
    interaction: *viewer_shell.ViewerInteractionState,
    locomotion_status: *viewer_shell.ViewerLocomotionStatus,
    key: viewer_shell.ViewerKey,
    resolved: paths.ResolvedPaths,
) !void {
    const key_result = try viewer_shell.handleKeyDown(
        room,
        runtime_session,
        fragment_catalog.*,
        interaction.*,
        locomotion_status.*,
        key,
    );
    interaction.* = key_result.interaction;
    locomotion_status.* = key_result.locomotion_status;
    try applyScheduledWorldStep(
        allocator,
        resolved,
        stderr,
        room,
        runtime_session,
        locomotion_status,
        key_result,
    );
    try stderr.flush();
    try renderCurrentFrame(
        allocator,
        canvas,
        stderr,
        room,
        runtime_session.*,
        render,
        fragment_catalog,
        interaction.*,
        locomotion_status.*,
    );
}

fn applyScheduledWorldStep(
    allocator: std.mem.Allocator,
    resolved: paths.ResolvedPaths,
    stderr: anytype,
    room: *viewer_shell.RoomSnapshot,
    runtime_session: *viewer_shell.Session,
    locomotion_status: *viewer_shell.ViewerLocomotionStatus,
    key_result: viewer_shell.ViewerKeyDownResult,
) !void {
    switch (key_result.post_key_action) {
        .none => {
            if (key_result.should_print_locomotion_diagnostic) {
                try viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status.*);
            }
        },
        .apply_validation_zone_effects => {
            const exact_zones = try runtime_query.init(room).containingZonesAtWorldPoint(runtime_session.heroWorldPosition());
            const effect_summary = try zone_effects.applyContainingZoneEffects(room, runtime_session, exact_zones.slice());
            try printSecretRoomDoorEvent(stderr, room, runtime_session.*, effect_summary.secret_room_door_event);
            if (effect_summary.triggered_room_transition) {
                try applyPendingTransitionAndPrint(
                    allocator,
                    resolved,
                    stderr,
                    room,
                    runtime_session,
                    locomotion_status,
                    key_result.locomotion_status,
                );
            } else {
                locomotion_status.* = key_result.locomotion_status;
            }
            if (key_result.should_print_locomotion_diagnostic) {
                try viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status.*);
            }
        },
        .advance_world => {
            const previous_bonus_event_count = runtime_session.bonusSpawnEvents().len;
            const previous_reward_pickup_event_count = runtime_session.rewardPickupEvents().len;
            const tick_result = try runtime_update.tick(room, runtime_session);
            try printSecretRoomDoorEvent(stderr, room, runtime_session.*, tick_result.secret_room_door_event);
            if (tick_result.triggered_room_transition) {
                try applyPendingTransitionAndPrint(
                    allocator,
                    resolved,
                    stderr,
                    room,
                    runtime_session,
                    locomotion_status,
                    tick_result.locomotion_status,
                );
            } else {
                locomotion_status.* = tick_result.locomotion_status;
                if (tick_result.consumed_hero_intent or key_result.should_print_locomotion_diagnostic) {
                    try viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status.*);
                }
                try printNewBonusSpawnEvents(
                    stderr,
                    room,
                    runtime_session.*,
                    previous_bonus_event_count,
                );
                try printNewRewardPickupEvents(
                    stderr,
                    room,
                    runtime_session.*,
                    previous_reward_pickup_event_count,
                );
            }
        },
    }
}

fn applyPendingTransitionAndPrint(
    allocator: std.mem.Allocator,
    resolved: paths.ResolvedPaths,
    stderr: anytype,
    room: *viewer_shell.RoomSnapshot,
    runtime_session: *viewer_shell.Session,
    locomotion_status: *viewer_shell.ViewerLocomotionStatus,
    pre_transition_locomotion_status: viewer_shell.ViewerLocomotionStatus,
) !void {
    const transition_result = try runtime_transition.applyPendingRoomTransition(
        allocator,
        resolved,
        room,
        runtime_session,
        locomotion_status,
        pre_transition_locomotion_status,
    );
    try printTransitionResult(stderr, transition_result);
    switch (transition_result) {
        .committed => try viewer_shell.printStartupDiagnostics(stderr, allocator, resolved, room),
        .rejected => {},
    }
    locomotion_status.* = try locomotion.inspectCurrentStatus(room, runtime_session.*);
    try viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status.*);
}

fn printSecretRoomDoorEvent(
    stderr: anytype,
    room: *const viewer_shell.RoomSnapshot,
    runtime_session: viewer_shell.Session,
    event: ?zone_effects.SecretRoomDoorEvent,
) !void {
    const door_event = event orelse return;
    try stderr.print(
        "event=secret_room_door scene_entry_index={d} background_entry_index={d} status={s} hero_little_keys={d}\n",
        .{
            room.scene.entry_index,
            room.background.entry_index,
            secretRoomDoorEventLabel(door_event),
            runtime_session.littleKeyCount(),
        },
    );
}

fn secretRoomDoorEventLabel(event: zone_effects.SecretRoomDoorEvent) []const u8 {
    return switch (event) {
        .house_locked_no_key => "locked_no_key",
        .house_consumed_key => "key_consumed",
        .cellar_return_free => "free_return",
    };
}

fn printNewBonusSpawnEvents(
    stderr: anytype,
    room: *const viewer_shell.RoomSnapshot,
    runtime_session: viewer_shell.Session,
    previous_bonus_event_count: usize,
) !void {
    const events = runtime_session.bonusSpawnEvents();
    if (events.len <= previous_bonus_event_count) return;

    for (events[previous_bonus_event_count..]) |event| {
        const behavior_state = runtime_session.objectBehaviorStateByIndex(event.source_object_index);
        try stderr.print(
            "event=bonus_spawn scene_entry_index={d} background_entry_index={d} frame_index={d} source_object_index={d} kind={s} sprite_index={d} quantity={d} emitted_bonus_count={d} bonus_exhausted={}\n",
            .{
                room.scene.entry_index,
                room.background.entry_index,
                event.frame_index,
                event.source_object_index,
                @tagName(event.kind),
                event.sprite_index,
                event.quantity,
                if (behavior_state) |state| state.emitted_bonus_count else @as(u8, 0),
                if (behavior_state) |state| state.bonus_exhausted else false,
            },
        );
    }
}

fn printNewRewardPickupEvents(
    stderr: anytype,
    room: *const viewer_shell.RoomSnapshot,
    runtime_session: viewer_shell.Session,
    previous_reward_pickup_event_count: usize,
) !void {
    const events = runtime_session.rewardPickupEvents();
    if (events.len <= previous_reward_pickup_event_count) return;

    for (events[previous_reward_pickup_event_count..]) |event| {
        try stderr.print(
            "event=bonus_pickup scene_entry_index={d} background_entry_index={d} frame_index={d} source_object_index={d} kind={s} sprite_index={d} quantity={d} hero_magic_level={d} hero_magic_point={d} hero_little_keys={d}\n",
            .{
                room.scene.entry_index,
                room.background.entry_index,
                event.pickup_frame_index,
                event.source_object_index,
                @tagName(event.kind),
                event.sprite_index,
                event.quantity,
                runtime_session.magicLevel(),
                runtime_session.magicPoint(),
                runtime_session.littleKeyCount(),
            },
        );
    }
}

fn printTransitionResult(stderr: anytype, transition_result: runtime_transition.TransitionApplyResult) !void {
    switch (transition_result) {
        .committed => |value| try stderr.print(
            "event=room_transition_committed source_scene_entry_index={d} source_background_entry_index={d} destination_cube={d} destination_scene_entry_index={d} destination_background_entry_index={d} hero_x={d} hero_y={d} hero_z={d}\n",
            .{
                value.source_scene_entry_index,
                value.source_background_entry_index,
                value.destination_cube,
                value.destination_scene_entry_index,
                value.destination_background_entry_index,
                value.hero_position.x,
                value.hero_position.y,
                value.hero_position.z,
            },
        ),
        .rejected => |value| {
            if (value.post_load_adjustment_failure) |failure| {
                var post_load_raw_cell_buffer: [32]u8 = undefined;
                var post_load_occupied_bounds_buffer: [48]u8 = undefined;
                try stderr.print(
                    "event=room_transition_rejected source_scene_entry_index={d} source_background_entry_index={d} destination_cube={d} reason={s} hero_x={d} hero_y={d} hero_z={d} post_load_target_status={s} post_load_raw_cell={s} post_load_raw_cell_status={s} post_load_occupied_coverage={s} post_load_occupied_bounds={s} post_load_occupied_bounds_dx={d} post_load_occupied_bounds_dz={d} post_load_shadow_adjustment_failure={s} provisional_x={d} provisional_y={d} provisional_z={d}\n",
                    .{
                        value.source_scene_entry_index,
                        value.source_background_entry_index,
                        value.destination_cube,
                        @tagName(value.reason),
                        value.hero_position.x,
                        value.hero_position.y,
                        value.hero_position.z,
                        @tagName(failure.move_target_status),
                        formatPostLoadRawCell(&post_load_raw_cell_buffer, failure.raw_cell),
                        @tagName(failure.raw_cell.status),
                        @tagName(failure.occupied_coverage.relation),
                        formatPostLoadOccupiedBounds(&post_load_occupied_bounds_buffer, failure.occupied_coverage),
                        failure.occupied_coverage.x_cells_from_bounds,
                        failure.occupied_coverage.z_cells_from_bounds,
                        formatOptionalShadowAdjustmentFailure(failure.shadow_adjustment_failure),
                        failure.provisional_world_position.x,
                        failure.provisional_world_position.y,
                        failure.provisional_world_position.z,
                    },
                );
            } else {
                try stderr.print(
                    "event=room_transition_rejected source_scene_entry_index={d} source_background_entry_index={d} destination_cube={d} reason={s} hero_x={d} hero_y={d} hero_z={d}\n",
                    .{
                        value.source_scene_entry_index,
                        value.source_background_entry_index,
                        value.destination_cube,
                        @tagName(value.reason),
                        value.hero_position.x,
                        value.hero_position.y,
                        value.hero_position.z,
                    },
                );
            }
        },
    }
}

fn formatPostLoadRawCell(
    buffer: []u8,
    probe: runtime_query.WorldPointCellProbe,
) []const u8 {
    const cell = probe.cell orelse return "none";
    return std.fmt.bufPrint(buffer, "{d}/{d}", .{ cell.x, cell.z }) catch "format_error";
}

fn formatPostLoadOccupiedBounds(
    buffer: []u8,
    coverage: runtime_query.OccupiedCoverageProbe,
) []const u8 {
    const bounds = coverage.occupied_bounds orelse return "none";
    return std.fmt.bufPrint(
        buffer,
        "{d}..{d}/{d}..{d}",
        .{ bounds.min_x, bounds.max_x, bounds.min_z, bounds.max_z },
    ) catch "format_error";
}

fn formatOptionalShadowAdjustmentFailure(
    failure: ?runtime_transition.ShadowAdjustmentFailure,
) []const u8 {
    return if (failure) |value| @tagName(value) else "none";
}

test "unsupported pending room-transition semantics stay diagnostic-only and keep the current room live" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 36, 36);
    defer room.deinit(allocator);

    var runtime_session = try viewer_shell.initSession(allocator, &room);
    defer runtime_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, runtime_session);

    const transition_zone = blk: {
        for (room.scene.zones) |zone| {
            if (zone.kind == .change_cube) break :blk zone;
        }
        return error.MissingChangeCubeZone;
    };
    const semantics = switch (transition_zone.semantics) {
        .change_cube => |value| value,
        else => return error.ExpectedChangeCubeSemantics,
    };
    try runtime_session.setPendingRoomTransition(.{
        .source_zone_index = transition_zone.index,
        .destination_cube = semantics.destination_cube,
        .destination_world_position_kind = .provisional_zone_relative,
        .destination_world_position = .{
            .x = semantics.destination_x,
            .y = semantics.destination_y,
            .z = semantics.destination_z,
        },
        .yaw = semantics.yaw,
        .test_brick = semantics.test_brick,
        .dont_readjust_twinsen = semantics.dont_readjust_twinsen,
    });

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    const transition_result = try runtime_transition.applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &runtime_session,
        &locomotion_status,
        locomotion_status,
    );
    try printTransitionResult(&output.writer, transition_result);
    switch (transition_result) {
        .rejected => |value| try std.testing.expectEqual(runtime_transition.TransitionRejectionReason.unsupported_yaw, value.reason),
        .committed => return error.UnexpectedCommittedRoomTransition,
    }
    try std.testing.expectEqual(@as(usize, 36), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 36), room.background.entry_index);
    try std.testing.expectEqual(@as(?runtime_session_mod.PendingRoomTransition, null), runtime_session.pendingRoomTransition());
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "event=room_transition_rejected") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "reason=unsupported_yaw") != null);
}

test "transition rejection diagnostics include post-load adjustment details when present" {
    const allocator = std.testing.allocator;

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    try printTransitionResult(&output.writer, .{
        .rejected = .{
            .source_scene_entry_index = 3,
            .source_background_entry_index = 3,
            .destination_cube = 19,
            .reason = .unsupported_destination_post_load_adjustment,
            .hero_position = .{ .x = 0, .y = 0, .z = 0 },
            .post_load_adjustment_failure = .{
                .provisional_world_position = .{ .x = 29184, .y = 3840, .z = 28416 },
                .move_target_status = .target_height_mismatch,
                .raw_cell = .{
                    .world_x = 29184,
                    .world_z = 28416,
                    .cell = .{ .x = 57, .z = 55 },
                    .status = .occupied_surface,
                    .occupied = true,
                    .surface = null,
                    .standability = null,
                },
                .occupied_coverage = .{
                    .relation = .within_occupied_bounds,
                    .occupied_bounds = .{
                        .min_x = 40,
                        .max_x = 60,
                        .min_z = 20,
                        .max_z = 55,
                    },
                    .x_cells_from_bounds = 0,
                    .z_cells_from_bounds = 0,
                },
                .shadow_adjustment_failure = .world_cell_empty,
            },
        },
    });

    try std.testing.expect(std.mem.indexOf(u8, output.written(), "post_load_target_status=target_height_mismatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "post_load_raw_cell=57/55") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "post_load_occupied_coverage=within_occupied_bounds") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "post_load_occupied_bounds=40..60/20..55") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "post_load_shadow_adjustment_failure=world_cell_empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "provisional_x=29184 provisional_y=3840 provisional_z=28416") != null);
}

test "viewer scheduler rejects the guarded 2/2 public exit as an unsupported exterior destination" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    var runtime_session = try viewer_shell.initSession(allocator, &room);
    defer runtime_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, runtime_session);
    const initial_render = viewer_shell.buildRenderSnapshot(&room, runtime_session);
    var initial_catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, initial_render);
    defer initial_catalog.deinit(allocator);
    const initial_interaction = viewer_shell.initialInteractionState(initial_catalog);
    try std.testing.expectEqual(viewer_shell.ViewerControlMode.locomotion, initial_interaction.control_mode);

    const move_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        initial_catalog,
        initial_interaction,
        locomotion_status,
        .right,
    );
    locomotion_status = move_result.locomotion_status;
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, move_result.post_key_action);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    try applyScheduledWorldStep(
        allocator,
        resolved,
        &output.writer,
        &room,
        &runtime_session,
        &locomotion_status,
        move_result,
    );

    const raw_start = room_state.heroStartWorldPoint(&room);
    try std.testing.expectEqual(@as(?runtime_session_mod.PendingRoomTransition, null), runtime_session.pendingRoomTransition());
    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 2), room.background.entry_index);
    try std.testing.expectEqual(raw_start.x + locomotion.raw_invalid_zone_entry_step_xz, runtime_session.heroWorldPosition().x);
    try std.testing.expectEqual(raw_start.y, runtime_session.heroWorldPosition().y);
    try std.testing.expectEqual(raw_start.z, runtime_session.heroWorldPosition().z);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "event=room_transition_rejected") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "reason=unsupported_exterior_destination_cube") != null);
}

test "viewer secret-room validation door probes consume keys and return freely" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var runtime_session = try viewer_shell.initSession(allocator, &room);
    defer runtime_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, runtime_session);
    const initial_render = viewer_shell.buildRenderSnapshot(&room, runtime_session);
    var initial_catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, initial_render);
    defer initial_catalog.deinit(allocator);
    const initial_interaction = viewer_shell.initialInteractionState(initial_catalog);

    const locked_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        initial_catalog,
        initial_interaction,
        locomotion_status,
        .proof_house_door,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.apply_validation_zone_effects, locked_result.post_key_action);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    try applyScheduledWorldStep(
        allocator,
        resolved,
        &output.writer,
        &room,
        &runtime_session,
        &locomotion_status,
        locked_result,
    );
    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 1), room.background.entry_index);
    try std.testing.expectEqual(@as(u8, 0), runtime_session.littleKeyCount());
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "event=secret_room_door") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "status=locked_no_key") != null);

    output.clearRetainingCapacity();
    runtime_session.setLittleKeyCount(1);
    const keyed_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        initial_catalog,
        initial_interaction,
        locomotion_status,
        .proof_house_door,
    );
    try applyScheduledWorldStep(
        allocator,
        resolved,
        &output.writer,
        &room,
        &runtime_session,
        &locomotion_status,
        keyed_result,
    );
    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 0), room.background.entry_index);
    try std.testing.expectEqual(@as(u8, 0), runtime_session.littleKeyCount());
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "status=key_consumed") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "event=room_transition_committed") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "destination_background_entry_index=0") != null);

    output.clearRetainingCapacity();
    const cellar_render = viewer_shell.buildRenderSnapshot(&room, runtime_session);
    var cellar_catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, cellar_render);
    defer cellar_catalog.deinit(allocator);
    const return_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        cellar_catalog,
        viewer_shell.initialInteractionState(cellar_catalog),
        locomotion_status,
        .proof_cellar_return,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.apply_validation_zone_effects, return_result.post_key_action);
    try applyScheduledWorldStep(
        allocator,
        resolved,
        &output.writer,
        &room,
        &runtime_session,
        &locomotion_status,
        return_result,
    );
    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 1), room.background.entry_index);
    try std.testing.expectEqual(@as(u8, 0), runtime_session.littleKeyCount());
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "status=free_return") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "destination_background_entry_index=1") != null);
}

test "committed room transitions reapply canonical destination room-entry seeding" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var destination_room = try room_state.loadRoomSnapshot(allocator, resolved, 36, 36);
    defer destination_room.deinit(allocator);

    var expected_destination_session = try viewer_shell.initSession(allocator, &destination_room);
    defer expected_destination_session.deinit(allocator);
    const destination_world_position = try viewer_shell.seedSessionToLocomotionFixture(
        &destination_room,
        &expected_destination_session,
    );

    var runtime_session = try viewer_shell.initSession(allocator, &room);
    defer runtime_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, runtime_session);
    runtime_session.setMagicLevelAndRefill(5);
    runtime_session.setGameVar(sendell_ball_flag_index, 9);
    runtime_session.setGameVar(lightning_spell_flag_index, 0);
    try runtime_session.setPendingRoomTransition(.{
        .source_zone_index = 0,
        .destination_cube = 34,
        .destination_world_position_kind = .final_landing,
        .destination_world_position = destination_world_position,
        .yaw = 0,
        .test_brick = false,
        .dont_readjust_twinsen = false,
    });

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    const transition_result = try runtime_transition.applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &runtime_session,
        &locomotion_status,
        locomotion_status,
    );
    try printTransitionResult(&output.writer, transition_result);
    switch (transition_result) {
        .committed => {},
        .rejected => return error.UnexpectedRejectedRoomTransition,
    }
    try std.testing.expectEqual(@as(usize, 36), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 36), room.background.entry_index);
    try std.testing.expectEqual(@as(u8, 2), runtime_session.magicLevel());
    try std.testing.expectEqual(expected_destination_session.magicPoint(), runtime_session.magicPoint());
    try std.testing.expectEqual(
        expected_destination_session.gameVar(sendell_ball_flag_index),
        runtime_session.gameVar(sendell_ball_flag_index),
    );
    try std.testing.expectEqual(
        expected_destination_session.gameVar(lightning_spell_flag_index),
        runtime_session.gameVar(lightning_spell_flag_index),
    );
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "event=room_transition_committed") != null);
}

test "main bonus spawn diagnostics print the bounded 19/19 object-2 reward event" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var runtime_session = try viewer_shell.initSession(allocator, &room);
    defer runtime_session.deinit(allocator);
    runtime_session.setHeroWorldPosition(.{
        .x = 2500,
        .y = 1000,
        .z = 1000,
    });

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    _ = try runtime_object_behavior.stepSupportedObjects(&room, &runtime_session);
    runtime_session.advanceFrameIndex();
    const primed_state = runtime_session.objectBehaviorStateByIndexPtr(2) orelse return error.MissingRuntimeObjectBehaviorState;
    primed_state.last_hit_by = 1;

    var previous_bonus_event_count: usize = runtime_session.bonusSpawnEvents().len;
    var step_index: usize = 0;
    while (step_index < 16) : (step_index += 1) {
        _ = try runtime_object_behavior.stepSupportedObjects(&room, &runtime_session);
        try printNewBonusSpawnEvents(&output.writer, &room, runtime_session, previous_bonus_event_count);
        previous_bonus_event_count = runtime_session.bonusSpawnEvents().len;
        runtime_session.advanceFrameIndex();
        if (std.mem.indexOf(u8, output.written(), "event=bonus_spawn") != null) {
            break;
        }
    }

    try std.testing.expect(std.mem.indexOf(u8, output.written(), "event=bonus_spawn") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "scene_entry_index=19 background_entry_index=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "source_object_index=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "kind=magic") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "quantity=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "emitted_bonus_count=10") != null);
}

test "main bonus pickup diagnostics print the bounded 19/19 magic reward resolution" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var runtime_session = try viewer_shell.initSession(allocator, &room);
    defer runtime_session.deinit(allocator);
    runtime_session.setMagicLevelAndRefill(3);
    runtime_session.setMagicPoint(10);
    runtime_session.setHeroWorldPosition(.{
        .x = 2500,
        .y = 1000,
        .z = 1000,
    });

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    _ = try runtime_object_behavior.stepSupportedObjects(&room, &runtime_session);
    runtime_session.advanceFrameIndex();
    const primed_state = runtime_session.objectBehaviorStateByIndexPtr(2) orelse return error.MissingRuntimeObjectBehaviorState;
    primed_state.last_hit_by = 1;

    while (runtime_session.rewardCollectibles().len == 0) {
        _ = try runtime_object_behavior.stepSupportedObjects(&room, &runtime_session);
        runtime_session.advanceFrameIndex();
    }

    while (true) {
        var settled = true;
        for (runtime_session.rewardCollectibles()) |collectible| {
            if (!collectible.settled) {
                settled = false;
                break;
            }
        }
        if (settled) break;

        runtime_session.setHeroWorldPosition(runtime_query.gridCellCenterWorldPosition(39, 10, 25 * runtime_query.world_grid_span_y));
        _ = try runtime_update.tick(&room, &runtime_session);
    }

    runtime_session.setHeroWorldPosition(runtime_session.rewardCollectibles()[0].world_position);
    const previous_reward_pickup_event_count = runtime_session.rewardPickupEvents().len;
    _ = try runtime_update.tick(&room, &runtime_session);
    try printNewRewardPickupEvents(&output.writer, &room, runtime_session, previous_reward_pickup_event_count);

    try std.testing.expect(std.mem.indexOf(u8, output.written(), "event=bonus_pickup") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "scene_entry_index=19 background_entry_index=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "source_object_index=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "kind=magic") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "quantity=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "hero_magic_point=20") != null);
}
