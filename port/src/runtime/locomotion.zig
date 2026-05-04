const std = @import("std");
const room_state = @import("room_state.zig");
const runtime_query = @import("world_query.zig");
const runtime_session = @import("session.zig");
const world_geometry = @import("world_geometry.zig");

pub const CardinalDirection = world_geometry.CardinalDirection;
pub const GridCell = world_geometry.GridCell;
pub const WorldPointSnapshot = world_geometry.WorldPointSnapshot;
pub const ZoneMembership = runtime_query.ContainingZoneSet;
pub const LocalNeighborTopology = runtime_query.LocalNeighborTopologyProbe;
pub const HeroIntent = runtime_session.HeroIntent;
pub const raw_invalid_zone_entry_step_xz: i32 = 32;
pub const behavior_movement_speed_startup_otringal_contract = "behavior_movement_speed_startup_otringal";

pub const BehaviorMovementProfile = struct {
    mode: runtime_session.BehaviorMode,
    startup_ms: u16,
    distance_z_at_2000ms: i32,
};

pub const RootMotionKeyframe = struct {
    duration_ms: u16,
    root_z: i32,
};

pub const BehaviorWalkRootMotion = struct {
    mode: runtime_session.BehaviorMode,
    animation_asset: []const u8,
    file3d_object: u8,
    loop_start_keyframe: u8,
    keyframes: []const RootMotionKeyframe,

    pub fn distanceZAt(self: BehaviorWalkRootMotion, elapsed_ms: u16) i32 {
        return rootMotionDistanceZAt(
            self.keyframes,
            self.loop_start_keyframe,
            elapsed_ms,
        );
    }
};

pub const HeldForwardMovementState = struct {
    mode: runtime_session.BehaviorMode,
    elapsed_ms: u16 = 0,
    previous_forward_distance_z: i32 = 0,
};

pub const HeldForwardMovementDelta = struct {
    mode: runtime_session.BehaviorMode,
    previous_elapsed_ms: u16,
    elapsed_ms: u16,
    previous_forward_distance_z: i32,
    forward_distance_z: i32,
    forward_delta_z: i32,
};

pub const LocomotionRejectedStage = enum {
    origin_invalid,
    target_rejected,
};

pub const CardinalMoveOption = struct {
    direction: CardinalDirection,
    target_cell: ?GridCell,
    status: runtime_query.MoveTargetStatus,
    occupied_coverage: runtime_query.OccupiedCoverageProbe,
};

pub const MoveOptions = struct {
    current_cell: GridCell,
    options: [4]CardinalMoveOption,
};

pub const RawInvalidStartCandidate = struct {
    kind: runtime_query.DiagnosticCandidateKind,
    cell: GridCell,
    x_distance: i32,
    z_distance: i32,
    distance_sq: i64,
};

pub const RawInvalidStartMappingHint = struct {
    hypothesis: runtime_query.MappingHypothesis,
    cell_span_xz: i32,
    raw_cell: ?GridCell,
    exact_status: runtime_query.HeroStartExactStatus,
    diagnostic_status: runtime_query.HeroStartDiagnosticStatus,
    occupied_coverage: runtime_query.OccupiedCoverageProbe,
    disposition: runtime_query.MappingEvidenceDisposition,
    better_metric_count: u8,
    worse_metric_count: u8,
};

pub const RawInvalidStartStatus = struct {
    exact_status: runtime_query.HeroStartExactStatus,
    diagnostic_status: runtime_query.HeroStartDiagnosticStatus,
    raw_cell: ?GridCell,
    occupied_coverage: runtime_query.OccupiedCoverageProbe,
    nearest_occupied: ?RawInvalidStartCandidate,
    nearest_standable: ?RawInvalidStartCandidate,
    best_alt_mapping: ?RawInvalidStartMappingHint,
    hero_position: WorldPointSnapshot,
};

pub const RawInvalidCurrentStatus = struct {
    reason: runtime_query.MoveTargetStatus,
    raw_cell: ?GridCell,
    occupied_coverage: runtime_query.OccupiedCoverageProbe,
    hero_position: WorldPointSnapshot,
    zone_membership: ZoneMembership,
};

pub const SeededValidStatus = struct {
    cell: GridCell,
    move_options: MoveOptions,
    local_topology: LocalNeighborTopology,
    hero_position: WorldPointSnapshot,
    zone_membership: ZoneMembership,
};

pub const MoveAcceptedStatus = struct {
    direction: CardinalDirection,
    origin_cell: GridCell,
    cell: GridCell,
    move_options: MoveOptions,
    local_topology: LocalNeighborTopology,
    hero_position: WorldPointSnapshot,
    zone_membership: ZoneMembership,
};

pub const RawZoneRecoveryAcceptedStatus = struct {
    direction: CardinalDirection,
    hero_position: WorldPointSnapshot,
    zone_membership: ZoneMembership,
};

pub const MoveRejectedStatus = struct {
    direction: CardinalDirection,
    rejection_stage: LocomotionRejectedStage,
    reason: runtime_query.MoveTargetStatus,
    current_cell: ?GridCell,
    target_cell: ?GridCell,
    target_occupied_coverage: ?runtime_query.OccupiedCoverageProbe,
    move_options: ?MoveOptions,
    local_topology: ?LocalNeighborTopology,
    hero_position: WorldPointSnapshot,
    zone_membership: ZoneMembership,
};

pub const LocomotionStatus = union(enum) {
    raw_invalid_start: RawInvalidStartStatus,
    raw_invalid_current: RawInvalidCurrentStatus,
    seeded_valid: SeededValidStatus,
    last_move_accepted: MoveAcceptedStatus,
    last_zone_recovery_accepted: RawZoneRecoveryAcceptedStatus,
    last_move_rejected: MoveRejectedStatus,
};

pub fn behaviorMovementProfile(mode: runtime_session.BehaviorMode) BehaviorMovementProfile {
    return switch (mode) {
        .normal => .{
            .mode = .normal,
            .startup_ms = 371,
            .distance_z_at_2000ms = 2008,
        },
        .sporty => .{
            .mode = .sporty,
            .startup_ms = 211,
            .distance_z_at_2000ms = 5066,
        },
        .aggressive => .{
            .mode = .aggressive,
            .startup_ms = 105,
            .distance_z_at_2000ms = 2974,
        },
        .discreet => .{
            .mode = .discreet,
            .startup_ms = 478,
            .distance_z_at_2000ms = 772,
        },
    };
}

pub fn behaviorForwardHoldDistanceZ(mode: runtime_session.BehaviorMode, hold_ms: u16) i32 {
    const profile = behaviorMovementProfile(mode);
    if (hold_ms <= profile.startup_ms) return 0;

    const active_ms: i32 = @as(i32, hold_ms) - profile.startup_ms;
    const proved_active_ms: i32 = 2000 - profile.startup_ms;
    return @divTrunc(profile.distance_z_at_2000ms * active_ms, proved_active_ms);
}

const normal_walk_root_motion = [_]RootMotionKeyframe{
    .{ .duration_ms = 300, .root_z = 0 },
    .{ .duration_ms = 200, .root_z = 240 },
    .{ .duration_ms = 200, .root_z = 240 },
    .{ .duration_ms = 200, .root_z = 240 },
    .{ .duration_ms = 200, .root_z = 240 },
};

const sporty_walk_root_motion = [_]RootMotionKeyframe{
    .{ .duration_ms = 140, .root_z = 0 },
    .{ .duration_ms = 160, .root_z = 248 },
    .{ .duration_ms = 200, .root_z = 491 },
    .{ .duration_ms = 160, .root_z = 491 },
    .{ .duration_ms = 140, .root_z = 400 },
    .{ .duration_ms = 140, .root_z = 400 },
    .{ .duration_ms = 140, .root_z = 400 },
    .{ .duration_ms = 140, .root_z = 400 },
    .{ .duration_ms = 140, .root_z = 400 },
    .{ .duration_ms = 140, .root_z = 491 },
};

const aggressive_walk_root_motion = [_]RootMotionKeyframe{
    .{ .duration_ms = 240, .root_z = 298 },
    .{ .duration_ms = 160, .root_z = 257 },
    .{ .duration_ms = 160, .root_z = 229 },
    .{ .duration_ms = 160, .root_z = 148 },
    .{ .duration_ms = 160, .root_z = 286 },
    .{ .duration_ms = 160, .root_z = 178 },
    .{ .duration_ms = 160, .root_z = 274 },
    .{ .duration_ms = 160, .root_z = 202 },
    .{ .duration_ms = 160, .root_z = 345 },
    .{ .duration_ms = 160, .root_z = 288 },
    .{ .duration_ms = 160, .root_z = 222 },
    .{ .duration_ms = 160, .root_z = 291 },
};

const discreet_walk_root_motion = [_]RootMotionKeyframe{
    .{ .duration_ms = 400, .root_z = 0 },
    .{ .duration_ms = 400, .root_z = 277 },
    .{ .duration_ms = 400, .root_z = 239 },
    .{ .duration_ms = 300, .root_z = 100 },
    .{ .duration_ms = 300, .root_z = 100 },
    .{ .duration_ms = 300, .root_z = 100 },
    .{ .duration_ms = 400, .root_z = 200 },
    .{ .duration_ms = 300, .root_z = 100 },
    .{ .duration_ms = 300, .root_z = 100 },
    .{ .duration_ms = 300, .root_z = 100 },
};

pub fn behaviorWalkRootMotion(mode: runtime_session.BehaviorMode) BehaviorWalkRootMotion {
    return switch (mode) {
        .normal => .{
            .mode = .normal,
            .animation_asset = "ANIM.HQR:1",
            .file3d_object = 0,
            .loop_start_keyframe = 1,
            .keyframes = &normal_walk_root_motion,
        },
        .sporty => .{
            .mode = .sporty,
            .animation_asset = "ANIM.HQR:67",
            .file3d_object = 1,
            .loop_start_keyframe = 4,
            .keyframes = &sporty_walk_root_motion,
        },
        .aggressive => .{
            .mode = .aggressive,
            .animation_asset = "ANIM.HQR:83",
            .file3d_object = 2,
            .loop_start_keyframe = 0,
            .keyframes = &aggressive_walk_root_motion,
        },
        .discreet => .{
            .mode = .discreet,
            .animation_asset = "ANIM.HQR:94",
            .file3d_object = 3,
            .loop_start_keyframe = 2,
            .keyframes = &discreet_walk_root_motion,
        },
    };
}

pub fn behaviorWalkRootMotionDistanceZ(mode: runtime_session.BehaviorMode, elapsed_ms: u16) i32 {
    return behaviorWalkRootMotion(mode).distanceZAt(elapsed_ms);
}

pub fn beginHeldForwardMovement(mode: runtime_session.BehaviorMode) HeldForwardMovementState {
    return .{ .mode = mode };
}

pub fn advanceHeldForwardMovement(
    state: *HeldForwardMovementState,
    frame_delta_ms: u16,
) HeldForwardMovementDelta {
    const previous_elapsed_ms = state.elapsed_ms;
    const previous_forward_distance_z = state.previous_forward_distance_z;
    state.elapsed_ms = saturatingAddU16(state.elapsed_ms, frame_delta_ms);
    const forward_distance_z = behaviorWalkRootMotionDistanceZ(state.mode, state.elapsed_ms);
    state.previous_forward_distance_z = forward_distance_z;
    return .{
        .mode = state.mode,
        .previous_elapsed_ms = previous_elapsed_ms,
        .elapsed_ms = state.elapsed_ms,
        .previous_forward_distance_z = previous_forward_distance_z,
        .forward_distance_z = forward_distance_z,
        .forward_delta_z = forward_distance_z - previous_forward_distance_z,
    };
}

pub fn applyHeldForwardMovement(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    frame_delta_ms: u16,
) !LocomotionStatus {
    const query = runtime_query.init(room);
    const origin_position = current_session.heroWorldPosition();
    const origin = query.evaluateHeroMoveTarget(origin_position);
    if (!origin.isAllowed()) {
        current_session.clearHeldForwardMovement();
        return .{
            .last_move_rejected = .{
                .direction = .north,
                .rejection_stage = .origin_invalid,
                .reason = origin.status,
                .current_cell = origin.raw_cell.cell,
                .target_cell = origin.raw_cell.cell,
                .target_occupied_coverage = null,
                .move_options = null,
                .local_topology = null,
                .hero_position = origin_position,
                .zone_membership = .{},
            },
        };
    }
    const origin_cell = origin.raw_cell.cell orelse return error.LocomotionStatusMissingCell;

    const mode = current_session.behaviorMode();
    var movement = heldForwardStateForSession(current_session.*, mode);
    const delta = advanceHeldForwardMovement(&movement, frame_delta_ms);
    current_session.setHeldForwardMovement(.{
        .mode = movement.mode,
        .elapsed_ms = movement.elapsed_ms,
        .previous_forward_distance_z = movement.previous_forward_distance_z,
    });

    if (delta.forward_delta_z == 0) {
        return seededValidStatusFromEvaluation(query, origin_position, origin);
    }

    const facing_direction = cardinalDirectionForHeroBeta(current_session.heroBeta());
    const target_position = worldPointAdvancedInDirection(
        origin_position,
        delta.forward_delta_z,
        facing_direction,
    );
    const target = query.evaluateHeroMoveTarget(target_position);
    if (!target.isAllowed()) {
        current_session.clearHeldForwardMovement();
        return .{
            .last_move_rejected = .{
                .direction = facing_direction,
                .rejection_stage = .target_rejected,
                .reason = target.status,
                .current_cell = origin.raw_cell.cell,
                .target_cell = target.raw_cell.cell,
                .target_occupied_coverage = target.occupied_coverage,
                .move_options = try buildMoveOptions(query, origin_position),
                .local_topology = try buildLocalTopology(query, origin_cell),
                .hero_position = origin_position,
                .zone_membership = try query.containingZonesAtWorldPoint(origin_position),
            },
        };
    }

    current_session.setHeroWorldPosition(target_position);
    const updated_position = current_session.heroWorldPosition();
    const move_options = try buildMoveOptions(query, updated_position);
    return .{
        .last_move_accepted = .{
            .direction = facing_direction,
            .origin_cell = origin_cell,
            .cell = move_options.current_cell,
            .move_options = move_options,
            .local_topology = try buildLocalTopology(query, move_options.current_cell),
            .hero_position = updated_position,
            .zone_membership = try query.containingZonesAtWorldPoint(updated_position),
        },
    };
}

fn heldForwardStateForSession(
    current_session: runtime_session.Session,
    mode: runtime_session.BehaviorMode,
) HeldForwardMovementState {
    const stored = current_session.heldForwardMovement() orelse return beginHeldForwardMovement(mode);
    if (stored.mode != mode) return beginHeldForwardMovement(mode);
    return .{
        .mode = stored.mode,
        .elapsed_ms = stored.elapsed_ms,
        .previous_forward_distance_z = stored.previous_forward_distance_z,
    };
}

fn rootMotionDistanceZAt(
    keyframes: []const RootMotionKeyframe,
    loop_start_keyframe: u8,
    elapsed_ms: u16,
) i32 {
    std.debug.assert(keyframes.len > 0);
    std.debug.assert(loop_start_keyframe < keyframes.len);

    var distance_z: i32 = 0;
    var remaining_ms: u32 = elapsed_ms;

    for (keyframes) |keyframe| {
        if (remaining_ms == 0) return distance_z;
        if (remaining_ms < keyframe.duration_ms) {
            return distance_z + interpolateRootZFromZero(keyframe.root_z, remaining_ms, keyframe.duration_ms);
        }
        distance_z += keyframe.root_z;
        remaining_ms -= keyframe.duration_ms;
    }

    const loop_keyframes = keyframes[loop_start_keyframe..];
    const loop_duration_ms = sumRootMotionDuration(loop_keyframes);
    if (loop_duration_ms == 0) return distance_z;

    const loop_distance_z = sumRootMotionDistanceZ(loop_keyframes);
    const loop_cycles = remaining_ms / loop_duration_ms;
    distance_z += @as(i32, @intCast(loop_cycles)) * loop_distance_z;
    remaining_ms %= loop_duration_ms;

    for (loop_keyframes) |keyframe| {
        if (remaining_ms == 0) return distance_z;
        if (remaining_ms < keyframe.duration_ms) {
            return distance_z + interpolateRootZFromZero(keyframe.root_z, remaining_ms, keyframe.duration_ms);
        }
        distance_z += keyframe.root_z;
        remaining_ms -= keyframe.duration_ms;
    }

    return distance_z;
}

fn sumRootMotionDuration(keyframes: []const RootMotionKeyframe) u32 {
    var duration_ms: u32 = 0;
    for (keyframes) |keyframe| {
        duration_ms += keyframe.duration_ms;
    }
    return duration_ms;
}

fn sumRootMotionDistanceZ(keyframes: []const RootMotionKeyframe) i32 {
    var distance_z: i32 = 0;
    for (keyframes) |keyframe| {
        distance_z += keyframe.root_z;
    }
    return distance_z;
}

fn interpolateRootZFromZero(target_z: i32, elapsed_ms: u32, duration_ms: u16) i32 {
    if (duration_ms == 0) return target_z;
    const interpolator = @divTrunc(
        (@as(i64, elapsed_ms) << 16) + ((@as(i64, duration_ms) + 1) >> 1),
        @as(i64, duration_ms),
    );
    return @as(i32, @intCast((@as(i64, target_z) * interpolator) >> 16));
}

fn saturatingAddU16(lhs: u16, rhs: u16) u16 {
    const sum: u32 = @as(u32, lhs) + rhs;
    return @intCast(@min(sum, std.math.maxInt(u16)));
}

pub fn inspectCurrentStatus(
    room: *const room_state.RoomSnapshot,
    current_session: runtime_session.Session,
) !LocomotionStatus {
    const query = runtime_query.init(room);
    const hero_position = current_session.heroWorldPosition();
    if (std.meta.eql(hero_position, room_state.heroStartWorldPoint(room))) {
        const probe = try query.probeHeroStart();
        if (probe.exact_status != .valid) {
            const mapping_report = try query.evaluateHeroStartMappings();
            return .{
                .raw_invalid_start = .{
                    .exact_status = probe.exact_status,
                    .diagnostic_status = probe.diagnostic_status,
                    .raw_cell = probe.raw_cell.cell,
                    .occupied_coverage = probe.occupied_coverage,
                    .nearest_occupied = buildRawInvalidStartCandidate(probe.nearest_occupied),
                    .nearest_standable = buildRawInvalidStartCandidate(probe.nearest_standable),
                    .best_alt_mapping = buildRawInvalidStartMappingHint(mapping_report),
                    .hero_position = hero_position,
                },
            };
        }
    }

    const evaluation = query.evaluateHeroMoveTarget(hero_position);
    if (!evaluation.isAllowed()) {
        return .{
            .raw_invalid_current = .{
                .reason = evaluation.status,
                .raw_cell = evaluation.raw_cell.cell,
                .occupied_coverage = evaluation.occupied_coverage,
                .hero_position = hero_position,
                .zone_membership = try query.containingZonesAtWorldPoint(hero_position),
            },
        };
    }

    return seededValidStatusFromEvaluation(query, hero_position, evaluation);
}

pub fn inspectCurrentStatusRequiringAdmittedSeed(
    room: *const room_state.RoomSnapshot,
    current_session: runtime_session.Session,
) !LocomotionStatus {
    const query = runtime_query.init(room);
    const hero_position = current_session.heroWorldPosition();
    if (std.meta.eql(hero_position, room_state.heroStartWorldPoint(room))) {
        return inspectCurrentStatus(room, current_session);
    }

    return seededValidStatus(query, hero_position);
}

pub fn seedSessionToNearestStandableStart(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !WorldPointSnapshot {
    const query = runtime_query.init(room);
    const probe = try query.probeHeroStart();
    const candidate = probe.nearest_standable orelse return error.RuntimeStartSeedUnavailable;
    if (candidate.standability != .standable) return error.RuntimeStartSeedUnavailable;

    const position = runtime_query.gridCellCenterWorldPosition(
        candidate.cell.x,
        candidate.cell.z,
        candidate.surface.top_y,
    );
    current_session.setHeroWorldPosition(position);
    return position;
}

/// Diagnostic grid-cell movement for viewer/debug probes. Gameplay movement
/// should consume held-input root-motion deltas and then apply collision/floor
/// response; this path intentionally remains a discrete topology probe.
pub fn applyStep(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    direction: CardinalDirection,
) !LocomotionStatus {
    const query = runtime_query.init(room);
    const origin_position = current_session.heroWorldPosition();
    const origin = query.evaluateHeroMoveTarget(origin_position);
    if (!origin.isAllowed()) {
        if (try tryApplyRawInvalidZoneRecoveryStep(query, current_session, direction, origin_position)) |status| {
            return status;
        }
        return .{
            .last_move_rejected = .{
                .direction = direction,
                .rejection_stage = .origin_invalid,
                .reason = origin.status,
                .current_cell = origin.raw_cell.cell,
                .target_cell = origin.raw_cell.cell,
                .target_occupied_coverage = null,
                .move_options = null,
                .local_topology = null,
                .hero_position = origin_position,
                .zone_membership = .{},
            },
        };
    }
    const origin_cell = origin.raw_cell.cell orelse return error.LocomotionStatusMissingCell;

    const target_position = steppedWorldPoint(origin_position, direction);
    const target = query.evaluateHeroMoveTarget(target_position);
    if (!target.isAllowed()) {
        return .{
            .last_move_rejected = .{
                .direction = direction,
                .rejection_stage = .target_rejected,
                .reason = target.status,
                .current_cell = origin.raw_cell.cell,
                .target_cell = target.raw_cell.cell,
                .target_occupied_coverage = target.occupied_coverage,
                .move_options = try buildMoveOptions(query, origin_position),
                .local_topology = try buildLocalTopology(query, origin_cell),
                .hero_position = origin_position,
                .zone_membership = try query.containingZonesAtWorldPoint(origin_position),
            },
        };
    }

    current_session.setHeroWorldPosition(target_position);
    const updated_position = current_session.heroWorldPosition();
    const move_options = try buildMoveOptions(query, updated_position);
    return .{
        .last_move_accepted = .{
            .direction = direction,
            .origin_cell = origin_cell,
            .cell = move_options.current_cell,
            .move_options = move_options,
            .local_topology = try buildLocalTopology(query, move_options.current_cell),
            .hero_position = updated_position,
            .zone_membership = try query.containingZonesAtWorldPoint(updated_position),
        },
    };
}

pub const applyDiagnosticStep = applyStep;

pub fn applyPendingHeroIntent(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !LocomotionStatus {
    const intent = current_session.consumeHeroIntent() orelse return error.MissingPendingHeroIntent;
    return switch (intent) {
        .move_cardinal => |direction| applyDiagnosticStep(room, current_session, direction),
        .move_forward_held_ms => |frame_delta_ms| applyHeldForwardMovement(room, current_session, frame_delta_ms),
        .turn_facing,
        => error.UnsupportedHeroIntentForLocomotion,
        .select_behavior_mode,
        .select_magic_ball,
        .cast_lightning,
        .default_action,
        .advance_story,
        .throw_magic_ball,
        => error.UnsupportedHeroIntentForLocomotion,
    };
}

pub const applyPendingDiagnosticHeroIntent = applyPendingHeroIntent;

fn seededValidStatus(
    query: runtime_query.WorldQuery,
    hero_position: WorldPointSnapshot,
) !LocomotionStatus {
    const evaluation = query.evaluateHeroMoveTarget(hero_position);
    if (!evaluation.isAllowed()) return error.LocomotionStatusInvalidPosition;

    return seededValidStatusFromEvaluation(query, hero_position, evaluation);
}

fn seededValidStatusFromEvaluation(
    query: runtime_query.WorldQuery,
    hero_position: WorldPointSnapshot,
    evaluation: runtime_query.MoveTargetEvaluation,
) !LocomotionStatus {
    if (!evaluation.isAllowed()) return error.LocomotionStatusInvalidPosition;

    const move_options = try buildMoveOptions(query, hero_position);
    return .{
        .seeded_valid = .{
            .cell = move_options.current_cell,
            .move_options = move_options,
            .local_topology = try buildLocalTopology(query, move_options.current_cell),
            .hero_position = hero_position,
            .zone_membership = try query.containingZonesAtWorldPoint(hero_position),
        },
    };
}

fn buildMoveOptions(
    query: runtime_query.WorldQuery,
    hero_position: WorldPointSnapshot,
) !MoveOptions {
    const option_set = try query.evaluateCardinalMoveOptions(hero_position);

    var options: [option_set.options.len]CardinalMoveOption = undefined;
    for (option_set.options, 0..) |option, index| {
        options[index] = .{
            .direction = option.direction,
            .target_cell = option.evaluation.raw_cell.cell,
            .status = option.evaluation.status,
            .occupied_coverage = option.evaluation.occupied_coverage,
        };
    }

    return .{
        .current_cell = option_set.origin.raw_cell.cell orelse return error.LocomotionStatusMissingCell,
        .options = options,
    };
}

fn buildRawInvalidStartCandidate(
    candidate: ?runtime_query.DiagnosticCandidate,
) ?RawInvalidStartCandidate {
    const resolved = candidate orelse return null;
    return .{
        .kind = resolved.kind,
        .cell = resolved.cell,
        .x_distance = resolved.x_distance,
        .z_distance = resolved.z_distance,
        .distance_sq = resolved.distance_sq,
    };
}

fn worldPointAdvancedInDirection(
    origin_world_position: WorldPointSnapshot,
    forward_delta_z: i32,
    direction: CardinalDirection,
) WorldPointSnapshot {
    return switch (direction) {
        .north => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z - forward_delta_z,
        },
        .east => .{
            .x = origin_world_position.x + forward_delta_z,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
        .south => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z + forward_delta_z,
        },
        .west => .{
            .x = origin_world_position.x - forward_delta_z,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
    };
}

fn cardinalDirectionForHeroBeta(beta: u16) CardinalDirection {
    return switch (@divFloor(beta % runtime_session.hero_beta_full_turn, runtime_session.hero_beta_quarter_turn)) {
        0 => .north,
        1 => .east,
        2 => .south,
        3 => .west,
        else => unreachable,
    };
}

fn buildRawInvalidStartMappingHint(
    report: runtime_query.HeroStartMappingEvaluationReport,
) ?RawInvalidStartMappingHint {
    var best_index: ?usize = null;

    for (report.evaluations[1..], 1..) |evaluation, index| {
        if (mappingHintDispositionRank(evaluation.comparison_to_canonical.disposition) == 0) continue;
        if (best_index) |resolved_best_index| {
            const best_evaluation = report.evaluations[resolved_best_index];
            if (!mappingHintOutranks(evaluation, best_evaluation)) continue;
        }
        best_index = index;
    }

    const resolved_index = best_index orelse return null;
    const evaluation = report.evaluations[resolved_index];
    return .{
        .hypothesis = evaluation.hypothesis,
        .cell_span_xz = evaluation.cell_span_xz,
        .raw_cell = evaluation.raw_cell.cell,
        .exact_status = evaluation.exact_status,
        .diagnostic_status = evaluation.diagnostic_status,
        .occupied_coverage = evaluation.occupied_coverage,
        .disposition = evaluation.comparison_to_canonical.disposition,
        .better_metric_count = evaluation.comparison_to_canonical.better_metric_count,
        .worse_metric_count = evaluation.comparison_to_canonical.worse_metric_count,
    };
}

fn mappingHintOutranks(
    candidate: runtime_query.HeroStartMappingEvaluation,
    baseline: runtime_query.HeroStartMappingEvaluation,
) bool {
    const candidate_rank = mappingHintDispositionRank(candidate.comparison_to_canonical.disposition);
    const baseline_rank = mappingHintDispositionRank(baseline.comparison_to_canonical.disposition);
    if (candidate_rank != baseline_rank) return candidate_rank > baseline_rank;

    if (candidate.comparison_to_canonical.better_metric_count != baseline.comparison_to_canonical.better_metric_count) {
        return candidate.comparison_to_canonical.better_metric_count > baseline.comparison_to_canonical.better_metric_count;
    }

    if (candidate.comparison_to_canonical.worse_metric_count != baseline.comparison_to_canonical.worse_metric_count) {
        return candidate.comparison_to_canonical.worse_metric_count < baseline.comparison_to_canonical.worse_metric_count;
    }

    if (candidate.cell_span_xz != baseline.cell_span_xz) return candidate.cell_span_xz < baseline.cell_span_xz;

    return @intFromEnum(candidate.hypothesis) < @intFromEnum(baseline.hypothesis);
}

fn mappingHintDispositionRank(disposition: runtime_query.MappingEvidenceDisposition) u8 {
    return switch (disposition) {
        .diagnostic_candidate_only_materially_better => 2,
        .diagnostic_candidate_only_partial_signal => 1,
        .canonical_mapping_poor_on_current_evidence,
        .diagnostic_candidate_only_not_better,
        => 0,
    };
}

fn buildLocalTopology(
    query: runtime_query.WorldQuery,
    current_cell: GridCell,
) !LocalNeighborTopology {
    return query.probeLocalNeighborTopology(current_cell.x, current_cell.z);
}

// Some guarded rooms still start a few world units away from a valid trigger even
// though we do not yet have admitted floor mapping there. Allow one bounded
// recovery nudge only when that nudge enters a previously absent zone.
fn tryApplyRawInvalidZoneRecoveryStep(
    query: runtime_query.WorldQuery,
    current_session: *runtime_session.Session,
    direction: CardinalDirection,
    origin_world_position: WorldPointSnapshot,
) !?LocomotionStatus {
    const target_world_position = steppedWorldPointByDistance(
        origin_world_position,
        direction,
        raw_invalid_zone_entry_step_xz,
    );
    if (!worldPointWithinBounds(query.roomWorldBounds(), target_world_position)) return null;

    const origin_zones = try query.containingZonesAtWorldPoint(origin_world_position);
    const target_zones = try query.containingZonesAtWorldPoint(target_world_position);
    if (!containsNewZone(origin_zones, target_zones)) return null;

    current_session.setHeroWorldPosition(target_world_position);
    return .{
        .last_zone_recovery_accepted = .{
            .direction = direction,
            .hero_position = current_session.heroWorldPosition(),
            .zone_membership = target_zones,
        },
    };
}

fn containsNewZone(
    origin_zones: ZoneMembership,
    target_zones: ZoneMembership,
) bool {
    for (target_zones.slice()) |target_zone| {
        if (!zoneSetContainsIndex(origin_zones, target_zone.index)) return true;
    }
    return false;
}

fn zoneSetContainsIndex(
    membership: ZoneMembership,
    zone_index: usize,
) bool {
    for (membership.slice()) |zone| {
        if (zone.index == zone_index) return true;
    }
    return false;
}

fn worldPointWithinBounds(
    bounds: world_geometry.WorldBounds,
    world_position: WorldPointSnapshot,
) bool {
    return world_position.x >= bounds.min_x and
        world_position.x <= bounds.max_x and
        world_position.z >= bounds.min_z and
        world_position.z <= bounds.max_z;
}

fn steppedWorldPoint(
    origin_world_position: WorldPointSnapshot,
    direction: CardinalDirection,
) WorldPointSnapshot {
    return steppedWorldPointByDistance(
        origin_world_position,
        direction,
        runtime_query.world_grid_span_xz,
    );
}

fn steppedWorldPointByDistance(
    origin_world_position: WorldPointSnapshot,
    direction: CardinalDirection,
    distance_xz: i32,
) WorldPointSnapshot {
    return switch (direction) {
        .north => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z - distance_xz,
        },
        .east => .{
            .x = origin_world_position.x + distance_xz,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
        .south => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z + distance_xz,
        },
        .west => .{
            .x = origin_world_position.x - distance_xz,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
    };
}
