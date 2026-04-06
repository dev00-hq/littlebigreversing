const std = @import("std");
const room_state = @import("room_state.zig");
const runtime_query = @import("world_query.zig");
const runtime_session = @import("session.zig");
const world_geometry = @import("world_geometry.zig");

pub const CardinalDirection = world_geometry.CardinalDirection;
pub const GridCell = world_geometry.GridCell;
pub const WorldPointSnapshot = world_geometry.WorldPointSnapshot;
pub const ZoneMembership = runtime_query.ContainingZoneSet;

pub const LocomotionRejectedStage = enum {
    origin_invalid,
    target_rejected,
};

pub const CardinalMoveOption = struct {
    direction: CardinalDirection,
    target_cell: ?GridCell,
    status: runtime_query.MoveTargetStatus,
};

pub const MoveOptions = struct {
    current_cell: GridCell,
    options: [4]CardinalMoveOption,
};

pub const RawInvalidStartStatus = struct {
    exact_status: runtime_query.HeroStartExactStatus,
    raw_cell: ?GridCell,
    occupied_coverage: runtime_query.OccupiedCoverageRelation,
    hero_position: WorldPointSnapshot,
};

pub const SeededValidStatus = struct {
    cell: GridCell,
    move_options: MoveOptions,
    hero_position: WorldPointSnapshot,
    zone_membership: ZoneMembership,
};

pub const MoveAcceptedStatus = struct {
    direction: CardinalDirection,
    cell: GridCell,
    move_options: MoveOptions,
    hero_position: WorldPointSnapshot,
    zone_membership: ZoneMembership,
};

pub const MoveRejectedStatus = struct {
    direction: CardinalDirection,
    rejection_stage: LocomotionRejectedStage,
    reason: runtime_query.MoveTargetStatus,
    current_cell: ?GridCell,
    target_cell: ?GridCell,
    move_options: ?MoveOptions,
    hero_position: WorldPointSnapshot,
    zone_membership: ZoneMembership,
};

pub const LocomotionStatus = union(enum) {
    raw_invalid_start: RawInvalidStartStatus,
    seeded_valid: SeededValidStatus,
    last_move_accepted: MoveAcceptedStatus,
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
            return .{
                .raw_invalid_start = .{
                    .exact_status = probe.exact_status,
                    .raw_cell = probe.raw_cell.cell,
                    .occupied_coverage = probe.occupied_coverage.relation,
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
        return .{
            .last_move_rejected = .{
                .direction = direction,
                .rejection_stage = .origin_invalid,
                .reason = origin.status,
                .current_cell = origin.raw_cell.cell,
                .target_cell = origin.raw_cell.cell,
                .move_options = null,
                .hero_position = origin_position,
                .zone_membership = .{},
            },
        };
    }

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
                .move_options = try buildMoveOptions(query, origin_position),
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
            .cell = move_options.current_cell,
            .move_options = move_options,
            .hero_position = updated_position,
            .zone_membership = try query.containingZonesAtWorldPoint(updated_position),
        },
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
        };
    }

    return .{
        .current_cell = option_set.origin.raw_cell.cell orelse return error.LocomotionStatusMissingCell,
        .options = options,
    };
}

fn steppedWorldPoint(
    origin_world_position: WorldPointSnapshot,
    direction: CardinalDirection,
) WorldPointSnapshot {
    return switch (direction) {
        .north => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z - runtime_query.world_grid_span_xz,
        },
        .east => .{
            .x = origin_world_position.x + runtime_query.world_grid_span_xz,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
        .south => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z + runtime_query.world_grid_span_xz,
        },
        .west => .{
            .x = origin_world_position.x - runtime_query.world_grid_span_xz,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
    };
}
