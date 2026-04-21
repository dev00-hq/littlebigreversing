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
    seeded_valid: SeededValidStatus,
    last_move_accepted: MoveAcceptedStatus,
    last_zone_recovery_accepted: RawZoneRecoveryAcceptedStatus,
    last_move_rejected: MoveRejectedStatus,
};

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

    return seededValidStatus(query, hero_position);
}

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

pub fn applyPendingHeroIntent(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !LocomotionStatus {
    const intent = current_session.consumeHeroIntent() orelse return error.MissingPendingHeroIntent;
    return switch (intent) {
        .move_cardinal => |direction| applyStep(room, current_session, direction),
        .cast_lightning,
        .default_action,
        .advance_story,
        => error.UnsupportedHeroIntentForLocomotion,
    };
}

fn seededValidStatus(
    query: runtime_query.WorldQuery,
    hero_position: WorldPointSnapshot,
) !LocomotionStatus {
    const evaluation = query.evaluateHeroMoveTarget(hero_position);
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
