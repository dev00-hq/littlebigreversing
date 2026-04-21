const std = @import("std");
const builtin = @import("builtin");
const paths_mod = @import("../foundation/paths.zig");
const room_fixtures = if (builtin.is_test) @import("../testing/room_fixtures.zig") else struct {};
const world_geometry = @import("world_geometry.zig");
const room_state = @import("room_state.zig");
const session = @import("session.zig");

const WorldPointSnapshot = world_geometry.WorldPointSnapshot;
const WorldBounds = world_geometry.WorldBounds;
const GridCell = world_geometry.GridCell;
const CardinalDirection = world_geometry.CardinalDirection;

pub const world_grid_span_xz: i32 = 512;
pub const world_grid_span_y: i32 = 256;
const world_grid_span_xz_usize: usize = 512;

pub const GridBounds = struct {
    width: usize,
    depth: usize,
    occupied_bounds: ?room_state.CompositionBoundsSnapshot,
};

pub const CellTopSurface = struct {
    cell: GridCell,
    total_height: u8,
    top_y: i32,
    stack_depth: u8,
    top_floor_type: u8,
    top_shape: u8,
    top_shape_class: room_state.SurfaceShapeClass,
    top_brick_index: u16,
};

pub const Standability = enum {
    standable,
    blocked,
};

pub const CellProbeStatus = enum {
    occupied_surface,
    empty,
    out_of_bounds,
    missing_top_surface,
};

pub const WorldPointCellProbe = struct {
    world_x: i32,
    world_z: i32,
    cell: ?GridCell,
    status: CellProbeStatus,
    occupied: bool,
    surface: ?CellTopSurface,
    standability: ?Standability,
};

pub const MoveTargetStatus = enum {
    allowed,
    target_out_of_bounds,
    target_empty,
    target_missing_top_surface,
    target_blocked,
    target_height_mismatch,
};

pub const MoveTargetEvaluation = struct {
    target_world_position: WorldPointSnapshot,
    raw_cell: WorldPointCellProbe,
    occupied_coverage: OccupiedCoverageProbe,
    status: MoveTargetStatus,

    pub fn isAllowed(self: MoveTargetEvaluation) bool {
        return self.status == .allowed;
    }
};

pub const CardinalMoveOptionEvaluation = struct {
    direction: CardinalDirection,
    evaluation: MoveTargetEvaluation,
};

pub const CardinalMoveOptionSet = struct {
    origin: MoveTargetEvaluation,
    options: [cardinal_directions.len]CardinalMoveOptionEvaluation,
};

pub const max_containing_zones = 16;

pub const ContainingZoneSet = struct {
    count: usize = 0,
    zones: [max_containing_zones]room_state.ZoneBoundsSnapshot = undefined,

    pub fn append(self: *ContainingZoneSet, zone: room_state.ZoneBoundsSnapshot) !void {
        if (self.count >= self.zones.len) return error.TooManyContainingZones;
        self.zones[self.count] = zone;
        self.count += 1;
    }

    pub fn slice(self: *const ContainingZoneSet) []const room_state.ZoneBoundsSnapshot {
        return self.zones[0..self.count];
    }
};

pub const CellNeighborProbe = struct {
    direction: CardinalDirection,
    cell: ?GridCell,
    world_bounds: ?WorldBounds,
    status: CellProbeStatus,
    occupied: bool,
    surface: ?CellTopSurface,
    standability: ?Standability,
    top_y_delta: ?i32,
};

pub const LocalNeighborTopologyProbe = struct {
    origin_surface: CellTopSurface,
    origin_standability: Standability,
    neighbors: [4]CellNeighborProbe,

    pub fn standableNeighborCount(self: LocalNeighborTopologyProbe) usize {
        var count: usize = 0;
        for (self.neighbors) |neighbor| {
            if (neighbor.standability == .standable) count += 1;
        }
        return count;
    }
};

pub const AdmittedStandableFooting = struct {
    cell: GridCell,
    surface: CellTopSurface,
    world_bounds: WorldBounds,
};

pub const ObservedTopYDeltaBucket = struct {
    delta: i32,
    count: usize,
};

pub const ObservedNeighborPatternSummary = struct {
    origin_cell_count: usize,
    total_neighbor_count: usize,
    occupied_surface_count: usize,
    empty_count: usize,
    out_of_bounds_count: usize,
    missing_top_surface_count: usize,
    standable_neighbor_count: usize,
    blocked_neighbor_count: usize,
    top_y_delta_buckets: []ObservedTopYDeltaBucket,

    pub fn deinit(self: ObservedNeighborPatternSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.top_y_delta_buckets);
    }
};

pub const TopologyRelationEvidenceBasis = enum {
    guarded_runtime_room_snapshot,
    unchecked_evidence_room_snapshot,
};

pub const TopologyRelationEvidenceAdmission = enum {
    admitted_supported_runtime,
    admitted_discovery_only,
    rejected,
};

pub const TopologyRelationEvidencePolicy = struct {
    basis: TopologyRelationEvidenceBasis,
    admission: TopologyRelationEvidenceAdmission,
    rationale: []const u8,

    pub fn allowsDiscovery(self: TopologyRelationEvidencePolicy) bool {
        return switch (self.admission) {
            .admitted_supported_runtime,
            .admitted_discovery_only,
            => true,
            .rejected => false,
        };
    }

    pub fn allowsRuntimeSemantics(self: TopologyRelationEvidencePolicy) bool {
        return self.admission == .admitted_supported_runtime;
    }
};

pub const OccupiedCoverageRelation = enum {
    unmapped_world_point,
    no_occupied_bounds,
    within_occupied_bounds,
    outside_occupied_bounds,
};

pub const OccupiedCoverageProbe = struct {
    relation: OccupiedCoverageRelation,
    occupied_bounds: ?room_state.CompositionBoundsSnapshot,
    x_cells_from_bounds: usize,
    z_cells_from_bounds: usize,
};

pub const HeroStartExactStatus = enum {
    valid,
    mapped_cell_out_of_bounds,
    mapped_cell_empty,
    mapped_cell_missing_top_surface,
    mapped_cell_blocked,
    surface_height_mismatch,
};

pub const HeroStartDiagnosticStatus = enum {
    exact_valid,
    exact_invalid_candidate_only,
    exact_invalid_mapping_mismatch,
    exact_invalid_no_candidate,
};

pub const DiagnosticCandidateKind = enum {
    occupied,
    standable,
};

pub const DiagnosticCandidate = struct {
    kind: DiagnosticCandidateKind,
    cell: GridCell,
    world_bounds: WorldBounds,
    surface: CellTopSurface,
    standability: Standability,
    x_distance: i32,
    z_distance: i32,
    distance_sq: i64,
};

pub const HeroStartProbe = struct {
    raw_world_position: WorldPointSnapshot,
    raw_cell: WorldPointCellProbe,
    occupied_coverage: OccupiedCoverageProbe,
    exact_status: HeroStartExactStatus,
    diagnostic_status: HeroStartDiagnosticStatus,
    nearest_occupied: ?DiagnosticCandidate,
    nearest_standable: ?DiagnosticCandidate,
};

pub const EvidenceAnchorKind = enum {
    hero_start_world_point,
    scene_object_world_point,
    zone_world_point,
    fragment_world_point,
};

pub const EvidenceMetricKind = enum {
    exact_status,
    occupied_coverage,
    nearest_occupied,
    nearest_standable,
};

pub const EvidenceAdmission = enum {
    admitted,
    rejected_no_floor_truth,
    rejected_out_of_scope_basis,
};

pub const MappingEvidenceCase = struct {
    anchor_kind: EvidenceAnchorKind,
    admission: EvidenceAdmission,
    allowed_metrics: []const EvidenceMetricKind,

    pub fn admitsMetric(self: MappingEvidenceCase, metric: EvidenceMetricKind) bool {
        for (self.allowed_metrics) |allowed| {
            if (allowed == metric) return true;
        }
        return false;
    }
};

pub const MappingHypothesisRole = enum {
    canonical_runtime_mapping,
    diagnostic_candidate_only,
};

pub const MappingHypothesisFamily = enum {
    canonical,
    axis_swap_control,
    dense_grid_candidate,
};

pub const MappingHypothesisDefinition = struct {
    hypothesis: MappingHypothesis,
    family: MappingHypothesisFamily,
    rationale: []const u8,
};

pub const MappingAxisInterpretation = enum {
    aligned,
    swapped,
};

pub const MappingHypothesis = enum {
    canonical_axis_aligned_512,
    swapped_axes_512_control,
    dense_swapped_axes_64,

    pub fn role(self: MappingHypothesis) MappingHypothesisRole {
        return switch (self) {
            .canonical_axis_aligned_512 => .canonical_runtime_mapping,
            .swapped_axes_512_control,
            .dense_swapped_axes_64,
            => .diagnostic_candidate_only,
        };
    }

    pub fn axisInterpretation(self: MappingHypothesis) MappingAxisInterpretation {
        return switch (self) {
            .canonical_axis_aligned_512 => .aligned,
            .swapped_axes_512_control,
            .dense_swapped_axes_64,
            => .swapped,
        };
    }

    pub fn cellSpan(self: MappingHypothesis) i32 {
        return switch (self) {
            .canonical_axis_aligned_512,
            .swapped_axes_512_control,
            => 512,
            .dense_swapped_axes_64,
            => 64,
        };
    }

    pub fn definition(self: MappingHypothesis) MappingHypothesisDefinition {
        inline for (mapping_hypothesis_definitions) |hypothesis_definition| {
            if (hypothesis_definition.hypothesis == self) return hypothesis_definition;
        }
        unreachable;
    }
};

const mapping_hypotheses = [_]MappingHypothesis{
    .canonical_axis_aligned_512,
    .swapped_axes_512_control,
    .dense_swapped_axes_64,
};

const cardinal_directions = [_]CardinalDirection{
    .north,
    .east,
    .south,
    .west,
};

const all_evidence_metrics = [_]EvidenceMetricKind{
    .exact_status,
    .occupied_coverage,
    .nearest_occupied,
    .nearest_standable,
};

const no_evidence_metrics = [_]EvidenceMetricKind{};

const mapping_hypothesis_definitions = [_]MappingHypothesisDefinition{
    .{
        .hypothesis = .canonical_axis_aligned_512,
        .family = .canonical,
        .rationale = "Current runtime mapping under the guarded 19/19 baseline.",
    },
    .{
        .hypothesis = .swapped_axes_512_control,
        .family = .axis_swap_control,
        .rationale = "Axis-swap control at the canonical span; tests whether orientation alone explains the mismatch.",
    },
    .{
        .hypothesis = .dense_swapped_axes_64,
        .family = .dense_grid_candidate,
        .rationale = "Retained dense-grid candidate only because it currently improves all admitted hero-start metrics under fixed scoring.",
    },
};

pub const EvidenceMetricComparison = enum {
    better,
    equal,
    worse,
};

pub const MappingEvidenceDisposition = enum {
    canonical_mapping_poor_on_current_evidence,
    diagnostic_candidate_only_not_better,
    diagnostic_candidate_only_partial_signal,
    diagnostic_candidate_only_materially_better,
};

pub const MappingEvidenceComparison = struct {
    exact_status: EvidenceMetricComparison,
    occupied_coverage: EvidenceMetricComparison,
    nearest_occupied: EvidenceMetricComparison,
    nearest_standable: EvidenceMetricComparison,
    better_metric_count: u8,
    worse_metric_count: u8,
    primary_metric_better_count: u8,
    supporting_metric_better_count: u8,
    stronger_evidence_bar_passed: bool,
    disposition: MappingEvidenceDisposition,
};

pub const MappingEvidenceCaseComparison = struct {
    evidence_case: MappingEvidenceCase,
    comparison: MappingEvidenceComparison,
};

pub const AdditionalAnchorInvestigationPriority = enum {
    primary,
    secondary,
};

pub const AdditionalAnchorCandidateRanking = struct {
    anchor_kind: EvidenceAnchorKind,
    priority: AdditionalAnchorInvestigationPriority,
    sample_count: usize,
    floor_aligned_sample_count: usize,
    rationale: []const u8,
};

pub const AdditionalAnchorInvestigation = struct {
    ranked_candidates: [2]AdditionalAnchorCandidateRanking,
    chosen_anchor_kind: EvidenceAnchorKind,
    chosen_evidence_case: MappingEvidenceCase,
    decision_rationale: []const u8,
};

pub const HeroStartMappingEvaluation = struct {
    hypothesis: MappingHypothesis,
    family: MappingHypothesisFamily,
    role: MappingHypothesisRole,
    rationale: []const u8,
    evidence_case: MappingEvidenceCase,
    axis_interpretation: MappingAxisInterpretation,
    cell_span_xz: i32,
    raw_world_position: WorldPointSnapshot,
    raw_cell: WorldPointCellProbe,
    occupied_coverage: OccupiedCoverageProbe,
    exact_status: HeroStartExactStatus,
    diagnostic_status: HeroStartDiagnosticStatus,
    nearest_occupied: ?DiagnosticCandidate,
    nearest_standable: ?DiagnosticCandidate,
    comparison_to_canonical: MappingEvidenceComparison,
};

pub const HeroStartMappingEvaluationReport = struct {
    raw_world_position: WorldPointSnapshot,
    evaluations: [mapping_hypothesis_definitions.len]HeroStartMappingEvaluation,

    pub fn evaluation(
        self: *const HeroStartMappingEvaluationReport,
        hypothesis: MappingHypothesis,
    ) *const HeroStartMappingEvaluation {
        for (&self.evaluations) |*item| {
            if (item.hypothesis == hypothesis) return item;
        }
        unreachable;
    }
};

const HeroStartEvaluationCore = struct {
    raw_cell: WorldPointCellProbe,
    occupied_coverage: OccupiedCoverageProbe,
    exact_status: HeroStartExactStatus,
    diagnostic_status: HeroStartDiagnosticStatus,
    nearest_occupied: ?DiagnosticCandidate,
    nearest_standable: ?DiagnosticCandidate,
};

const AnchorCandidateAssessment = struct {
    anchor_kind: EvidenceAnchorKind,
    sample_count: usize,
    floor_aligned_sample_count: usize,
    priority_score: u8,
    rationale: []const u8,
};

pub const WorldQuery = struct {
    room: *const room_state.RoomSnapshot,

    pub fn init(room: *const room_state.RoomSnapshot) WorldQuery {
        return .{ .room = room };
    }

    pub fn gridBounds(self: WorldQuery) GridBounds {
        return .{
            .width = self.room.background.column_table.width,
            .depth = self.room.background.column_table.depth,
            .occupied_bounds = self.room.background.composition.occupied_bounds,
        };
    }

    pub fn roomWorldBounds(self: WorldQuery) WorldBounds {
        const bounds = self.gridBounds();
        return .{
            .min_x = 0,
            .max_x = worldAxisMax(bounds.width),
            .min_z = 0,
            .max_z = worldAxisMax(bounds.depth),
        };
    }

    pub fn containsCell(self: WorldQuery, x: usize, z: usize) bool {
        const bounds = self.gridBounds();
        return x < bounds.width and z < bounds.depth;
    }

    pub fn isOccupiedCell(self: WorldQuery, x: usize, z: usize) !bool {
        const cell_index = try self.cellIndex(x, z);
        return self.room.background.composition.height_grid[cell_index] > 0;
    }

    pub fn cellWorldBounds(self: WorldQuery, x: usize, z: usize) !WorldBounds {
        _ = try self.cellIndex(x, z);
        return gridCellWorldBounds(x, z);
    }

    pub fn gridCellAtWorldPoint(self: WorldQuery, world_x: i32, world_z: i32) !GridCell {
        if (world_x < 0 or world_z < 0) return error.WorldPointOutOfBounds;

        const cell_x: usize = @intCast(@divFloor(world_x, world_grid_span_xz));
        const cell_z: usize = @intCast(@divFloor(world_z, world_grid_span_xz));
        _ = try self.cellIndex(cell_x, cell_z);

        return .{
            .x = cell_x,
            .z = cell_z,
        };
    }

    pub fn cellTopSurface(self: WorldQuery, x: usize, z: usize) !CellTopSurface {
        const cell_index = try self.cellIndex(x, z);
        const total_height = self.room.background.composition.height_grid[cell_index];
        if (total_height == 0) return error.WorldCellEmpty;

        const tile = self.findCompositionTile(x, z) orelse return error.WorldCellMissingTopSurface;
        return .{
            .cell = .{ .x = x, .z = z },
            .total_height = total_height,
            .top_y = topSurfaceY(total_height),
            .stack_depth = tile.stack_depth,
            .top_floor_type = tile.top_floor_type,
            .top_shape = tile.top_shape,
            .top_shape_class = tile.top_shape_class,
            .top_brick_index = tile.top_brick_index,
        };
    }

    pub fn standabilityAtCell(self: WorldQuery, x: usize, z: usize) !Standability {
        return standabilityForSurface(try self.cellTopSurface(x, z));
    }

    pub fn probeCellAtWorldPoint(self: WorldQuery, world_x: i32, world_z: i32) WorldPointCellProbe {
        return self.probeCellAtWorldPointWithHypothesis(world_x, world_z, .canonical_axis_aligned_512);
    }

    pub fn probeCellAtWorldPointForWorldY(self: WorldQuery, world_x: i32, world_z: i32, world_y: i32) WorldPointCellProbe {
        return self.probeCellAtWorldPointWithHypothesisForWorldY(world_x, world_z, world_y, .canonical_axis_aligned_512);
    }

    pub fn evaluateHeroMoveTarget(
        self: WorldQuery,
        target_world_position: WorldPointSnapshot,
    ) MoveTargetEvaluation {
        const raw_cell = self.probeCellAtWorldPointForWorldY(
            target_world_position.x,
            target_world_position.z,
            target_world_position.y,
        );
        return .{
            .target_world_position = target_world_position,
            .raw_cell = raw_cell,
            .occupied_coverage = self.occupiedCoverageForCell(raw_cell.cell),
            .status = moveTargetStatusForProbe(raw_cell, target_world_position.y),
        };
    }

    pub fn evaluateCardinalMoveOptions(
        self: WorldQuery,
        origin_world_position: WorldPointSnapshot,
    ) !CardinalMoveOptionSet {
        const origin = self.evaluateHeroMoveTarget(origin_world_position);
        if (!origin.isAllowed()) return error.MoveTargetOriginInvalid;

        var options: [cardinal_directions.len]CardinalMoveOptionEvaluation = undefined;
        inline for (cardinal_directions, 0..) |direction, index| {
            options[index] = .{
                .direction = direction,
                .evaluation = self.evaluateHeroMoveTarget(
                    worldPointSteppedInDirection(origin_world_position, direction),
                ),
            };
        }

        return .{
            .origin = origin,
            .options = options,
        };
    }

    pub fn containingZonesAtWorldPoint(
        self: WorldQuery,
        world_position: WorldPointSnapshot,
    ) !ContainingZoneSet {
        var containing: ContainingZoneSet = .{};
        for (self.room.scene.zones) |zone| {
            if (!zoneContainsWorldPoint(zone, world_position)) continue;
            try containing.append(zone);
        }
        return containing;
    }

    pub fn probeLocalNeighborTopology(self: WorldQuery, x: usize, z: usize) !LocalNeighborTopologyProbe {
        const origin_surface = try self.cellTopSurface(x, z);
        var neighbors: [cardinal_directions.len]CellNeighborProbe = undefined;
        inline for (cardinal_directions, 0..) |direction, index| {
            neighbors[index] = self.probeNeighborAtCell(origin_surface, direction);
        }

        return .{
            .origin_surface = origin_surface,
            .origin_standability = standabilityForSurface(origin_surface),
            .neighbors = neighbors,
        };
    }

    pub fn admittedStandableFootingAtWorldPoint(
        self: WorldQuery,
        world_position: WorldPointSnapshot,
    ) !AdmittedStandableFooting {
        const probe = self.probeCellAtWorldPointForWorldY(world_position.x, world_position.z, world_position.y);
        return switch (exactStatusForProbe(probe, world_position.y)) {
            .valid => .{
                .cell = probe.cell.?,
                .surface = probe.surface.?,
                .world_bounds = gridCellWorldBounds(probe.cell.?.x, probe.cell.?.z),
            },
            .mapped_cell_out_of_bounds => error.WorldPointOutOfBounds,
            .mapped_cell_empty => error.WorldCellEmpty,
            .mapped_cell_missing_top_surface => error.WorldCellMissingTopSurface,
            .mapped_cell_blocked => error.WorldCellNotStandable,
            .surface_height_mismatch => error.WorldPointSurfaceHeightMismatch,
        };
    }

    pub fn classicShadowAdjustedLanding(
        self: WorldQuery,
        provisional_world_position: WorldPointSnapshot,
    ) !WorldPointSnapshot {
        const cell = try self.gridCellAtWorldPoint(
            provisional_world_position.x,
            provisional_world_position.z,
        );
        const surface = try self.cellSurfaceAtOrBelowWorldY(cell, provisional_world_position.y);
        if (standabilityForSurface(surface) != .standable) return error.WorldCellNotStandable;
        return .{
            .x = provisional_world_position.x,
            .y = surface.top_y,
            .z = provisional_world_position.z,
        };
    }

    pub fn summarizeObservedNeighborPatterns(
        self: WorldQuery,
        allocator: std.mem.Allocator,
    ) !ObservedNeighborPatternSummary {
        var delta_buckets = try std.ArrayList(ObservedTopYDeltaBucket).initCapacity(allocator, 0);
        defer delta_buckets.deinit(allocator);

        var summary = ObservedNeighborPatternSummary{
            .origin_cell_count = 0,
            .total_neighbor_count = 0,
            .occupied_surface_count = 0,
            .empty_count = 0,
            .out_of_bounds_count = 0,
            .missing_top_surface_count = 0,
            .standable_neighbor_count = 0,
            .blocked_neighbor_count = 0,
            .top_y_delta_buckets = &.{},
        };

        for (self.room.background.composition.tiles) |tile| {
            const topology = try self.probeLocalNeighborTopology(tile.x, tile.z);
            summary.origin_cell_count += 1;
            summary.total_neighbor_count += topology.neighbors.len;

            for (topology.neighbors) |neighbor| {
                switch (neighbor.status) {
                    .occupied_surface => {
                        summary.occupied_surface_count += 1;
                        switch (neighbor.standability.?) {
                            .standable => summary.standable_neighbor_count += 1,
                            .blocked => summary.blocked_neighbor_count += 1,
                        }
                        try incrementTopYDeltaBucket(&delta_buckets, allocator, neighbor.top_y_delta.?);
                    },
                    .empty => summary.empty_count += 1,
                    .out_of_bounds => summary.out_of_bounds_count += 1,
                    .missing_top_surface => summary.missing_top_surface_count += 1,
                }
            }
        }

        std.mem.sort(ObservedTopYDeltaBucket, delta_buckets.items, {}, lessThanTopYDeltaBucket);
        summary.top_y_delta_buckets = try delta_buckets.toOwnedSlice(allocator);
        return summary;
    }

    pub fn occupiedCoverageForCell(self: WorldQuery, cell: ?GridCell) OccupiedCoverageProbe {
        const occupied_bounds = self.room.background.composition.occupied_bounds;
        if (cell == null) {
            return .{
                .relation = .unmapped_world_point,
                .occupied_bounds = occupied_bounds,
                .x_cells_from_bounds = 0,
                .z_cells_from_bounds = 0,
            };
        }
        if (occupied_bounds == null) {
            return .{
                .relation = .no_occupied_bounds,
                .occupied_bounds = null,
                .x_cells_from_bounds = 0,
                .z_cells_from_bounds = 0,
            };
        }

        const bounds = occupied_bounds.?;
        const x_cells_from_bounds = axisDistanceToRange(cell.?.x, bounds.min_x, bounds.max_x);
        const z_cells_from_bounds = axisDistanceToRange(cell.?.z, bounds.min_z, bounds.max_z);
        return .{
            .relation = if (x_cells_from_bounds == 0 and z_cells_from_bounds == 0)
                .within_occupied_bounds
            else
                .outside_occupied_bounds,
            .occupied_bounds = bounds,
            .x_cells_from_bounds = x_cells_from_bounds,
            .z_cells_from_bounds = z_cells_from_bounds,
        };
    }

    pub fn probeHeroStart(self: WorldQuery) !HeroStartProbe {
        const hero_position = heroStartWorldPosition(self.room);
        const evaluation = try self.evaluateHeroStartCore(hero_position, .canonical_axis_aligned_512);
        return .{
            .raw_world_position = hero_position,
            .raw_cell = evaluation.raw_cell,
            .occupied_coverage = evaluation.occupied_coverage,
            .exact_status = evaluation.exact_status,
            .diagnostic_status = evaluation.diagnostic_status,
            .nearest_occupied = evaluation.nearest_occupied,
            .nearest_standable = evaluation.nearest_standable,
        };
    }

    pub fn evaluateHeroStartMappings(self: WorldQuery) !HeroStartMappingEvaluationReport {
        const hero_position = heroStartWorldPosition(self.room);
        const canonical_core = try self.evaluateHeroStartCore(hero_position, .canonical_axis_aligned_512);
        const evidence_case = evidenceCaseForAnchor(.hero_start_world_point);

        var evaluations: [mapping_hypothesis_definitions.len]HeroStartMappingEvaluation = undefined;
        evaluations[0] = buildMappingEvaluation(
            hero_position,
            .canonical_axis_aligned_512,
            evidence_case,
            canonical_core,
            .{
                .exact_status = .equal,
                .occupied_coverage = .equal,
                .nearest_occupied = .equal,
                .nearest_standable = .equal,
                .better_metric_count = 0,
                .worse_metric_count = 0,
                .primary_metric_better_count = 0,
                .supporting_metric_better_count = 0,
                .stronger_evidence_bar_passed = false,
                .disposition = .canonical_mapping_poor_on_current_evidence,
            },
        );

        inline for (mapping_hypotheses[1..], 1..) |hypothesis, index| {
            const core = try self.evaluateHeroStartCore(hero_position, hypothesis);
            evaluations[index] = buildMappingEvaluation(
                hero_position,
                hypothesis,
                evidence_case,
                core,
                compareEvidenceCaseAgainstCanonical(.hero_start_world_point, canonical_core, core).comparison,
            );
        }

        return .{
            .raw_world_position = hero_position,
            .evaluations = evaluations,
        };
    }

    pub fn validateHeroStart(self: WorldQuery) !HeroStartProbe {
        const probe = try self.probeHeroStart();
        switch (probe.exact_status) {
            .valid => return probe,
            .mapped_cell_out_of_bounds => return error.HeroStartOutOfBounds,
            .mapped_cell_empty => return error.HeroStartCellEmpty,
            .mapped_cell_missing_top_surface => return error.HeroStartMissingTopSurface,
            .mapped_cell_blocked => return error.HeroStartNotStandable,
            .surface_height_mismatch => return error.HeroStartSurfaceHeightMismatch,
        }
    }

    pub fn investigateAdditionalEvidenceAnchor(self: WorldQuery) AdditionalAnchorInvestigation {
        const zone_candidate = assessZoneAnchorCandidate(self.room);
        const scene_object_candidate = assessSceneObjectAnchorCandidate(self.room);
        const ranked_candidates = rankAdditionalAnchorCandidates(zone_candidate, scene_object_candidate);
        const chosen_anchor_kind = ranked_candidates[0].anchor_kind;
        return .{
            .ranked_candidates = ranked_candidates,
            .chosen_anchor_kind = chosen_anchor_kind,
            .chosen_evidence_case = evidenceCaseForAnchor(chosen_anchor_kind),
            .decision_rationale = decisionRationaleForAnchor(chosen_anchor_kind),
        };
    }

    fn cellIndex(self: WorldQuery, x: usize, z: usize) !usize {
        const bounds = self.gridBounds();
        if (x >= bounds.width or z >= bounds.depth) return error.WorldCellOutOfBounds;
        return (z * bounds.width) + x;
    }

    fn findCompositionTile(self: WorldQuery, x: usize, z: usize) ?room_state.CompositionTileSnapshot {
        for (self.room.background.composition.tiles) |tile| {
            if (tile.x == x and tile.z == z) return tile;
        }
        return null;
    }

    fn cellSurfaceAtOrBelowWorldY(self: WorldQuery, cell: GridCell, world_y: i32) !CellTopSurface {
        const cell_index = try self.cellIndex(cell.x, cell.z);
        const occupancy = self.room.background.composition.level_occupancy_grid[cell_index];
        if (occupancy == 0) return error.WorldCellEmpty;

        var level: usize = if (world_y <= 0)
            0
        else
            @min(@as(usize, @intCast(@divFloor(world_y - 1, world_grid_span_y))), 24);

        while (true) {
            const level_bit = @as(u32, 1) << @intCast(level);
            if ((occupancy & level_bit) != 0) {
                const level_index = (cell_index * 25) + level;
                const below_mask = if (level == 24)
                    occupancy
                else
                    occupancy & ((@as(u32, 1) << @intCast(level + 1)) - 1);
                return .{
                    .cell = cell,
                    .total_height = @intCast(level + 1),
                    .top_y = @as(i32, @intCast(level + 1)) * world_grid_span_y,
                    .stack_depth = @intCast(@popCount(below_mask)),
                    .top_floor_type = self.room.background.composition.level_floor_type_grid[level_index],
                    .top_shape = self.room.background.composition.level_shape_grid[level_index],
                    .top_shape_class = self.room.background.composition.level_shape_class_grid[level_index],
                    .top_brick_index = self.room.background.composition.level_brick_index_grid[level_index],
                };
            }
            if (level == 0) break;
            level -= 1;
        }
        return error.WorldCellEmpty;
    }

    fn probeNeighborAtCell(
        self: WorldQuery,
        origin_surface: CellTopSurface,
        direction: CardinalDirection,
    ) CellNeighborProbe {
        const neighbor_cell = self.neighborCellInDirection(origin_surface.cell, direction) orelse {
            return .{
                .direction = direction,
                .cell = null,
                .world_bounds = null,
                .status = .out_of_bounds,
                .occupied = false,
                .surface = null,
                .standability = null,
                .top_y_delta = null,
            };
        };
        const world_bounds = gridCellWorldBounds(neighbor_cell.x, neighbor_cell.z);
        const cell_index = self.cellIndex(neighbor_cell.x, neighbor_cell.z) catch unreachable;
        const occupied = self.room.background.composition.height_grid[cell_index] > 0;
        if (!occupied) {
            return .{
                .direction = direction,
                .cell = neighbor_cell,
                .world_bounds = world_bounds,
                .status = .empty,
                .occupied = false,
                .surface = null,
                .standability = null,
                .top_y_delta = null,
            };
        }

        const tile = self.findCompositionTile(neighbor_cell.x, neighbor_cell.z) orelse {
            return .{
                .direction = direction,
                .cell = neighbor_cell,
                .world_bounds = world_bounds,
                .status = .missing_top_surface,
                .occupied = true,
                .surface = null,
                .standability = null,
                .top_y_delta = null,
            };
        };
        const surface = CellTopSurface{
            .cell = neighbor_cell,
            .total_height = self.room.background.composition.height_grid[cell_index],
            .top_y = topSurfaceY(tile.total_height),
            .stack_depth = tile.stack_depth,
            .top_floor_type = tile.top_floor_type,
            .top_shape = tile.top_shape,
            .top_shape_class = tile.top_shape_class,
            .top_brick_index = tile.top_brick_index,
        };
        const standability = standabilityForSurface(surface);
        return .{
            .direction = direction,
            .cell = neighbor_cell,
            .world_bounds = world_bounds,
            .status = .occupied_surface,
            .occupied = true,
            .surface = surface,
            .standability = standability,
            .top_y_delta = surface.top_y - origin_surface.top_y,
        };
    }

    fn neighborCellInDirection(self: WorldQuery, origin: GridCell, direction: CardinalDirection) ?GridCell {
        const bounds = self.gridBounds();
        return switch (direction) {
            .north => if (origin.z == 0) null else .{ .x = origin.x, .z = origin.z - 1 },
            .east => if (origin.x + 1 >= bounds.width) null else .{ .x = origin.x + 1, .z = origin.z },
            .south => if (origin.z + 1 >= bounds.depth) null else .{ .x = origin.x, .z = origin.z + 1 },
            .west => if (origin.x == 0) null else .{ .x = origin.x - 1, .z = origin.z },
        };
    }

    fn evaluateHeroStartCore(
        self: WorldQuery,
        hero_position: WorldPointSnapshot,
        hypothesis: MappingHypothesis,
    ) !HeroStartEvaluationCore {
        const raw_cell = self.probeCellAtWorldPointWithHypothesis(
            hero_position.x,
            hero_position.z,
            hypothesis,
        );
        const exact_status = exactStatusForProbe(raw_cell, hero_position.y);
        const occupied_coverage = self.occupiedCoverageForCell(raw_cell.cell);

        const nearest_occupied = if (exact_status == .valid)
            null
        else
            self.findNearestCandidateForHypothesis(
                hero_position.x,
                hero_position.z,
                hypothesis,
                .occupied,
            ) catch |err| switch (err) {
                error.HeroStartNoOccupiedCell => null,
                else => return err,
            };
        const nearest_standable = if (exact_status == .valid)
            null
        else
            self.findNearestCandidateForHypothesis(
                hero_position.x,
                hero_position.z,
                hypothesis,
                .standable,
            ) catch |err| switch (err) {
                error.HeroStartNoStandableCell => null,
                else => return err,
            };

        return .{
            .raw_cell = raw_cell,
            .occupied_coverage = occupied_coverage,
            .exact_status = exact_status,
            .diagnostic_status = diagnosticStatusForProbe(
                exact_status,
                occupied_coverage,
                nearest_occupied,
                nearest_standable,
            ),
            .nearest_occupied = nearest_occupied,
            .nearest_standable = nearest_standable,
        };
    }

    fn probeCellAtWorldPointWithHypothesis(
        self: WorldQuery,
        world_x: i32,
        world_z: i32,
        hypothesis: MappingHypothesis,
    ) WorldPointCellProbe {
        return self.probeCellAtWorldPointWithHypothesisForWorldY(world_x, world_z, std.math.maxInt(i32), hypothesis);
    }

    fn probeCellAtWorldPointWithHypothesisForWorldY(
        self: WorldQuery,
        world_x: i32,
        world_z: i32,
        world_y: i32,
        hypothesis: MappingHypothesis,
    ) WorldPointCellProbe {
        if (world_x < 0 or world_z < 0) {
            return .{
                .world_x = world_x,
                .world_z = world_z,
                .cell = null,
                .status = .out_of_bounds,
                .occupied = false,
                .surface = null,
                .standability = null,
            };
        }

        const mapped = mapWorldPointToCellIndices(world_x, world_z, hypothesis);
        const cell = GridCell{
            .x = @intCast(mapped.x),
            .z = @intCast(mapped.z),
        };
        if (!self.containsCell(cell.x, cell.z)) {
            return .{
                .world_x = world_x,
                .world_z = world_z,
                .cell = cell,
                .status = .out_of_bounds,
                .occupied = false,
                .surface = null,
                .standability = null,
            };
        }

        const cell_index = self.cellIndex(cell.x, cell.z) catch unreachable;
        const occupied = self.room.background.composition.height_grid[cell_index] > 0;
        if (!occupied) {
            return .{
                .world_x = world_x,
                .world_z = world_z,
                .cell = cell,
                .status = .empty,
                .occupied = false,
                .surface = null,
                .standability = null,
            };
        }

        const tile = self.findCompositionTile(cell.x, cell.z) orelse {
            return .{
                .world_x = world_x,
                .world_z = world_z,
                .cell = cell,
                .status = .missing_top_surface,
                .occupied = true,
                .surface = null,
                .standability = null,
            };
        };
        const top_surface = CellTopSurface{
            .cell = cell,
            .total_height = self.room.background.composition.height_grid[cell_index],
            .top_y = topSurfaceY(tile.total_height),
            .stack_depth = tile.stack_depth,
            .top_floor_type = tile.top_floor_type,
            .top_shape = tile.top_shape,
            .top_shape_class = tile.top_shape_class,
            .top_brick_index = tile.top_brick_index,
        };
        const surface = if (world_y >= top_surface.top_y)
            top_surface
        else
            self.cellSurfaceAtOrBelowWorldY(cell, world_y) catch |err| switch (err) {
                error.WorldCellEmpty => return .{
                    .world_x = world_x,
                    .world_z = world_z,
                    .cell = cell,
                    .status = .empty,
                    .occupied = false,
                    .surface = null,
                    .standability = null,
                },
                else => return .{
                    .world_x = world_x,
                    .world_z = world_z,
                    .cell = cell,
                    .status = .missing_top_surface,
                    .occupied = true,
                    .surface = null,
                    .standability = null,
                },
            };
        const standability = standabilityForSurface(surface);
        return .{
            .world_x = world_x,
            .world_z = world_z,
            .cell = cell,
            .status = .occupied_surface,
            .occupied = true,
            .surface = surface,
            .standability = standability,
        };
    }

    fn findNearestCandidateForHypothesis(
        self: WorldQuery,
        world_x: i32,
        world_z: i32,
        hypothesis: MappingHypothesis,
        kind: DiagnosticCandidateKind,
    ) !DiagnosticCandidate {
        var best: ?struct {
            candidate: DiagnosticCandidate,
        } = null;

        for (self.room.background.composition.tiles) |tile| {
            const surface = try self.cellTopSurface(tile.x, tile.z);
            const standability = standabilityForSurface(surface);
            if (kind == .standable and standability != .standable) continue;

            const cell = GridCell{ .x = tile.x, .z = tile.z };
            const world_bounds = gridCellWorldBoundsForHypothesis(cell.x, cell.z, hypothesis);
            const dx = axisDistanceToBounds(world_x, world_bounds.min_x, world_bounds.max_x);
            const dz = axisDistanceToBounds(world_z, world_bounds.min_z, world_bounds.max_z);
            const distance_sq = (@as(i64, dx) * @as(i64, dx)) + (@as(i64, dz) * @as(i64, dz));
            const candidate = DiagnosticCandidate{
                .kind = kind,
                .cell = cell,
                .world_bounds = world_bounds,
                .surface = surface,
                .standability = standability,
                .x_distance = dx,
                .z_distance = dz,
                .distance_sq = distance_sq,
            };

            if (best == null or
                distance_sq < best.?.candidate.distance_sq or
                (distance_sq == best.?.candidate.distance_sq and lessThanCell(cell, best.?.candidate.cell)))
            {
                best = .{ .candidate = candidate };
            }
        }

        const resolved = best orelse return switch (kind) {
            .occupied => error.HeroStartNoOccupiedCell,
            .standable => error.HeroStartNoStandableCell,
        };
        return resolved.candidate;
    }
};

pub fn init(room: *const room_state.RoomSnapshot) WorldQuery {
    return WorldQuery.init(room);
}

pub fn topologyRelationEvidencePolicy(
    basis: TopologyRelationEvidenceBasis,
) TopologyRelationEvidencePolicy {
    return switch (basis) {
        .guarded_runtime_room_snapshot => .{
            .basis = basis,
            .admission = .admitted_supported_runtime,
            .rationale = "Guarded room snapshots remain the only supported basis for runtime-facing topology semantics.",
        },
        .unchecked_evidence_room_snapshot => .{
            .basis = basis,
            .admission = .admitted_discovery_only,
            .rationale = "Unchecked evidence-only room snapshots may inform discovery-only topology observation because they still decode immutable room geometry, but bypassing the guarded loader policy keeps them outside the supported runtime boundary and insufficient on their own for runtime-facing relation classes.",
        },
    };
}

pub fn gridCellWorldBounds(x: usize, z: usize) WorldBounds {
    return gridCellWorldBoundsForHypothesis(x, z, .canonical_axis_aligned_512);
}

pub fn gridCellCenterWorldPosition(
    cell_x: usize,
    cell_z: usize,
    world_y: i32,
) WorldPointSnapshot {
    const bounds = gridCellWorldBounds(cell_x, cell_z);
    return .{
        .x = bounds.min_x + @divFloor(world_grid_span_xz, 2),
        .y = world_y,
        .z = bounds.min_z + @divFloor(world_grid_span_xz, 2),
    };
}

pub fn nearestStandableCenterWorldPosition(
    room: *const room_state.RoomSnapshot,
    world_x: i32,
    world_z: i32,
) !WorldPointSnapshot {
    const query = init(room);
    const candidate = try query.findNearestCandidateForHypothesis(
        world_x,
        world_z,
        .canonical_axis_aligned_512,
        .standable,
    );
    return gridCellCenterWorldPosition(candidate.cell.x, candidate.cell.z, candidate.surface.top_y);
}

fn buildMappingEvaluation(
    raw_world_position: WorldPointSnapshot,
    hypothesis: MappingHypothesis,
    evidence_case: MappingEvidenceCase,
    core: HeroStartEvaluationCore,
    comparison_to_canonical: MappingEvidenceComparison,
) HeroStartMappingEvaluation {
    const definition = hypothesis.definition();
    return .{
        .hypothesis = hypothesis,
        .family = definition.family,
        .role = hypothesis.role(),
        .rationale = definition.rationale,
        .evidence_case = evidence_case,
        .axis_interpretation = hypothesis.axisInterpretation(),
        .cell_span_xz = hypothesis.cellSpan(),
        .raw_world_position = raw_world_position,
        .raw_cell = core.raw_cell,
        .occupied_coverage = core.occupied_coverage,
        .exact_status = core.exact_status,
        .diagnostic_status = core.diagnostic_status,
        .nearest_occupied = core.nearest_occupied,
        .nearest_standable = core.nearest_standable,
        .comparison_to_canonical = comparison_to_canonical,
    };
}

pub fn evidenceCaseForAnchor(anchor_kind: EvidenceAnchorKind) MappingEvidenceCase {
    return switch (anchor_kind) {
        .hero_start_world_point => .{
            .anchor_kind = anchor_kind,
            .admission = .admitted,
            .allowed_metrics = all_evidence_metrics[0..],
        },
        .scene_object_world_point,
        .zone_world_point,
        => .{
            .anchor_kind = anchor_kind,
            .admission = .rejected_no_floor_truth,
            .allowed_metrics = no_evidence_metrics[0..],
        },
        .fragment_world_point => .{
            .anchor_kind = anchor_kind,
            .admission = .rejected_out_of_scope_basis,
            .allowed_metrics = no_evidence_metrics[0..],
        },
    };
}

fn compareEvidenceCaseAgainstCanonical(
    anchor_kind: EvidenceAnchorKind,
    canonical: HeroStartEvaluationCore,
    candidate: HeroStartEvaluationCore,
) MappingEvidenceCaseComparison {
    const evidence_case = evidenceCaseForAnchor(anchor_kind);
    return .{
        .evidence_case = evidence_case,
        .comparison = compareCoreAgainstCanonicalForEvidenceCase(evidence_case, canonical, candidate),
    };
}

fn compareCoreAgainstCanonicalForEvidenceCase(
    evidence_case: MappingEvidenceCase,
    canonical: HeroStartEvaluationCore,
    candidate: HeroStartEvaluationCore,
) MappingEvidenceComparison {
    if (evidence_case.admission != .admitted) return neutralEvidenceComparison();

    const exact_status = if (evidence_case.admitsMetric(.exact_status))
        compareExactStatus(candidate.exact_status, canonical.exact_status)
    else
        .equal;
    const occupied_coverage = if (evidence_case.admitsMetric(.occupied_coverage))
        compareOccupiedCoverage(candidate.occupied_coverage, canonical.occupied_coverage)
    else
        .equal;
    const nearest_occupied = if (evidence_case.admitsMetric(.nearest_occupied))
        compareNearestCandidate(candidate.nearest_occupied, canonical.nearest_occupied)
    else
        .equal;
    const nearest_standable = if (evidence_case.admitsMetric(.nearest_standable))
        compareNearestCandidate(candidate.nearest_standable, canonical.nearest_standable)
    else
        .equal;
    const primary_metric_better_count =
        metricBetterCount(exact_status) +
        metricBetterCount(occupied_coverage);
    const supporting_metric_better_count =
        metricBetterCount(nearest_occupied) +
        metricBetterCount(nearest_standable);
    const better_metric_count = primary_metric_better_count + supporting_metric_better_count;
    const worse_metric_count =
        metricWorseCount(exact_status) +
        metricWorseCount(occupied_coverage) +
        metricWorseCount(nearest_occupied) +
        metricWorseCount(nearest_standable);
    const stronger_evidence_bar_passed =
        worse_metric_count == 0 and
        primary_metric_better_count >= 1 and
        supporting_metric_better_count == 2 and
        better_metric_count >= 3;

    return .{
        .exact_status = exact_status,
        .occupied_coverage = occupied_coverage,
        .nearest_occupied = nearest_occupied,
        .nearest_standable = nearest_standable,
        .better_metric_count = better_metric_count,
        .worse_metric_count = worse_metric_count,
        .primary_metric_better_count = primary_metric_better_count,
        .supporting_metric_better_count = supporting_metric_better_count,
        .stronger_evidence_bar_passed = stronger_evidence_bar_passed,
        .disposition = if (stronger_evidence_bar_passed)
            .diagnostic_candidate_only_materially_better
        else if (better_metric_count > 0)
            .diagnostic_candidate_only_partial_signal
        else
            .diagnostic_candidate_only_not_better,
    };
}

fn neutralEvidenceComparison() MappingEvidenceComparison {
    return .{
        .exact_status = .equal,
        .occupied_coverage = .equal,
        .nearest_occupied = .equal,
        .nearest_standable = .equal,
        .better_metric_count = 0,
        .worse_metric_count = 0,
        .primary_metric_better_count = 0,
        .supporting_metric_better_count = 0,
        .stronger_evidence_bar_passed = false,
        .disposition = .diagnostic_candidate_only_not_better,
    };
}

fn metricBetterCount(comparison: EvidenceMetricComparison) u8 {
    return if (comparison == .better) 1 else 0;
}

fn metricWorseCount(comparison: EvidenceMetricComparison) u8 {
    return if (comparison == .worse) 1 else 0;
}

fn heroStartWorldPosition(room: *const room_state.RoomSnapshot) WorldPointSnapshot {
    return room_state.heroStartWorldPoint(room);
}

fn incrementTopYDeltaBucket(
    buckets: *std.ArrayList(ObservedTopYDeltaBucket),
    allocator: std.mem.Allocator,
    delta: i32,
) !void {
    for (buckets.items) |*bucket| {
        if (bucket.delta == delta) {
            bucket.count += 1;
            return;
        }
    }
    try buckets.append(allocator, .{
        .delta = delta,
        .count = 1,
    });
}

fn lessThanTopYDeltaBucket(
    _: void,
    left: ObservedTopYDeltaBucket,
    right: ObservedTopYDeltaBucket,
) bool {
    return left.delta < right.delta;
}

fn mapWorldPointToCellIndices(
    world_x: i32,
    world_z: i32,
    hypothesis: MappingHypothesis,
) struct { x: i32, z: i32 } {
    const span = hypothesis.cellSpan();
    return switch (hypothesis.axisInterpretation()) {
        .aligned => .{
            .x = @divFloor(world_x, span),
            .z = @divFloor(world_z, span),
        },
        .swapped => .{
            .x = @divFloor(world_z, span),
            .z = @divFloor(world_x, span),
        },
    };
}

fn gridCellWorldBoundsForHypothesis(
    x: usize,
    z: usize,
    hypothesis: MappingHypothesis,
) WorldBounds {
    const span_usize: usize = @intCast(hypothesis.cellSpan());
    const x_min_aligned: i32 = @intCast(x * span_usize);
    const z_min_aligned: i32 = @intCast(z * span_usize);
    const cell_span: i32 = hypothesis.cellSpan() - 1;
    return switch (hypothesis.axisInterpretation()) {
        .aligned => .{
            .min_x = x_min_aligned,
            .max_x = x_min_aligned + cell_span,
            .min_z = z_min_aligned,
            .max_z = z_min_aligned + cell_span,
        },
        .swapped => .{
            .min_x = z_min_aligned,
            .max_x = z_min_aligned + cell_span,
            .min_z = x_min_aligned,
            .max_z = x_min_aligned + cell_span,
        },
    };
}

fn compareExactStatus(
    candidate: HeroStartExactStatus,
    baseline: HeroStartExactStatus,
) EvidenceMetricComparison {
    return compareRankedMetric(
        exactStatusRank(candidate),
        exactStatusRank(baseline),
    );
}

fn compareOccupiedCoverage(
    candidate: OccupiedCoverageProbe,
    baseline: OccupiedCoverageProbe,
) EvidenceMetricComparison {
    const relation_cmp = compareRankedMetric(
        occupiedCoverageRank(candidate.relation),
        occupiedCoverageRank(baseline.relation),
    );
    if (relation_cmp != .equal) return relation_cmp;

    const candidate_distance = candidate.x_cells_from_bounds + candidate.z_cells_from_bounds;
    const baseline_distance = baseline.x_cells_from_bounds + baseline.z_cells_from_bounds;
    const distance_cmp = compareRankedMetric(candidate_distance, baseline_distance);
    if (distance_cmp != .equal) return distance_cmp;

    return compareRankedMetric(candidate.x_cells_from_bounds, baseline.x_cells_from_bounds);
}

fn compareNearestCandidate(
    candidate: ?DiagnosticCandidate,
    baseline: ?DiagnosticCandidate,
) EvidenceMetricComparison {
    if (candidate == null and baseline == null) return .equal;
    if (candidate != null and baseline == null) return .better;
    if (candidate == null and baseline != null) return .worse;
    return compareRankedMetric(candidate.?.distance_sq, baseline.?.distance_sq);
}

fn compareRankedMetric(candidate: anytype, baseline: @TypeOf(candidate)) EvidenceMetricComparison {
    if (candidate < baseline) return .better;
    if (candidate > baseline) return .worse;
    return .equal;
}

fn exactStatusRank(status: HeroStartExactStatus) u8 {
    return switch (status) {
        .valid => 0,
        .surface_height_mismatch => 1,
        .mapped_cell_blocked => 2,
        .mapped_cell_missing_top_surface => 3,
        .mapped_cell_empty => 4,
        .mapped_cell_out_of_bounds => 5,
    };
}

fn occupiedCoverageRank(relation: OccupiedCoverageRelation) u8 {
    return switch (relation) {
        .within_occupied_bounds => 0,
        .outside_occupied_bounds => 1,
        .no_occupied_bounds => 2,
        .unmapped_world_point => 3,
    };
}

pub fn standabilityForSurface(surface: CellTopSurface) Standability {
    return switch (surface.top_shape_class) {
        .solid,
        .single_stair,
        .double_stair_corner,
        .double_stair_peak,
        => .standable,
        .open,
        .weird,
        => .blocked,
    };
}

fn topSurfaceY(total_height: u8) i32 {
    return @as(i32, total_height) * world_grid_span_y;
}

fn axisDistanceToBounds(value: i32, min_value: i32, max_value: i32) i32 {
    if (value < min_value) return min_value - value;
    if (value > max_value) return value - max_value;
    return 0;
}

fn axisDistanceToRange(value: usize, min_value: usize, max_value: usize) usize {
    if (value < min_value) return min_value - value;
    if (value > max_value) return value - max_value;
    return 0;
}

fn lessThanCell(left: GridCell, right: GridCell) bool {
    if (left.z != right.z) return left.z < right.z;
    return left.x < right.x;
}

fn worldAxisMax(cell_count: usize) i32 {
    if (cell_count == 0) return 0;
    return @intCast((cell_count * world_grid_span_xz_usize) - 1);
}

fn assessZoneAnchorCandidate(room: *const room_state.RoomSnapshot) AnchorCandidateAssessment {
    var floor_aligned_sample_count: usize = 0;
    for (room.scene.zones) |zone| {
        if (isFloorAlignedY(zone.y_min) and isFloorAlignedY(zone.y_max)) {
            floor_aligned_sample_count += 1;
        }
    }

    return .{
        .anchor_kind = .zone_world_point,
        .sample_count = room.scene.zones.len,
        .floor_aligned_sample_count = floor_aligned_sample_count,
        .priority_score = if (room.scene.zones.len > 0 and floor_aligned_sample_count == room.scene.zones.len) 2 else if (floor_aligned_sample_count > 0) 1 else 0,
        .rationale = "Zone bounds are the stronger current candidate because they stay in room-world coordinates and their Y extents remain floor-grid aligned, even though they still describe trigger volumes rather than floor points.",
    };
}

fn assessSceneObjectAnchorCandidate(room: *const room_state.RoomSnapshot) AnchorCandidateAssessment {
    var sample_count: usize = 0;
    var floor_aligned_sample_count: usize = 0;
    for (room.scene.objects) |object| {
        if (object.x == 0 and object.y == 0 and object.z == 0) continue;
        sample_count += 1;
        if (isFloorAlignedY(object.y)) floor_aligned_sample_count += 1;
    }

    return .{
        .anchor_kind = .scene_object_world_point,
        .sample_count = sample_count,
        .floor_aligned_sample_count = floor_aligned_sample_count,
        .priority_score = if (sample_count > 0 and floor_aligned_sample_count == sample_count) 2 else if (floor_aligned_sample_count > 0) 1 else 0,
        .rationale = "Scene-object placements are weaker current evidence because the positioned non-origin samples are sparse and can sit off the 256-unit floor grid, so they do not presently read as reliable standable-floor anchors.",
    };
}

fn rankAdditionalAnchorCandidates(
    first: AnchorCandidateAssessment,
    second: AnchorCandidateAssessment,
) [2]AdditionalAnchorCandidateRanking {
    const ordered = if (first.priority_score >= second.priority_score)
        [_]AnchorCandidateAssessment{ first, second }
    else
        [_]AnchorCandidateAssessment{ second, first };
    return .{
        .{
            .anchor_kind = ordered[0].anchor_kind,
            .priority = .primary,
            .sample_count = ordered[0].sample_count,
            .floor_aligned_sample_count = ordered[0].floor_aligned_sample_count,
            .rationale = ordered[0].rationale,
        },
        .{
            .anchor_kind = ordered[1].anchor_kind,
            .priority = .secondary,
            .sample_count = ordered[1].sample_count,
            .floor_aligned_sample_count = ordered[1].floor_aligned_sample_count,
            .rationale = ordered[1].rationale,
        },
    };
}

fn decisionRationaleForAnchor(anchor_kind: EvidenceAnchorKind) []const u8 {
    return switch (anchor_kind) {
        .zone_world_point => "Zone bounds stay rejected because the checked-in room snapshot only proves volumetric trigger regions; admitting a single point would require inventing an unsupported center, corner, or floor-projection policy.",
        .scene_object_world_point => "Scene-object points stay rejected because the checked-in room snapshot does not show a source-backed floor-truth relationship between those placements and standable surfaces.",
        .hero_start_world_point => "Hero start remains the canonical admitted floor-truth anchor class for current mapping evaluation.",
        .fragment_world_point => "Fragment anchors remain outside the current evidence basis.",
    };
}

fn isFloorAlignedY(world_y: i32) bool {
    return @mod(world_y, world_grid_span_y) == 0;
}

fn exactStatusForProbe(raw_cell: WorldPointCellProbe, hero_y: i32) HeroStartExactStatus {
    return switch (raw_cell.status) {
        .out_of_bounds => .mapped_cell_out_of_bounds,
        .empty => .mapped_cell_empty,
        .missing_top_surface => .mapped_cell_missing_top_surface,
        .occupied_surface => blk: {
            if (raw_cell.standability.? != .standable) break :blk .mapped_cell_blocked;
            if (raw_cell.surface.?.top_y != hero_y) break :blk .surface_height_mismatch;
            break :blk .valid;
        },
    };
}

fn diagnosticStatusForProbe(
    exact_status: HeroStartExactStatus,
    occupied_coverage: OccupiedCoverageProbe,
    nearest_occupied: ?DiagnosticCandidate,
    nearest_standable: ?DiagnosticCandidate,
) HeroStartDiagnosticStatus {
    if (exact_status == .valid) return .exact_valid;
    if (occupied_coverage.relation == .unmapped_world_point or occupied_coverage.relation == .outside_occupied_bounds) {
        return .exact_invalid_mapping_mismatch;
    }
    if (nearest_occupied != null or nearest_standable != null) return .exact_invalid_candidate_only;
    return .exact_invalid_no_candidate;
}

fn moveTargetStatusForProbe(raw_cell: WorldPointCellProbe, hero_y: i32) MoveTargetStatus {
    return switch (exactStatusForProbe(raw_cell, hero_y)) {
        .valid => .allowed,
        .mapped_cell_out_of_bounds => .target_out_of_bounds,
        .mapped_cell_empty => .target_empty,
        .mapped_cell_missing_top_surface => .target_missing_top_surface,
        .mapped_cell_blocked => .target_blocked,
        .surface_height_mismatch => .target_height_mismatch,
    };
}

fn zoneContainsWorldPoint(zone: room_state.ZoneBoundsSnapshot, world_position: WorldPointSnapshot) bool {
    return world_position.x >= zone.x_min and
        world_position.x <= zone.x_max and
        world_position.y >= zone.y_min and
        world_position.y <= zone.y_max and
        world_position.z >= zone.z_min and
        world_position.z <= zone.z_max;
}

fn worldPointSteppedInDirection(
    origin_world_position: WorldPointSnapshot,
    direction: CardinalDirection,
) WorldPointSnapshot {
    return switch (direction) {
        .north => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z - world_grid_span_xz,
        },
        .east => .{
            .x = origin_world_position.x + world_grid_span_xz,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
        .south => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z + world_grid_span_xz,
        },
        .west => .{
            .x = origin_world_position.x - world_grid_span_xz,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
    };
}

test "runtime world query consumes the guarded room snapshot for base topology queries" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const occupied_tile = room.background.composition.tiles[0];
    const surface = try query.cellTopSurface(occupied_tile.x, occupied_tile.z);

    try std.testing.expectEqual(GridBounds{
        .width = 64,
        .depth = 64,
        .occupied_bounds = .{
            .min_x = 39,
            .max_x = 63,
            .min_z = 6,
            .max_z = 58,
        },
    }, query.gridBounds());
    try std.testing.expectEqual(WorldBounds{
        .min_x = 0,
        .max_x = 32767,
        .min_z = 0,
        .max_z = 32767,
    }, query.roomWorldBounds());
    try std.testing.expect(try query.isOccupiedCell(occupied_tile.x, occupied_tile.z));
    try std.testing.expectEqual(occupied_tile.x, surface.cell.x);
    try std.testing.expectEqual(occupied_tile.z, surface.cell.z);
    try std.testing.expectEqual(occupied_tile.total_height, surface.total_height);
    try std.testing.expectEqual(occupied_tile.stack_depth, surface.stack_depth);
    try std.testing.expectEqual(occupied_tile.top_floor_type, surface.top_floor_type);
    try std.testing.expectEqual(occupied_tile.top_shape, surface.top_shape);
    try std.testing.expectEqual(occupied_tile.top_shape_class, surface.top_shape_class);
    try std.testing.expectEqual(occupied_tile.top_brick_index, surface.top_brick_index);
}

test "runtime world query rejects empty and out-of-bounds cells explicitly" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);

    try std.testing.expectEqual(false, try query.isOccupiedCell(0, 0));
    try std.testing.expectError(error.WorldCellEmpty, query.cellTopSurface(0, 0));
    try std.testing.expectError(error.WorldCellOutOfBounds, query.cellTopSurface(64, 0));
    try std.testing.expectError(error.WorldPointOutOfBounds, query.gridCellAtWorldPoint(-1, 0));
}

test "runtime world query reports diagnostic local neighbor topology for an occupied 19/19 cell" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const origin_tile = room.background.composition.tiles[0];
    const topology = try query.probeLocalNeighborTopology(origin_tile.x, origin_tile.z);

    try std.testing.expectEqual(origin_tile.x, topology.origin_surface.cell.x);
    try std.testing.expectEqual(origin_tile.z, topology.origin_surface.cell.z);
    try std.testing.expectEqual(try query.standabilityAtCell(origin_tile.x, origin_tile.z), topology.origin_standability);

    var expected_standable_neighbor_count: usize = 0;
    for (topology.neighbors, cardinal_directions) |neighbor, direction| {
        try std.testing.expectEqual(direction, neighbor.direction);

        const expected_cell = expectedNeighborCell(query.gridBounds(), topology.origin_surface.cell, direction);
        try std.testing.expectEqual(expected_cell, neighbor.cell);
        if (expected_cell == null) {
            try std.testing.expectEqual(CellProbeStatus.out_of_bounds, neighbor.status);
            try std.testing.expectEqual(false, neighbor.occupied);
            try std.testing.expectEqual(@as(?WorldBounds, null), neighbor.world_bounds);
            try std.testing.expectEqual(@as(?CellTopSurface, null), neighbor.surface);
            try std.testing.expectEqual(@as(?Standability, null), neighbor.standability);
            try std.testing.expectEqual(@as(?i32, null), neighbor.top_y_delta);
            continue;
        }

        try std.testing.expectEqual(gridCellWorldBounds(expected_cell.?.x, expected_cell.?.z), neighbor.world_bounds.?);

        const occupied = try query.isOccupiedCell(expected_cell.?.x, expected_cell.?.z);
        try std.testing.expectEqual(occupied, neighbor.occupied);
        if (!occupied) {
            try std.testing.expectEqual(CellProbeStatus.empty, neighbor.status);
            try std.testing.expectEqual(@as(?CellTopSurface, null), neighbor.surface);
            try std.testing.expectEqual(@as(?Standability, null), neighbor.standability);
            try std.testing.expectEqual(@as(?i32, null), neighbor.top_y_delta);
            continue;
        }

        const expected_surface = query.cellTopSurface(expected_cell.?.x, expected_cell.?.z) catch |err| switch (err) {
            error.WorldCellMissingTopSurface => {
                try std.testing.expectEqual(CellProbeStatus.missing_top_surface, neighbor.status);
                try std.testing.expectEqual(@as(?CellTopSurface, null), neighbor.surface);
                try std.testing.expectEqual(@as(?Standability, null), neighbor.standability);
                try std.testing.expectEqual(@as(?i32, null), neighbor.top_y_delta);
                continue;
            },
            else => return err,
        };
        const expected_standability = try query.standabilityAtCell(expected_cell.?.x, expected_cell.?.z);
        try std.testing.expectEqual(CellProbeStatus.occupied_surface, neighbor.status);
        try std.testing.expectEqual(expected_surface, neighbor.surface.?);
        try std.testing.expectEqual(expected_standability, neighbor.standability.?);
        try std.testing.expectEqual(expected_surface.top_y - topology.origin_surface.top_y, neighbor.top_y_delta.?);
        if (expected_standability == .standable) expected_standable_neighbor_count += 1;
    }

    try std.testing.expectEqual(expected_standable_neighbor_count, topology.standableNeighborCount());
}

test "runtime world query rejects invalid origin cells for local neighbor topology probes" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);

    try std.testing.expectError(error.WorldCellEmpty, query.probeLocalNeighborTopology(0, 0));
    try std.testing.expectError(error.WorldCellOutOfBounds, query.probeLocalNeighborTopology(64, 0));
}

test "runtime world query summarizes observed local neighbor patterns on the guarded 19/19 baseline" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const summary = try query.summarizeObservedNeighborPatterns(allocator);
    defer summary.deinit(allocator);

    try std.testing.expectEqual(room.background.composition.tiles.len, summary.origin_cell_count);
    try std.testing.expectEqual(summary.origin_cell_count * cardinal_directions.len, summary.total_neighbor_count);
    try std.testing.expectEqual(@as(usize, 4828), summary.occupied_surface_count);
    try std.testing.expectEqual(@as(usize, 107), summary.empty_count);
    try std.testing.expectEqual(@as(usize, 49), summary.out_of_bounds_count);
    try std.testing.expectEqual(@as(usize, 0), summary.missing_top_surface_count);
    try std.testing.expectEqual(@as(usize, 4828), summary.standable_neighbor_count);
    try std.testing.expectEqual(@as(usize, 0), summary.blocked_neighbor_count);
    try std.testing.expectEqual(summary.occupied_surface_count, summary.standable_neighbor_count + summary.blocked_neighbor_count);
    try std.testing.expectEqual(summary.total_neighbor_count, summary.occupied_surface_count + summary.empty_count + summary.out_of_bounds_count + summary.missing_top_surface_count);
    try std.testing.expectEqual(@as(usize, 1), summary.top_y_delta_buckets.len);
    try std.testing.expectEqual(ObservedTopYDeltaBucket{
        .delta = 0,
        .count = 4828,
    }, summary.top_y_delta_buckets[0]);
}

test "runtime world query separates raw hero-start mapping evidence from heuristic candidates on the supported snapshot" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    try std.testing.expectError(error.HeroStartCellEmpty, query.validateHeroStart());

    const hero_start = try query.probeHeroStart();
    const raw_cell = hero_start.raw_cell.cell.?;

    try std.testing.expectEqual(@as(i32, 1987), hero_start.raw_world_position.x);
    try std.testing.expectEqual(@as(i32, 512), hero_start.raw_world_position.y);
    try std.testing.expectEqual(@as(i32, 3743), hero_start.raw_world_position.z);
    try std.testing.expectEqual(@as(usize, 3), raw_cell.x);
    try std.testing.expectEqual(@as(usize, 7), raw_cell.z);
    try std.testing.expectEqual(CellProbeStatus.empty, hero_start.raw_cell.status);
    try std.testing.expectEqual(false, hero_start.raw_cell.occupied);
    try std.testing.expectEqual(@as(?CellTopSurface, null), hero_start.raw_cell.surface);
    try std.testing.expectEqual(@as(?Standability, null), hero_start.raw_cell.standability);
    try std.testing.expectEqual(HeroStartExactStatus.mapped_cell_empty, hero_start.exact_status);
    try std.testing.expectEqual(HeroStartDiagnosticStatus.exact_invalid_mapping_mismatch, hero_start.diagnostic_status);
    try std.testing.expectEqual(OccupiedCoverageRelation.outside_occupied_bounds, hero_start.occupied_coverage.relation);
    try std.testing.expectEqual(@as(?room_state.CompositionBoundsSnapshot, .{
        .min_x = 39,
        .max_x = 63,
        .min_z = 6,
        .max_z = 58,
    }), hero_start.occupied_coverage.occupied_bounds);
    try std.testing.expectEqual(@as(usize, 36), hero_start.occupied_coverage.x_cells_from_bounds);
    try std.testing.expectEqual(@as(usize, 0), hero_start.occupied_coverage.z_cells_from_bounds);
    try std.testing.expect(hero_start.nearest_occupied != null);
    try std.testing.expect(hero_start.nearest_standable != null);
    try std.testing.expectEqual(DiagnosticCandidateKind.occupied, hero_start.nearest_occupied.?.kind);
    try std.testing.expectEqual(DiagnosticCandidateKind.standable, hero_start.nearest_standable.?.kind);
    try std.testing.expect(hero_start.nearest_occupied.?.cell.x >= hero_start.occupied_coverage.occupied_bounds.?.min_x);
    try std.testing.expect(hero_start.nearest_occupied.?.cell.x <= hero_start.occupied_coverage.occupied_bounds.?.max_x);
    try std.testing.expect(hero_start.nearest_occupied.?.cell.z >= hero_start.occupied_coverage.occupied_bounds.?.min_z);
    try std.testing.expect(hero_start.nearest_occupied.?.cell.z <= hero_start.occupied_coverage.occupied_bounds.?.max_z);
    try std.testing.expectEqual(Standability.standable, hero_start.nearest_standable.?.standability);
    try std.testing.expect(hero_start.nearest_standable.?.distance_sq >= hero_start.nearest_occupied.?.distance_sq);
    try std.testing.expect(hero_start.nearest_standable.?.world_bounds.min_x > hero_start.raw_world_position.x);
    try std.testing.expectEqual(@as(i32, 0), hero_start.nearest_standable.?.z_distance);
}

test "runtime world query keeps the baked 19/19 hero start invalid under move-target evaluation" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const runtime_session = session.Session.init(room_state.heroStartWorldPoint(room));
    const hero_start_move = query.evaluateHeroMoveTarget(runtime_session.heroWorldPosition());

    try std.testing.expectEqual(runtime_session.heroWorldPosition(), hero_start_move.target_world_position);
    try std.testing.expectEqual(MoveTargetStatus.target_empty, hero_start_move.status);
    try std.testing.expectEqual(false, hero_start_move.isAllowed());
    try std.testing.expectEqual(@as(?GridCell, .{ .x = 3, .z = 7 }), hero_start_move.raw_cell.cell);
    try std.testing.expectEqual(CellProbeStatus.empty, hero_start_move.raw_cell.status);
    try std.testing.expectEqual(OccupiedCoverageRelation.outside_occupied_bounds, hero_start_move.occupied_coverage.relation);
}

test "runtime world query evaluates bounded move targets from a seeded guarded 19/19 fixture" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const seeded_surface = try query.cellTopSurface(39, 6);
    const south_surface = try query.cellTopSurface(39, 7);
    try std.testing.expectEqual(Standability.standable, try query.standabilityAtCell(39, 6));
    try std.testing.expectEqual(Standability.standable, try query.standabilityAtCell(39, 7));
    try std.testing.expectEqual(@as(i32, 6400), seeded_surface.top_y);
    try std.testing.expectEqual(seeded_surface.top_y, south_surface.top_y);

    const seeded_start = gridCellCenterWorldPosition(39, 6, seeded_surface.top_y);
    const allowed_target = gridCellCenterWorldPosition(39, 7, south_surface.top_y);
    const empty_target = gridCellCenterWorldPosition(38, 6, seeded_surface.top_y);
    const out_of_bounds_target = WorldPointSnapshot{
        .x = -1,
        .y = seeded_surface.top_y,
        .z = allowed_target.z,
    };
    const height_mismatch_target = gridCellCenterWorldPosition(39, 7, south_surface.top_y - world_grid_span_y);

    var runtime_session = session.Session.init(room_state.heroStartWorldPoint(room));
    runtime_session.setHeroWorldPosition(seeded_start);
    try std.testing.expectEqual(seeded_start, runtime_session.heroWorldPosition());
    try std.testing.expect(runtime_session.heroWorldPosition().x != room.scene.hero_start.x);
    try std.testing.expect(runtime_session.heroWorldPosition().z != room.scene.hero_start.z);

    const seeded_origin_eval = query.evaluateHeroMoveTarget(runtime_session.heroWorldPosition());
    try std.testing.expectEqual(MoveTargetStatus.allowed, seeded_origin_eval.status);
    try std.testing.expectEqual(true, seeded_origin_eval.isAllowed());
    try std.testing.expectEqual(@as(?GridCell, .{ .x = 39, .z = 6 }), seeded_origin_eval.raw_cell.cell);

    const allowed_move = query.evaluateHeroMoveTarget(allowed_target);
    try std.testing.expectEqual(MoveTargetStatus.allowed, allowed_move.status);
    try std.testing.expectEqual(true, allowed_move.isAllowed());
    try std.testing.expectEqual(@as(?GridCell, .{ .x = 39, .z = 7 }), allowed_move.raw_cell.cell);
    try std.testing.expectEqual(OccupiedCoverageRelation.within_occupied_bounds, allowed_move.occupied_coverage.relation);

    const empty_move = query.evaluateHeroMoveTarget(empty_target);
    try std.testing.expectEqual(MoveTargetStatus.target_empty, empty_move.status);
    try std.testing.expectEqual(false, empty_move.isAllowed());
    try std.testing.expectEqual(@as(?GridCell, .{ .x = 38, .z = 6 }), empty_move.raw_cell.cell);
    try std.testing.expectEqual(OccupiedCoverageRelation.outside_occupied_bounds, empty_move.occupied_coverage.relation);

    const out_of_bounds_move = query.evaluateHeroMoveTarget(out_of_bounds_target);
    try std.testing.expectEqual(MoveTargetStatus.target_out_of_bounds, out_of_bounds_move.status);
    try std.testing.expectEqual(false, out_of_bounds_move.isAllowed());
    try std.testing.expectEqual(@as(?GridCell, null), out_of_bounds_move.raw_cell.cell);
    try std.testing.expectEqual(OccupiedCoverageRelation.unmapped_world_point, out_of_bounds_move.occupied_coverage.relation);

    const height_mismatch_move = query.evaluateHeroMoveTarget(height_mismatch_target);
    try std.testing.expectEqual(MoveTargetStatus.target_height_mismatch, height_mismatch_move.status);
    try std.testing.expectEqual(false, height_mismatch_move.isAllowed());
    try std.testing.expectEqual(@as(?GridCell, .{ .x = 39, .z = 7 }), height_mismatch_move.raw_cell.cell);
    try std.testing.expectEqual(OccupiedCoverageRelation.within_occupied_bounds, height_mismatch_move.occupied_coverage.relation);

    var first_blocked_cell: ?GridCell = null;
    for (room.background.composition.tiles) |tile| {
        if (try query.standabilityAtCell(tile.x, tile.z) == .blocked) {
            first_blocked_cell = .{ .x = tile.x, .z = tile.z };
            break;
        }
    }
    try std.testing.expectEqual(@as(?GridCell, null), first_blocked_cell);
}

test "runtime world query evaluates cardinal move options from an admitted guarded 19/19 position" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const seeded_surface = try query.cellTopSurface(39, 6);
    const seeded_start = gridCellCenterWorldPosition(39, 6, seeded_surface.top_y);

    const option_set = try query.evaluateCardinalMoveOptions(seeded_start);

    try std.testing.expectEqual(MoveTargetStatus.allowed, option_set.origin.status);
    try std.testing.expectEqual(@as(?GridCell, .{ .x = 39, .z = 6 }), option_set.origin.raw_cell.cell);

    const north_eval = query.evaluateHeroMoveTarget(WorldPointSnapshot{
        .x = seeded_start.x,
        .y = seeded_start.y,
        .z = seeded_start.z - world_grid_span_xz,
    });
    const east_eval = query.evaluateHeroMoveTarget(WorldPointSnapshot{
        .x = seeded_start.x + world_grid_span_xz,
        .y = seeded_start.y,
        .z = seeded_start.z,
    });
    const south_eval = query.evaluateHeroMoveTarget(WorldPointSnapshot{
        .x = seeded_start.x,
        .y = seeded_start.y,
        .z = seeded_start.z + world_grid_span_xz,
    });
    const west_eval = query.evaluateHeroMoveTarget(WorldPointSnapshot{
        .x = seeded_start.x - world_grid_span_xz,
        .y = seeded_start.y,
        .z = seeded_start.z,
    });

    try std.testing.expectEqual(CardinalDirection.north, option_set.options[0].direction);
    try std.testing.expectEqual(CardinalDirection.east, option_set.options[1].direction);
    try std.testing.expectEqual(CardinalDirection.south, option_set.options[2].direction);
    try std.testing.expectEqual(CardinalDirection.west, option_set.options[3].direction);
    try std.testing.expectEqual(north_eval, option_set.options[0].evaluation);
    try std.testing.expectEqual(east_eval, option_set.options[1].evaluation);
    try std.testing.expectEqual(south_eval, option_set.options[2].evaluation);
    try std.testing.expectEqual(west_eval, option_set.options[3].evaluation);
}

test "runtime world query rejects cardinal move options from the invalid baked guarded 19/19 start" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const runtime_session = session.Session.init(room_state.heroStartWorldPoint(room));

    try std.testing.expectError(
        error.MoveTargetOriginInvalid,
        query.evaluateCardinalMoveOptions(runtime_session.heroWorldPosition()),
    );
}

test "runtime world query compares fixed mapping hypotheses without promoting diagnostic candidates" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const report = try query.evaluateHeroStartMappings();
    const canonical = report.evaluation(.canonical_axis_aligned_512);
    const swapped_512 = report.evaluation(.swapped_axes_512_control);
    const dense_swapped_64 = report.evaluation(.dense_swapped_axes_64);

    try std.testing.expectEqual(@as(i32, 1987), report.raw_world_position.x);
    try std.testing.expectEqual(@as(i32, 512), report.raw_world_position.y);
    try std.testing.expectEqual(@as(i32, 3743), report.raw_world_position.z);

    try std.testing.expectEqual(@as(usize, 3), report.evaluations.len);
    try std.testing.expectEqual(MappingHypothesisRole.canonical_runtime_mapping, canonical.role);
    try std.testing.expectEqual(MappingHypothesisFamily.canonical, canonical.family);
    try std.testing.expectEqual(MappingEvidenceDisposition.canonical_mapping_poor_on_current_evidence, canonical.comparison_to_canonical.disposition);
    try std.testing.expectEqual(MappingHypothesisRole.diagnostic_candidate_only, swapped_512.role);
    try std.testing.expectEqual(MappingHypothesisFamily.axis_swap_control, swapped_512.family);
    try std.testing.expectEqual(MappingHypothesisRole.diagnostic_candidate_only, dense_swapped_64.role);
    try std.testing.expectEqual(MappingHypothesisFamily.dense_grid_candidate, dense_swapped_64.family);
    try std.testing.expectEqualStrings("Current runtime mapping under the guarded 19/19 baseline.", canonical.rationale);
    try std.testing.expectEqualStrings("Axis-swap control at the canonical span; tests whether orientation alone explains the mismatch.", swapped_512.rationale);
    try std.testing.expectEqual(EvidenceAnchorKind.hero_start_world_point, canonical.evidence_case.anchor_kind);
    try std.testing.expectEqual(EvidenceAdmission.admitted, canonical.evidence_case.admission);
    try std.testing.expectEqual(@as(usize, 4), canonical.evidence_case.allowed_metrics.len);

    try std.testing.expectEqual(MappingAxisInterpretation.swapped, swapped_512.axis_interpretation);
    try std.testing.expectEqual(MappingAxisInterpretation.swapped, dense_swapped_64.axis_interpretation);
    try std.testing.expectEqual(@as(i32, 64), dense_swapped_64.cell_span_xz);

    try std.testing.expectEqual(@as(usize, 3), canonical.raw_cell.cell.?.x);
    try std.testing.expectEqual(@as(usize, 7), canonical.raw_cell.cell.?.z);
    try std.testing.expectEqual(@as(usize, 7), swapped_512.raw_cell.cell.?.x);
    try std.testing.expectEqual(@as(usize, 3), swapped_512.raw_cell.cell.?.z);
    try std.testing.expectEqual(@as(usize, 58), dense_swapped_64.raw_cell.cell.?.x);
    try std.testing.expectEqual(@as(usize, 31), dense_swapped_64.raw_cell.cell.?.z);

    try std.testing.expectEqual(OccupiedCoverageRelation.outside_occupied_bounds, canonical.occupied_coverage.relation);
    try std.testing.expectEqual(OccupiedCoverageRelation.within_occupied_bounds, dense_swapped_64.occupied_coverage.relation);
    try std.testing.expectEqual(EvidenceMetricComparison.better, dense_swapped_64.comparison_to_canonical.occupied_coverage);
    try std.testing.expect(canonical.exact_status != .valid);
    try std.testing.expectEqual(@as(u8, 0), canonical.comparison_to_canonical.better_metric_count);
    try std.testing.expectEqual(@as(u8, 0), canonical.comparison_to_canonical.worse_metric_count);
    try std.testing.expectEqual(false, canonical.comparison_to_canonical.stronger_evidence_bar_passed);
    try std.testing.expectEqual(MappingEvidenceDisposition.diagnostic_candidate_only_materially_better, dense_swapped_64.comparison_to_canonical.disposition);
    try std.testing.expect(dense_swapped_64.comparison_to_canonical.better_metric_count >= 3);
    try std.testing.expectEqual(@as(u8, 0), dense_swapped_64.comparison_to_canonical.worse_metric_count);
    try std.testing.expectEqual(true, dense_swapped_64.comparison_to_canonical.stronger_evidence_bar_passed);

    try std.testing.expect(canonical.nearest_occupied != null);
    try std.testing.expect(dense_swapped_64.nearest_occupied != null);
    try std.testing.expect(dense_swapped_64.nearest_occupied.?.distance_sq < canonical.nearest_occupied.?.distance_sq);

    const canonical_cell = try query.gridCellAtWorldPoint(report.raw_world_position.x, report.raw_world_position.z);
    try std.testing.expectEqual(canonical.raw_cell.cell.?.x, canonical_cell.x);
    try std.testing.expectEqual(canonical.raw_cell.cell.?.z, canonical_cell.z);
    try std.testing.expect(dense_swapped_64.raw_cell.cell.?.x != canonical_cell.x or dense_swapped_64.raw_cell.cell.?.z != canonical_cell.z);
    for (report.evaluations) |evaluation| {
        try std.testing.expect(!(evaluation.cell_span_xz == 64 and evaluation.axis_interpretation == .aligned));
    }

    const runtime_session = session.Session.init(room_state.heroStartWorldPoint(room));
    const hero_position = runtime_session.heroWorldPosition();
    try std.testing.expectEqual(report.raw_world_position.x, hero_position.x);
    try std.testing.expectEqual(report.raw_world_position.y, hero_position.y);
    try std.testing.expectEqual(report.raw_world_position.z, hero_position.z);
}

test "runtime world query reports out-of-bounds mapping evidence without forcing a heuristic narrative" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const raw_cell = query.probeCellAtWorldPoint(-16, 3743);
    const coverage = query.occupiedCoverageForCell(raw_cell.cell);

    try std.testing.expectEqual(CellProbeStatus.out_of_bounds, raw_cell.status);
    try std.testing.expectEqual(@as(?GridCell, null), raw_cell.cell);
    try std.testing.expectEqual(OccupiedCoverageRelation.unmapped_world_point, coverage.relation);
}

test "runtime world query keeps a single flattering metric as diagnostic-only partial signal" {
    const canonical = HeroStartEvaluationCore{
        .raw_cell = .{
            .world_x = 1987,
            .world_z = 3743,
            .cell = .{ .x = 3, .z = 7 },
            .status = .empty,
            .occupied = false,
            .surface = null,
            .standability = null,
        },
        .occupied_coverage = .{
            .relation = .outside_occupied_bounds,
            .occupied_bounds = .{
                .min_x = 39,
                .max_x = 63,
                .min_z = 6,
                .max_z = 58,
            },
            .x_cells_from_bounds = 36,
            .z_cells_from_bounds = 0,
        },
        .exact_status = .mapped_cell_empty,
        .diagnostic_status = .exact_invalid_mapping_mismatch,
        .nearest_occupied = testDiagnosticCandidate(.occupied, 64),
        .nearest_standable = testDiagnosticCandidate(.standable, 144),
    };
    const candidate = HeroStartEvaluationCore{
        .raw_cell = canonical.raw_cell,
        .occupied_coverage = .{
            .relation = .outside_occupied_bounds,
            .occupied_bounds = canonical.occupied_coverage.occupied_bounds,
            .x_cells_from_bounds = 8,
            .z_cells_from_bounds = 0,
        },
        .exact_status = .mapped_cell_empty,
        .diagnostic_status = .exact_invalid_mapping_mismatch,
        .nearest_occupied = testDiagnosticCandidate(.occupied, 64),
        .nearest_standable = testDiagnosticCandidate(.standable, 144),
    };

    const assessment = compareEvidenceCaseAgainstCanonical(.hero_start_world_point, canonical, candidate);
    try std.testing.expectEqual(EvidenceAdmission.admitted, assessment.evidence_case.admission);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.exact_status);
    try std.testing.expectEqual(EvidenceMetricComparison.better, assessment.comparison.occupied_coverage);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.nearest_occupied);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.nearest_standable);
    try std.testing.expectEqual(@as(u8, 1), assessment.comparison.better_metric_count);
    try std.testing.expectEqual(@as(u8, 0), assessment.comparison.worse_metric_count);
    try std.testing.expectEqual(@as(u8, 1), assessment.comparison.primary_metric_better_count);
    try std.testing.expectEqual(@as(u8, 0), assessment.comparison.supporting_metric_better_count);
    try std.testing.expectEqual(false, assessment.comparison.stronger_evidence_bar_passed);
    try std.testing.expectEqual(MappingEvidenceDisposition.diagnostic_candidate_only_partial_signal, assessment.comparison.disposition);
}

test "runtime world query requires cross-metric agreement before a candidate counts as materially better" {
    const canonical = HeroStartEvaluationCore{
        .raw_cell = .{
            .world_x = 1987,
            .world_z = 3743,
            .cell = .{ .x = 3, .z = 7 },
            .status = .empty,
            .occupied = false,
            .surface = null,
            .standability = null,
        },
        .occupied_coverage = .{
            .relation = .outside_occupied_bounds,
            .occupied_bounds = .{
                .min_x = 39,
                .max_x = 63,
                .min_z = 6,
                .max_z = 58,
            },
            .x_cells_from_bounds = 36,
            .z_cells_from_bounds = 0,
        },
        .exact_status = .mapped_cell_empty,
        .diagnostic_status = .exact_invalid_mapping_mismatch,
        .nearest_occupied = testDiagnosticCandidate(.occupied, 256),
        .nearest_standable = testDiagnosticCandidate(.standable, 400),
    };
    const candidate = HeroStartEvaluationCore{
        .raw_cell = .{
            .world_x = 1987,
            .world_z = 3743,
            .cell = .{ .x = 58, .z = 31 },
            .status = .occupied_surface,
            .occupied = true,
            .surface = testTopSurface(),
            .standability = .standable,
        },
        .occupied_coverage = .{
            .relation = .within_occupied_bounds,
            .occupied_bounds = canonical.occupied_coverage.occupied_bounds,
            .x_cells_from_bounds = 0,
            .z_cells_from_bounds = 0,
        },
        .exact_status = .surface_height_mismatch,
        .diagnostic_status = .exact_invalid_candidate_only,
        .nearest_occupied = testDiagnosticCandidate(.occupied, 4),
        .nearest_standable = testDiagnosticCandidate(.standable, 9),
    };

    const assessment = compareEvidenceCaseAgainstCanonical(.hero_start_world_point, canonical, candidate);
    try std.testing.expectEqual(EvidenceAdmission.admitted, assessment.evidence_case.admission);
    try std.testing.expectEqual(EvidenceMetricComparison.better, assessment.comparison.exact_status);
    try std.testing.expectEqual(EvidenceMetricComparison.better, assessment.comparison.occupied_coverage);
    try std.testing.expectEqual(EvidenceMetricComparison.better, assessment.comparison.nearest_occupied);
    try std.testing.expectEqual(EvidenceMetricComparison.better, assessment.comparison.nearest_standable);
    try std.testing.expectEqual(@as(u8, 4), assessment.comparison.better_metric_count);
    try std.testing.expectEqual(@as(u8, 0), assessment.comparison.worse_metric_count);
    try std.testing.expectEqual(@as(u8, 2), assessment.comparison.primary_metric_better_count);
    try std.testing.expectEqual(@as(u8, 2), assessment.comparison.supporting_metric_better_count);
    try std.testing.expectEqual(true, assessment.comparison.stronger_evidence_bar_passed);
    try std.testing.expectEqual(MappingEvidenceDisposition.diagnostic_candidate_only_materially_better, assessment.comparison.disposition);
}

test "runtime world query rejects scene-object anchors without floor-truth scoring" {
    const canonical = testHeroStartCore(.mapped_cell_empty, 36, 64, 144);
    const candidate = testHeroStartCore(.surface_height_mismatch, 0, 4, 9);

    const assessment = compareEvidenceCaseAgainstCanonical(.scene_object_world_point, canonical, candidate);
    try std.testing.expectEqual(EvidenceAnchorKind.scene_object_world_point, assessment.evidence_case.anchor_kind);
    try std.testing.expectEqual(EvidenceAdmission.rejected_no_floor_truth, assessment.evidence_case.admission);
    try std.testing.expectEqual(@as(usize, 0), assessment.evidence_case.allowed_metrics.len);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.exact_status);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.occupied_coverage);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.nearest_occupied);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.nearest_standable);
    try std.testing.expectEqual(@as(u8, 0), assessment.comparison.better_metric_count);
    try std.testing.expectEqual(false, assessment.comparison.stronger_evidence_bar_passed);
    try std.testing.expectEqual(MappingEvidenceDisposition.diagnostic_candidate_only_not_better, assessment.comparison.disposition);
}

test "runtime world query ranks zones ahead of scene objects for the bounded extra-anchor investigation" {
    const room = try room_fixtures.guarded1919();

    const query = init(room);
    const investigation = query.investigateAdditionalEvidenceAnchor();

    try std.testing.expectEqual(EvidenceAnchorKind.zone_world_point, investigation.ranked_candidates[0].anchor_kind);
    try std.testing.expectEqual(AdditionalAnchorInvestigationPriority.primary, investigation.ranked_candidates[0].priority);
    try std.testing.expectEqual(@as(usize, 4), investigation.ranked_candidates[0].sample_count);
    try std.testing.expectEqual(@as(usize, 4), investigation.ranked_candidates[0].floor_aligned_sample_count);
    try std.testing.expectEqualStrings(
        "Zone bounds are the stronger current candidate because they stay in room-world coordinates and their Y extents remain floor-grid aligned, even though they still describe trigger volumes rather than floor points.",
        investigation.ranked_candidates[0].rationale,
    );

    try std.testing.expectEqual(EvidenceAnchorKind.scene_object_world_point, investigation.ranked_candidates[1].anchor_kind);
    try std.testing.expectEqual(AdditionalAnchorInvestigationPriority.secondary, investigation.ranked_candidates[1].priority);
    try std.testing.expectEqual(@as(usize, 1), investigation.ranked_candidates[1].sample_count);
    try std.testing.expectEqual(@as(usize, 0), investigation.ranked_candidates[1].floor_aligned_sample_count);
    try std.testing.expectEqualStrings(
        "Scene-object placements are weaker current evidence because the positioned non-origin samples are sparse and can sit off the 256-unit floor grid, so they do not presently read as reliable standable-floor anchors.",
        investigation.ranked_candidates[1].rationale,
    );

    try std.testing.expectEqual(EvidenceAnchorKind.zone_world_point, investigation.chosen_anchor_kind);
    try std.testing.expectEqual(EvidenceAdmission.rejected_no_floor_truth, investigation.chosen_evidence_case.admission);
    try std.testing.expectEqual(@as(usize, 0), investigation.chosen_evidence_case.allowed_metrics.len);
    try std.testing.expectEqualStrings(
        "Zone bounds stay rejected because the checked-in room snapshot only proves volumetric trigger regions; admitting a single point would require inventing an unsupported center, corner, or floor-projection policy.",
        investigation.decision_rationale,
    );
}

test "runtime world query keeps the investigated zone anchors out of mapping scores" {
    const canonical = testHeroStartCore(.mapped_cell_empty, 36, 64, 144);
    const candidate = testHeroStartCore(.surface_height_mismatch, 0, 4, 9);

    const assessment = compareEvidenceCaseAgainstCanonical(.zone_world_point, canonical, candidate);
    try std.testing.expectEqual(EvidenceAnchorKind.zone_world_point, assessment.evidence_case.anchor_kind);
    try std.testing.expectEqual(EvidenceAdmission.rejected_no_floor_truth, assessment.evidence_case.admission);
    try std.testing.expectEqual(@as(usize, 0), assessment.evidence_case.allowed_metrics.len);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.exact_status);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.occupied_coverage);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.nearest_occupied);
    try std.testing.expectEqual(EvidenceMetricComparison.equal, assessment.comparison.nearest_standable);
    try std.testing.expectEqual(@as(u8, 0), assessment.comparison.better_metric_count);
    try std.testing.expectEqual(@as(u8, 0), assessment.comparison.worse_metric_count);
    try std.testing.expectEqual(MappingEvidenceDisposition.diagnostic_candidate_only_not_better, assessment.comparison.disposition);
}

test "runtime world query keeps fragment anchors out of the current evidence basis" {
    const canonical = testHeroStartCore(.mapped_cell_empty, 36, 64, 144);
    const candidate = testHeroStartCore(.surface_height_mismatch, 0, 4, 9);

    const assessment = compareEvidenceCaseAgainstCanonical(.fragment_world_point, canonical, candidate);
    try std.testing.expectEqual(EvidenceAnchorKind.fragment_world_point, assessment.evidence_case.anchor_kind);
    try std.testing.expectEqual(EvidenceAdmission.rejected_out_of_scope_basis, assessment.evidence_case.admission);
    try std.testing.expectEqual(@as(usize, 0), assessment.evidence_case.allowed_metrics.len);
    try std.testing.expectEqual(MappingEvidenceDisposition.diagnostic_candidate_only_not_better, assessment.comparison.disposition);
}

test "runtime world query keeps unchecked evidence-room topology discovery outside the runtime boundary" {
    const guarded_policy = topologyRelationEvidencePolicy(.guarded_runtime_room_snapshot);
    try std.testing.expectEqual(
        TopologyRelationEvidenceAdmission.admitted_supported_runtime,
        guarded_policy.admission,
    );
    try std.testing.expectEqual(true, guarded_policy.allowsDiscovery());
    try std.testing.expectEqual(true, guarded_policy.allowsRuntimeSemantics());
    try std.testing.expectEqualStrings(
        "Guarded room snapshots remain the only supported basis for runtime-facing topology semantics.",
        guarded_policy.rationale,
    );

    const unchecked_policy = topologyRelationEvidencePolicy(.unchecked_evidence_room_snapshot);
    try std.testing.expectEqual(
        TopologyRelationEvidenceAdmission.admitted_discovery_only,
        unchecked_policy.admission,
    );
    try std.testing.expectEqual(true, unchecked_policy.allowsDiscovery());
    try std.testing.expectEqual(false, unchecked_policy.allowsRuntimeSemantics());
    try std.testing.expectEqualStrings(
        "Unchecked evidence-only room snapshots may inform discovery-only topology observation because they still decode immutable room geometry, but bypassing the guarded loader policy keeps them outside the supported runtime boundary and insufficient on their own for runtime-facing relation classes.",
        unchecked_policy.rationale,
    );
}

test "runtime world query ranks checked-in unchecked evidence rooms and finds no richer topology relation source" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const baseline_room = try room_fixtures.guarded1919();

    const baseline_query = init(baseline_room);
    const baseline_summary = try baseline_query.summarizeObservedNeighborPatterns(allocator);
    defer baseline_summary.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), baseline_summary.blocked_neighbor_count);
    try std.testing.expectEqual(@as(usize, 0), countNonFlatOccupiedNeighbors(baseline_summary));

    var candidates = [_]UncheckedEvidenceRoomCandidateScan{
        try scanUncheckedEvidenceRoomCandidate(allocator, resolved, 2, 2),
        try scanUncheckedEvidenceRoomCandidate(allocator, resolved, 44, 2),
        try scanUncheckedEvidenceRoomCandidate(allocator, resolved, 11, 10),
    };
    std.mem.sort(UncheckedEvidenceRoomCandidateScan, &candidates, {}, lessThanUncheckedEvidenceRoomCandidate);

    try std.testing.expectEqual(
        UncheckedEvidenceRoomCandidateStatus.ranked,
        candidates[0].status,
    );
    try std.testing.expectEqual(@as(usize, 11), candidates[0].scene_entry_index);
    try std.testing.expectEqual(@as(usize, 10), candidates[0].background_entry_index);

    try std.testing.expectEqual(
        UncheckedEvidenceRoomCandidateStatus.ranked,
        candidates[1].status,
    );
    try std.testing.expectEqual(@as(usize, 2), candidates[1].scene_entry_index);
    try std.testing.expectEqual(@as(usize, 2), candidates[1].background_entry_index);

    try std.testing.expectEqual(
        UncheckedEvidenceRoomCandidateStatus.excluded_not_interior,
        candidates[2].status,
    );
    try std.testing.expectEqual(@as(usize, 44), candidates[2].scene_entry_index);
    try std.testing.expectEqual(@as(usize, 2), candidates[2].background_entry_index);

    for (candidates[0..2]) |candidate| {
        try std.testing.expectEqual(@as(usize, 0), candidate.blocked_neighbor_count);
        try std.testing.expectEqual(@as(usize, 0), candidate.nonflat_occupied_neighbor_count);
        try std.testing.expectEqual(@as(usize, 1), candidate.top_y_delta_bucket_count);
        try std.testing.expectEqual(false, candidate.introduces_cases_beyond_baseline);
        try std.testing.expectEqual(false, candidate.qualifies_for_relation_followup);
    }

    try std.testing.expectEqual(@as(?usize, null), firstQualifiedCandidateIndex(candidates[0..]));
}

const UncheckedEvidenceRoomCandidateStatus = enum {
    ranked,
    excluded_not_interior,
};

const UncheckedEvidenceRoomCandidateScan = struct {
    scene_entry_index: usize,
    background_entry_index: usize,
    status: UncheckedEvidenceRoomCandidateStatus,
    blocked_neighbor_count: usize,
    nonflat_occupied_neighbor_count: usize,
    top_y_delta_bucket_count: usize,
    occupied_surface_count: usize,
    introduces_cases_beyond_baseline: bool,
    qualifies_for_relation_followup: bool,
};

fn scanUncheckedEvidenceRoomCandidate(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
) !UncheckedEvidenceRoomCandidateScan {
    const room = room_state.loadRoomSnapshotUncheckedForTests(
        allocator,
        resolved,
        scene_entry_index,
        background_entry_index,
    ) catch |err| switch (err) {
        error.ViewerSceneMustBeInterior => {
            return .{
                .scene_entry_index = scene_entry_index,
                .background_entry_index = background_entry_index,
                .status = .excluded_not_interior,
                .blocked_neighbor_count = 0,
                .nonflat_occupied_neighbor_count = 0,
                .top_y_delta_bucket_count = 0,
                .occupied_surface_count = 0,
                .introduces_cases_beyond_baseline = false,
                .qualifies_for_relation_followup = false,
            };
        },
        else => return err,
    };
    defer room.deinit(allocator);

    const query = init(&room);
    const summary = try query.summarizeObservedNeighborPatterns(allocator);
    defer summary.deinit(allocator);

    const nonflat_occupied_neighbor_count = countNonFlatOccupiedNeighbors(summary);
    const introduces_cases_beyond_baseline =
        summary.blocked_neighbor_count > 0 or nonflat_occupied_neighbor_count > 0;
    return .{
        .scene_entry_index = scene_entry_index,
        .background_entry_index = background_entry_index,
        .status = .ranked,
        .blocked_neighbor_count = summary.blocked_neighbor_count,
        .nonflat_occupied_neighbor_count = nonflat_occupied_neighbor_count,
        .top_y_delta_bucket_count = summary.top_y_delta_buckets.len,
        .occupied_surface_count = summary.occupied_surface_count,
        .introduces_cases_beyond_baseline = introduces_cases_beyond_baseline,
        .qualifies_for_relation_followup = introduces_cases_beyond_baseline,
    };
}

fn countNonFlatOccupiedNeighbors(summary: ObservedNeighborPatternSummary) usize {
    var count: usize = 0;
    for (summary.top_y_delta_buckets) |bucket| {
        if (bucket.delta != 0) count += bucket.count;
    }
    return count;
}

fn firstQualifiedCandidateIndex(candidates: []const UncheckedEvidenceRoomCandidateScan) ?usize {
    for (candidates, 0..) |candidate, index| {
        if (candidate.qualifies_for_relation_followup) return index;
    }
    return null;
}

fn lessThanUncheckedEvidenceRoomCandidate(
    _: void,
    left: UncheckedEvidenceRoomCandidateScan,
    right: UncheckedEvidenceRoomCandidateScan,
) bool {
    if (left.status != right.status) return left.status == .ranked;
    if (left.qualifies_for_relation_followup != right.qualifies_for_relation_followup) {
        return left.qualifies_for_relation_followup;
    }
    if (left.blocked_neighbor_count != right.blocked_neighbor_count) {
        return left.blocked_neighbor_count > right.blocked_neighbor_count;
    }
    if (left.nonflat_occupied_neighbor_count != right.nonflat_occupied_neighbor_count) {
        return left.nonflat_occupied_neighbor_count > right.nonflat_occupied_neighbor_count;
    }
    if (left.top_y_delta_bucket_count != right.top_y_delta_bucket_count) {
        return left.top_y_delta_bucket_count > right.top_y_delta_bucket_count;
    }
    if (left.occupied_surface_count != right.occupied_surface_count) {
        return left.occupied_surface_count > right.occupied_surface_count;
    }
    if (left.scene_entry_index != right.scene_entry_index) {
        return left.scene_entry_index < right.scene_entry_index;
    }
    return left.background_entry_index < right.background_entry_index;
}

fn testTopSurface() CellTopSurface {
    return .{
        .cell = .{ .x = 0, .z = 0 },
        .total_height = 1,
        .top_y = 256,
        .stack_depth = 1,
        .top_floor_type = 0,
        .top_shape = 0,
        .top_shape_class = .solid,
        .top_brick_index = 0,
    };
}

fn testHeroStartCore(
    exact_status: HeroStartExactStatus,
    x_cells_from_bounds: usize,
    nearest_occupied_distance_sq: i64,
    nearest_standable_distance_sq: i64,
) HeroStartEvaluationCore {
    return .{
        .raw_cell = .{
            .world_x = 1987,
            .world_z = 3743,
            .cell = .{ .x = 3, .z = 7 },
            .status = if (exact_status == .surface_height_mismatch or exact_status == .mapped_cell_blocked) .occupied_surface else .empty,
            .occupied = exact_status == .surface_height_mismatch or exact_status == .mapped_cell_blocked,
            .surface = if (exact_status == .surface_height_mismatch or exact_status == .mapped_cell_blocked) testTopSurface() else null,
            .standability = if (exact_status == .surface_height_mismatch) .standable else if (exact_status == .mapped_cell_blocked) .blocked else null,
        },
        .occupied_coverage = .{
            .relation = if (x_cells_from_bounds == 0) .within_occupied_bounds else .outside_occupied_bounds,
            .occupied_bounds = .{
                .min_x = 39,
                .max_x = 63,
                .min_z = 6,
                .max_z = 58,
            },
            .x_cells_from_bounds = x_cells_from_bounds,
            .z_cells_from_bounds = 0,
        },
        .exact_status = exact_status,
        .diagnostic_status = if (x_cells_from_bounds == 0) .exact_invalid_candidate_only else .exact_invalid_mapping_mismatch,
        .nearest_occupied = testDiagnosticCandidate(.occupied, nearest_occupied_distance_sq),
        .nearest_standable = testDiagnosticCandidate(.standable, nearest_standable_distance_sq),
    };
}

fn testDiagnosticCandidate(kind: DiagnosticCandidateKind, distance_sq: i64) DiagnosticCandidate {
    return .{
        .kind = kind,
        .cell = .{ .x = 0, .z = 0 },
        .world_bounds = .{
            .min_x = 0,
            .max_x = 0,
            .min_z = 0,
            .max_z = 0,
        },
        .surface = testTopSurface(),
        .standability = .standable,
        .x_distance = @intCast(distance_sq),
        .z_distance = 0,
        .distance_sq = distance_sq,
    };
}

fn expectedNeighborCell(bounds: GridBounds, origin: GridCell, direction: CardinalDirection) ?GridCell {
    return switch (direction) {
        .north => if (origin.z == 0) null else .{ .x = origin.x, .z = origin.z - 1 },
        .east => if (origin.x + 1 >= bounds.width) null else .{ .x = origin.x + 1, .z = origin.z },
        .south => if (origin.z + 1 >= bounds.depth) null else .{ .x = origin.x, .z = origin.z + 1 },
        .west => if (origin.x == 0) null else .{ .x = origin.x - 1, .z = origin.z },
    };
}
