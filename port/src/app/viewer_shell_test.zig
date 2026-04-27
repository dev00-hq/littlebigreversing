const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");
const room_state = @import("../runtime/room_state.zig");
const runtime_locomotion = @import("../runtime/locomotion.zig");
const runtime_object_behavior = @import("../runtime/object_behavior.zig");
const runtime_session_mod = @import("../runtime/session.zig");
const runtime_update = @import("../runtime/update.zig");
const runtime_query = @import("../runtime/world_query.zig");
const fragment_compare = @import("viewer/fragment_compare.zig");
const viewer_shell = @import("viewer_shell.zig");

fn initViewerSession(room: *const viewer_shell.RoomSnapshot) !viewer_shell.Session {
    return viewer_shell.initSession(std.testing.allocator, room);
}

fn expectMoveOptions(
    room: *const viewer_shell.RoomSnapshot,
    hero_position: viewer_shell.WorldPointSnapshot,
    move_options: viewer_shell.ViewerMoveOptions,
) !void {
    const query = runtime_query.init(room);
    const expected = try query.evaluateCardinalMoveOptions(hero_position);

    try std.testing.expectEqual(expected.origin.raw_cell.cell.?, move_options.current_cell);
    for (expected.options, 0..) |option, index| {
        try std.testing.expectEqual(option.direction, move_options.options[index].direction);
        try std.testing.expectEqual(option.evaluation.raw_cell.cell, move_options.options[index].target_cell);
        try std.testing.expectEqual(option.evaluation.status, move_options.options[index].status);
        try std.testing.expectEqual(option.evaluation.occupied_coverage, move_options.options[index].occupied_coverage);
    }
}

fn expectLocalTopology(
    room: *const viewer_shell.RoomSnapshot,
    current_cell: viewer_shell.GridCell,
    local_topology: viewer_shell.ViewerLocalNeighborTopology,
) !void {
    const query = runtime_query.init(room);
    const expected = try query.probeLocalNeighborTopology(current_cell.x, current_cell.z);

    try std.testing.expectEqual(expected.origin_surface, local_topology.origin_surface);
    try std.testing.expectEqual(expected.origin_standability, local_topology.origin_standability);
    for (expected.neighbors, 0..) |neighbor, index| {
        try std.testing.expectEqual(neighbor, local_topology.neighbors[index]);
    }
}

fn expectZoneIndices(
    membership: runtime_query.ContainingZoneSet,
    expected_indices: []const usize,
) !void {
    const zones = membership.slice();
    try std.testing.expectEqual(expected_indices.len, zones.len);
    for (zones, expected_indices) |zone, expected_index| {
        try std.testing.expectEqual(expected_index, zone.index);
    }
}

fn expectDisplayMoveOptionLines(
    display: viewer_shell.ViewerLocomotionStatusDisplay,
    line_index: usize,
    move_options: viewer_shell.ViewerMoveOptions,
) !void {
    var north_cell_buffer: [16]u8 = undefined;
    var east_cell_buffer: [16]u8 = undefined;
    var south_cell_buffer: [16]u8 = undefined;
    var west_cell_buffer: [16]u8 = undefined;
    var first_line_buffer: [96]u8 = undefined;
    const first_line = try std.fmt.bufPrint(
        &first_line_buffer,
        "N {s} {s} E {s} {s}",
        .{
            try formatDisplayTargetCellValue(&north_cell_buffer, move_options.options[0].target_cell),
            moveOptionStatusHudLabel(move_options.options[0].status),
            try formatDisplayTargetCellValue(&east_cell_buffer, move_options.options[1].target_cell),
            moveOptionStatusHudLabel(move_options.options[1].status),
        },
    );
    var second_line_buffer: [96]u8 = undefined;
    const second_line = try std.fmt.bufPrint(
        &second_line_buffer,
        "S {s} {s} W {s} {s}",
        .{
            try formatDisplayTargetCellValue(&south_cell_buffer, move_options.options[2].target_cell),
            moveOptionStatusHudLabel(move_options.options[2].status),
            try formatDisplayTargetCellValue(&west_cell_buffer, move_options.options[3].target_cell),
            moveOptionStatusHudLabel(move_options.options[3].status),
        },
    );

    try std.testing.expectEqualStrings(first_line, display.lines[line_index]);
    try std.testing.expectEqualStrings(second_line, display.lines[line_index + 1]);
}

fn expectNoSchematicCue(display: viewer_shell.ViewerLocomotionStatusDisplay) !void {
    switch (display.schematic) {
        .none => {},
        else => return error.UnexpectedViewerLocomotionSchematicCue,
    }
}

fn expectAdmittedPathSchematicCue(
    display: viewer_shell.ViewerLocomotionStatusDisplay,
    move_options: viewer_shell.ViewerMoveOptions,
) !void {
    switch (display.schematic) {
        .admitted_path => |value| {
            try std.testing.expectEqual(move_options.current_cell, value.current_cell);
            for (move_options.options, 0..) |move_option, index| {
                try std.testing.expectEqual(move_option.direction, value.move_options[index].direction);
                try std.testing.expectEqual(move_option.target_cell, value.move_options[index].target_cell);
                try std.testing.expectEqual(move_option.status, value.move_options[index].status);
            }
        },
        .none => return error.MissingViewerLocomotionSchematicCue,
    }
}

fn expectNoAttemptCue(display: viewer_shell.ViewerLocomotionStatusDisplay) !void {
    switch (display.attempt) {
        .none => {},
        else => return error.UnexpectedViewerLocomotionAttemptCue,
    }
}

fn formatRawInvalidStartMappingHintHudLine(
    buffer: []u8,
    hint: ?viewer_shell.ViewerRawInvalidStartMappingHint,
) ![]const u8 {
    const resolved = hint orelse return std.fmt.bufPrint(buffer, "ALT MAP NONE", .{});

    var hypothesis_buffer: [48]u8 = undefined;
    var cell_buffer: [16]u8 = undefined;
    var exact_buffer: [48]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "ALT MAP {s} CELL {s} {s}",
        .{
            upperTag(&hypothesis_buffer, @tagName(resolved.hypothesis)),
            try formatOptionalCellValue(&cell_buffer, resolved.raw_cell),
            upperTag(&exact_buffer, @tagName(resolved.exact_status)),
        },
    );
}

fn formatRawInvalidStartMappingHintDiagnosticValue(
    buffer: []u8,
    hint: ?viewer_shell.ViewerRawInvalidStartMappingHint,
) ![]const u8 {
    const resolved = hint orelse return std.fmt.bufPrint(buffer, "none", .{});

    var cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "{s}:{d}:{s}:{s}:{s}:{d}:{d}",
        .{
            @tagName(resolved.hypothesis),
            resolved.cell_span_xz,
            try formatOptionalCellValue(&cell_buffer, resolved.raw_cell),
            @tagName(resolved.exact_status),
            @tagName(resolved.disposition),
            resolved.better_metric_count,
            resolved.worse_metric_count,
        },
    );
}

fn expectAcceptedAttemptCue(
    display: viewer_shell.ViewerLocomotionStatusDisplay,
    direction: viewer_shell.CardinalDirection,
    origin_cell: viewer_shell.GridCell,
    destination_cell: viewer_shell.GridCell,
) !void {
    switch (display.attempt) {
        .accepted => |value| {
            try std.testing.expectEqual(direction, value.direction);
            try std.testing.expectEqual(origin_cell, value.origin_cell);
            try std.testing.expectEqual(destination_cell, value.destination_cell);
        },
        else => return error.MissingViewerLocomotionAttemptCue,
    }
}

fn expectRejectedAttemptCue(
    display: viewer_shell.ViewerLocomotionStatusDisplay,
    direction: viewer_shell.CardinalDirection,
    current_cell: viewer_shell.GridCell,
    target_cell: viewer_shell.GridCell,
) !void {
    switch (display.attempt) {
        .rejected => |value| {
            try std.testing.expectEqual(direction, value.direction);
            try std.testing.expectEqual(current_cell, value.current_cell);
            try std.testing.expectEqual(target_cell, value.target_cell);
        },
        else => return error.MissingViewerLocomotionAttemptCue,
    }
}

fn formatDiagnostic(
    allocator: std.mem.Allocator,
    status: viewer_shell.ViewerLocomotionStatus,
) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try viewer_shell.printLocomotionStatusDiagnostic(&output.writer, status);
    return output.toOwnedSlice();
}

fn formatOptionalCellValue(buffer: []u8, cell: ?viewer_shell.GridCell) ![]const u8 {
    if (cell) |resolved| return std.fmt.bufPrint(buffer, "{d}/{d}", .{ resolved.x, resolved.z });
    return "none";
}

fn formatRequiredCellValue(buffer: []u8, cell: viewer_shell.GridCell) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{d}/{d}", .{ cell.x, cell.z });
}

fn formatDisplayTargetCellValue(buffer: []u8, cell: ?viewer_shell.GridCell) ![]const u8 {
    if (cell) |resolved| return std.fmt.bufPrint(buffer, "{d}/{d}", .{ resolved.x, resolved.z });
    return "NONE";
}

fn steppedWorldPoint(
    origin_world_position: viewer_shell.WorldPointSnapshot,
    direction: viewer_shell.CardinalDirection,
) viewer_shell.WorldPointSnapshot {
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

fn expectNearestStandableSeed(room: *const viewer_shell.RoomSnapshot) !void {
    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(std.testing.allocator);
    const query = runtime_query.init(room);
    const probe = try query.probeHeroStart();
    const candidate = probe.nearest_standable orelse return error.MissingNearestStandableDiagnosticCandidate;
    const expected = runtime_query.gridCellCenterWorldPosition(
        candidate.cell.x,
        candidate.cell.z,
        candidate.surface.top_y,
    );

    const seeded = try viewer_shell.seedSessionToLocomotionFixture(room, &runtime_session);
    try std.testing.expectEqual(expected, seeded);
    try std.testing.expectEqual(expected, runtime_session.heroWorldPosition());

    const status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);
    switch (status) {
        .seeded_valid => |value| {
            try std.testing.expectEqual(candidate.cell, value.cell);
            try std.testing.expectEqual(expected, value.hero_position);
            try expectMoveOptions(room, expected, value.move_options);
            try expectLocalTopology(room, candidate.cell, value.local_topology);
        },
        else => return error.UnexpectedViewerLocomotionStatus,
    }
}

fn directionLabel(direction: viewer_shell.CardinalDirection) []const u8 {
    return switch (direction) {
        .north => "north",
        .east => "east",
        .south => "south",
        .west => "west",
    };
}

fn shortDirectionLabel(direction: viewer_shell.CardinalDirection) []const u8 {
    return switch (direction) {
        .north => "N",
        .east => "E",
        .south => "S",
        .west => "W",
    };
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

fn formatMoveOptionsDiagnosticValue(
    buffer: []u8,
    move_options: viewer_shell.ViewerMoveOptions,
) ![]const u8 {
    var cell_buffers: [4][16]u8 = undefined;
    var writer = std.Io.Writer.fixed(buffer);
    for (move_options.options, 0..) |option, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.print(
            "{s}:{s}:{s}:{s}:{d}:{d}",
            .{
                directionLabel(option.direction),
                try formatOptionalCellValue(&cell_buffers[index], option.target_cell),
                @tagName(option.status),
                @tagName(option.occupied_coverage.relation),
                option.occupied_coverage.x_cells_from_bounds,
                option.occupied_coverage.z_cells_from_bounds,
            },
        );
    }
    return writer.buffered();
}

fn formatZoneDiagnosticValue(
    buffer: []u8,
    zone_membership: runtime_query.ContainingZoneSet,
) []const u8 {
    const zones = zone_membership.slice();
    if (zones.len == 0) return "none";

    var writer = std.Io.Writer.fixed(buffer);
    for (zones, 0..) |zone, index| {
        if (index != 0) writer.writeAll("|") catch unreachable;
        writer.print("{d}", .{zone.index}) catch unreachable;
    }
    return writer.buffered();
}

fn formatRawInvalidStartCandidateHudLine(
    buffer: []u8,
    label: []const u8,
    candidate: ?viewer_shell.ViewerRawInvalidStartCandidate,
) ![]const u8 {
    const resolved = candidate orelse return std.fmt.bufPrint(buffer, "{s} NONE", .{label});

    var cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "{s} {s} DX {d} DZ {d} D2 {d}",
        .{
            label,
            try formatRequiredCellValue(&cell_buffer, resolved.cell),
            resolved.x_distance,
            resolved.z_distance,
            resolved.distance_sq,
        },
    );
}

fn formatRawInvalidStartCandidateDiagnosticValue(
    buffer: []u8,
    candidate: ?viewer_shell.ViewerRawInvalidStartCandidate,
) ![]const u8 {
    const resolved = candidate orelse return "none";

    var cell_buffer: [16]u8 = undefined;
    return std.fmt.bufPrint(
        buffer,
        "{s}:{d}:{d}:{d}",
        .{
            try formatRequiredCellValue(&cell_buffer, resolved.cell),
            resolved.x_distance,
            resolved.z_distance,
            resolved.distance_sq,
        },
    );
}

fn coverageHudRelationLabel(relation: runtime_query.OccupiedCoverageRelation) []const u8 {
    return switch (relation) {
        .unmapped_world_point => "UNMAPPED",
        .no_occupied_bounds => "NO_OCC",
        .within_occupied_bounds => "WITHIN",
        .outside_occupied_bounds => "OUTSIDE",
    };
}

fn formatCoverageHudLine(
    buffer: []u8,
    coverage: runtime_query.OccupiedCoverageProbe,
) ![]const u8 {
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
                coverageHudRelationLabel(coverage.relation),
            },
        );
    }

    return std.fmt.bufPrint(
        buffer,
        "BOUNDS NONE DX{d} DZ{d} {s}",
        .{
            coverage.x_cells_from_bounds,
            coverage.z_cells_from_bounds,
            coverageHudRelationLabel(coverage.relation),
        },
    );
}

fn formatOccupiedBoundsDiagnosticValue(
    buffer: []u8,
    coverage: runtime_query.OccupiedCoverageProbe,
) ![]const u8 {
    const bounds = coverage.occupied_bounds orelse return "none";
    return std.fmt.bufPrint(
        buffer,
        "{d}..{d}:{d}..{d}",
        .{ bounds.min_x, bounds.max_x, bounds.min_z, bounds.max_z },
    );
}

fn formatLocalTopologyHudLine(
    buffer: []u8,
    local_topology: viewer_shell.ViewerLocalNeighborTopology,
) ![]const u8 {
    var token_buffers: [4][16]u8 = undefined;
    var writer = std.Io.Writer.fixed(buffer);
    try writer.writeAll("TOPO ");
    for (local_topology.neighbors, 0..) |neighbor, index| {
        if (index != 0) try writer.writeAll(" ");
        try writer.print(
            "{s}:{s}",
            .{
                shortDirectionLabel(neighbor.direction),
                try localTopologyHudToken(&token_buffers[index], neighbor),
            },
        );
    }
    return writer.buffered();
}

fn formatLocalTopologyDiagnosticValue(
    buffer: []u8,
    local_topology: viewer_shell.ViewerLocalNeighborTopology,
) ![]const u8 {
    var cell_buffers: [4][16]u8 = undefined;
    var standability_buffers: [4][16]u8 = undefined;
    var delta_buffers: [4][16]u8 = undefined;
    var writer = std.Io.Writer.fixed(buffer);
    for (local_topology.neighbors, 0..) |neighbor, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.print(
            "{s}:{s}:{s}:{s}:{s}",
            .{
                directionLabel(neighbor.direction),
                try formatOptionalCellValue(&cell_buffers[index], neighbor.cell),
                @tagName(neighbor.status),
                formatOptionalStandability(&standability_buffers[index], neighbor.standability),
                try formatOptionalSignedDelta(&delta_buffers[index], neighbor.top_y_delta),
            },
        );
    }
    return writer.buffered();
}

fn formatCurrentFootingHudLine(
    buffer: []u8,
    local_topology: viewer_shell.ViewerLocalNeighborTopology,
) ![]const u8 {
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
    );
}

fn formatCurrentFootingDiagnosticValue(
    buffer: []u8,
    local_topology: viewer_shell.ViewerLocalNeighborTopology,
) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{s}:{d}:{d}:{d}:{d}:{s}",
        .{
            @tagName(local_topology.origin_standability),
            local_topology.origin_surface.top_y,
            local_topology.origin_surface.total_height,
            local_topology.origin_surface.stack_depth,
            local_topology.origin_surface.top_floor_type,
            @tagName(local_topology.origin_surface.top_shape_class),
        },
    );
}

fn upperTag(buffer: []u8, value: []const u8) []const u8 {
    const len = @min(buffer.len, value.len);
    for (value[0..len], 0..) |char, index| {
        buffer[index] = if (char >= 'a' and char <= 'z') char - 32 else char;
    }
    return buffer[0..len];
}

fn localTopologyHudToken(buffer: []u8, neighbor: runtime_query.CellNeighborProbe) ![]const u8 {
    if (neighbor.top_y_delta) |delta| return formatSignedDelta(buffer, delta);

    return switch (neighbor.status) {
        .out_of_bounds => "OOB",
        .empty => "EMPTY",
        .missing_top_surface => "NO_TOP",
        .occupied_surface => "OCC",
    };
}

fn formatOptionalStandability(buffer: []u8, standability: ?runtime_query.Standability) []const u8 {
    if (standability) |resolved| return std.fmt.bufPrint(buffer, "{s}", .{@tagName(resolved)}) catch unreachable;
    return "none";
}

fn formatOptionalSignedDelta(buffer: []u8, delta: ?i32) ![]const u8 {
    if (delta) |resolved| return formatSignedDelta(buffer, resolved);
    return "none";
}

fn formatSignedDelta(buffer: []u8, delta: i32) ![]const u8 {
    return if (delta >= 0)
        std.fmt.bufPrint(buffer, "+{d}", .{delta})
    else
        std.fmt.bufPrint(buffer, "{d}", .{delta});
}

test "viewer argument parsing requires explicit scene and background entries" {
    const parsed = try viewer_shell.parseArgs(std.testing.allocator, &.{
        "--scene-entry",
        "2",
        "--background-entry",
        "2",
        "--asset-root",
        "D:/assets",
    });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.scene_entry);
    try std.testing.expectEqual(@as(usize, 2), parsed.background_entry);
    try std.testing.expectEqualStrings("D:/assets", parsed.asset_root_override.?);
}

test "viewer window title carries the canonical room metadata" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    const title = try viewer_shell.formatWindowTitleZ(allocator, room);
    defer allocator.free(title);

    try std.testing.expect(std.mem.indexOf(u8, title, "scene=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "background=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "kind=interior") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "loader=17") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "hero=1987,512,3743") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "cube=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "gri=20(grm=2,bll=1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "grm=151") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "bll=180") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "fragments=0/0") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "blocks=73[1|2|3|4|5|7|...]") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "columns=64x64") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "comp=1246") != null);
}

test "viewer startup diagnostics include the guarded 19/19 neighbor pattern summary" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try room_fixtures.guarded1919();

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try viewer_shell.printStartupDiagnostics(&output.writer, allocator, resolved, room);

    const rendered = try output.toOwnedSlice();
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(
        u8,
        rendered,
        "event=neighbor_pattern_summary origin_cell_count=1246 occupied_surface_count=4828 empty_count=107 out_of_bounds_count=49 missing_top_surface_count=0 standable_neighbor_count=4828 blocked_neighbor_count=0 top_y_delta_buckets=0:4828\n",
    ) != null);
}

test "viewer locomotion harness consumes runtime-owned raw invalid 19/19 status without mutation" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);
    const raw_start = runtime_session.heroWorldPosition();
    const status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);
    const rejected_status = try runtime_locomotion.applyStep(room, &runtime_session, .south);

    switch (status) {
        .raw_invalid_start => |value| {
            try std.testing.expectEqual(runtime_query.HeroStartExactStatus.mapped_cell_empty, value.exact_status);
            try std.testing.expectEqual(runtime_query.HeroStartDiagnosticStatus.exact_invalid_mapping_mismatch, value.diagnostic_status);
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, .{ .x = 3, .z = 7 }), value.raw_cell);
            try std.testing.expectEqual(runtime_query.OccupiedCoverageRelation.outside_occupied_bounds, value.occupied_coverage.relation);
            try std.testing.expectEqual(@as(usize, 36), value.occupied_coverage.x_cells_from_bounds);
            try std.testing.expectEqual(@as(usize, 0), value.occupied_coverage.z_cells_from_bounds);
            try std.testing.expect(value.nearest_occupied != null);
            try std.testing.expect(value.nearest_standable != null);
            try std.testing.expectEqual(raw_start, value.hero_position);
        },
        else => return error.UnexpectedViewerLocomotionStatus,
    }
    const raw_value = switch (status) {
        .raw_invalid_start => |value| value,
        else => unreachable,
    };

    var status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const display = viewer_shell.formatLocomotionStatusDisplay(&status_buffer, status);
    try std.testing.expectEqual(@as(usize, 7), display.line_count);
    try std.testing.expectEqualStrings("RAW START INVALID", display.lines[0]);
    try std.testing.expectEqualStrings("CELL 3/7 MAPPED_CELL_EMPTY", display.lines[1]);
    try std.testing.expectEqualStrings("DIAG EXACT_INVALID_MAPPING_MISMATCH", display.lines[2]);
    var coverage_line_buffer: [80]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatCoverageHudLine(&coverage_line_buffer, raw_value.occupied_coverage),
        display.lines[3],
    );
    var nearest_occupied_line_buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatRawInvalidStartCandidateHudLine(&nearest_occupied_line_buffer, "NEAR OCC", raw_value.nearest_occupied),
        display.lines[4],
    );
    var nearest_standable_line_buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatRawInvalidStartCandidateHudLine(&nearest_standable_line_buffer, "NEAR STAND", raw_value.nearest_standable),
        display.lines[5],
    );
    var best_alt_mapping_line_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatRawInvalidStartMappingHintHudLine(&best_alt_mapping_line_buffer, raw_value.best_alt_mapping),
        display.lines[6],
    );
    try expectNoSchematicCue(display);
    try expectNoAttemptCue(display);

    const raw_diagnostic = try formatDiagnostic(allocator, status);
    defer allocator.free(raw_diagnostic);
    var occupied_bounds_buffer: [48]u8 = undefined;
    var nearest_occupied_buffer: [48]u8 = undefined;
    var nearest_standable_buffer: [48]u8 = undefined;
    var best_alt_mapping_buffer: [160]u8 = undefined;
    const expected_raw_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_status status=raw_invalid_start exact_status={s} diagnostic_status={s} raw_cell=3/7 occupied_coverage={s} occupied_bounds={s} occupied_bounds_dx={d} occupied_bounds_dz={d} nearest_occupied={s} nearest_standable={s} best_alt_mapping={s} move_options=unavailable hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            @tagName(raw_value.exact_status),
            @tagName(raw_value.diagnostic_status),
            @tagName(raw_value.occupied_coverage.relation),
            try formatOccupiedBoundsDiagnosticValue(&occupied_bounds_buffer, raw_value.occupied_coverage),
            raw_value.occupied_coverage.x_cells_from_bounds,
            raw_value.occupied_coverage.z_cells_from_bounds,
            try formatRawInvalidStartCandidateDiagnosticValue(&nearest_occupied_buffer, raw_value.nearest_occupied),
            try formatRawInvalidStartCandidateDiagnosticValue(&nearest_standable_buffer, raw_value.nearest_standable),
            try formatRawInvalidStartMappingHintDiagnosticValue(&best_alt_mapping_buffer, raw_value.best_alt_mapping),
            raw_value.hero_position.x,
            raw_value.hero_position.y,
            raw_value.hero_position.z,
        },
    );
    defer allocator.free(expected_raw_diagnostic);
    try std.testing.expectEqualStrings(expected_raw_diagnostic, raw_diagnostic);

    switch (rejected_status) {
        .last_move_rejected => |value| {
            try std.testing.expectEqual(viewer_shell.CardinalDirection.south, value.direction);
            try std.testing.expectEqual(viewer_shell.ViewerLocomotionRejectedStage.origin_invalid, value.rejection_stage);
            try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_empty, value.reason);
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, .{ .x = 3, .z = 7 }), value.current_cell);
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, .{ .x = 3, .z = 7 }), value.target_cell);
            try std.testing.expectEqual(@as(?runtime_query.OccupiedCoverageProbe, null), value.target_occupied_coverage);
            try std.testing.expectEqual(@as(?viewer_shell.ViewerMoveOptions, null), value.move_options);
            try std.testing.expectEqual(@as(?viewer_shell.ViewerLocalNeighborTopology, null), value.local_topology);
            try std.testing.expectEqual(raw_start, value.hero_position);
        },
        else => return error.UnexpectedViewerLocomotionStatus,
    }
    const origin_rejected_value = switch (rejected_status) {
        .last_move_rejected => |value| value,
        else => unreachable,
    };

    const rejected_diagnostic = try formatDiagnostic(allocator, rejected_status);
    defer allocator.free(rejected_diagnostic);
    const expected_origin_rejected_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_move direction={s} status=rejected rejection_stage={s} reason={s} current_cell=3/7 target_cell=3/7 move_options=unavailable hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            @tagName(origin_rejected_value.direction),
            @tagName(origin_rejected_value.rejection_stage),
            @tagName(origin_rejected_value.reason),
            origin_rejected_value.hero_position.x,
            origin_rejected_value.hero_position.y,
            origin_rejected_value.hero_position.z,
        },
    );
    defer allocator.free(expected_origin_rejected_diagnostic);
    try std.testing.expectEqualStrings(expected_origin_rejected_diagnostic, rejected_diagnostic);
    const rejected_display = viewer_shell.formatLocomotionStatusDisplay(&status_buffer, rejected_status);
    try expectNoSchematicCue(rejected_display);
    try expectNoAttemptCue(rejected_display);

    try std.testing.expectEqual(raw_start, runtime_session.heroWorldPosition());
}

test "viewer locomotion harness consumes runtime-owned seeded 19/19 fixture status" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);
    const seeded = try viewer_shell.seedSessionToLocomotionFixture(room, &runtime_session);
    const query = runtime_query.init(room);
    const seeded_eval = query.evaluateHeroMoveTarget(seeded);
    const status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);

    try std.testing.expectEqual(seeded, runtime_session.heroWorldPosition());
    try std.testing.expectEqual(runtime_query.MoveTargetStatus.allowed, seeded_eval.status);
    try std.testing.expectEqual(@as(?viewer_shell.GridCell, viewer_shell.locomotion_fixture_cell), seeded_eval.raw_cell.cell);
    try std.testing.expect(runtime_session.heroWorldPosition().x != room.scene.hero_start.x);
    try std.testing.expect(runtime_session.heroWorldPosition().z != room.scene.hero_start.z);
    switch (status) {
        .seeded_valid => |value| {
            try std.testing.expectEqual(viewer_shell.locomotion_fixture_cell, value.cell);
            try expectMoveOptions(room, seeded, value.move_options);
            try expectLocalTopology(room, viewer_shell.locomotion_fixture_cell, value.local_topology);
            try std.testing.expectEqual(seeded, value.hero_position);
        },
        else => return error.UnexpectedViewerLocomotionStatus,
    }
    const seeded_value = switch (status) {
        .seeded_valid => |value| value,
        else => unreachable,
    };

    var status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const display = viewer_shell.formatLocomotionStatusDisplay(&status_buffer, status);
    try std.testing.expectEqual(@as(usize, 7), display.line_count);
    try std.testing.expectEqualStrings("FIXTURE SEEDED VALID", display.lines[0]);
    try std.testing.expectEqualStrings("CELL 39/6 STATUS ALLOWED", display.lines[1]);
    try expectDisplayMoveOptionLines(display, 2, seeded_value.move_options);
    try std.testing.expectEqualStrings("ZONES NONE", display.lines[4]);
    var seeded_topology_line_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatLocalTopologyHudLine(&seeded_topology_line_buffer, seeded_value.local_topology),
        display.lines[5],
    );
    var seeded_footing_line_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatCurrentFootingHudLine(&seeded_footing_line_buffer, seeded_value.local_topology),
        display.lines[6],
    );
    try expectAdmittedPathSchematicCue(display, seeded_value.move_options);
    try expectNoAttemptCue(display);

    const diagnostic = try formatDiagnostic(allocator, status);
    defer allocator.free(diagnostic);
    var seeded_move_options_buffer: [256]u8 = undefined;
    var seeded_topology_buffer: [384]u8 = undefined;
    var seeded_footing_buffer: [128]u8 = undefined;
    var seeded_cell_buffer: [16]u8 = undefined;
    var seeded_zone_buffer: [128]u8 = undefined;
    const expected_seeded_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_seed status=seeded_valid cell={s} move_options={s} local_topology={s} current_footing={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatRequiredCellValue(&seeded_cell_buffer, seeded_value.cell),
            try formatMoveOptionsDiagnosticValue(&seeded_move_options_buffer, seeded_value.move_options),
            try formatLocalTopologyDiagnosticValue(&seeded_topology_buffer, seeded_value.local_topology),
            try formatCurrentFootingDiagnosticValue(&seeded_footing_buffer, seeded_value.local_topology),
            formatZoneDiagnosticValue(&seeded_zone_buffer, seeded_value.zone_membership),
            seeded_value.hero_position.x,
            seeded_value.hero_position.y,
            seeded_value.hero_position.z,
        },
    );
    defer allocator.free(expected_seeded_diagnostic);
    try std.testing.expectEqualStrings(expected_seeded_diagnostic, diagnostic);
}

test "viewer locomotion harness consumes runtime-owned 2/2 raw-zone recovery acceptance" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded22();

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);
    const raw_start = runtime_session.heroWorldPosition();
    const moved_status = try runtime_locomotion.applyStep(room, &runtime_session, .east);

    switch (moved_status) {
        .last_zone_recovery_accepted => |value| {
            try std.testing.expectEqual(viewer_shell.CardinalDirection.east, value.direction);
            try std.testing.expectEqual(
                raw_start.x + runtime_locomotion.raw_invalid_zone_entry_step_xz,
                value.hero_position.x,
            );
            try std.testing.expectEqual(raw_start.y, value.hero_position.y);
            try std.testing.expectEqual(raw_start.z, value.hero_position.z);
            try std.testing.expectEqual(runtime_session.heroWorldPosition(), value.hero_position);
            try expectZoneIndices(value.zone_membership, &.{0});
        },
        else => return error.UnexpectedViewerLocomotionStatus,
    }
    const moved_value = switch (moved_status) {
        .last_zone_recovery_accepted => |value| value,
        else => unreachable,
    };

    var status_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const display = viewer_shell.formatLocomotionStatusDisplay(&status_buffer, moved_status);
    try std.testing.expectEqual(@as(usize, 3), display.line_count);
    try std.testing.expectEqualStrings("RAW MOVE EAST ACCEPTED", display.lines[0]);
    try std.testing.expectEqualStrings("ZONES 0", display.lines[1]);
    try std.testing.expectEqualStrings("RAW START ZONE RECOVERY", display.lines[2]);
    try expectNoSchematicCue(display);
    try expectNoAttemptCue(display);

    const diagnostic = try formatDiagnostic(allocator, moved_status);
    defer allocator.free(diagnostic);
    var zones_buffer: [128]u8 = undefined;
    const expected_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_move direction={s} status=accepted_raw_zone_recovery recovery_step_xz={d} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            "east",
            runtime_locomotion.raw_invalid_zone_entry_step_xz,
            formatZoneDiagnosticValue(&zones_buffer, moved_value.zone_membership),
            moved_value.hero_position.x,
            moved_value.hero_position.y,
            moved_value.hero_position.z,
        },
    );
    defer allocator.free(expected_diagnostic);
    try std.testing.expectEqualStrings(expected_diagnostic, diagnostic);
}

test "viewer locomotion harness consumes runtime-owned accepted and rejected seeded steps" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);
    const seeded = try viewer_shell.seedSessionToLocomotionFixture(room, &runtime_session);

    const moved_status = try runtime_locomotion.applyStep(room, &runtime_session, .south);
    try std.testing.expect(runtime_session.heroWorldPosition().z > seeded.z);
    switch (moved_status) {
        .last_move_accepted => |value| {
            try std.testing.expectEqual(viewer_shell.CardinalDirection.south, value.direction);
            try std.testing.expectEqual(viewer_shell.locomotion_fixture_cell, value.origin_cell);
            try std.testing.expectEqual(viewer_shell.GridCell{ .x = 39, .z = 7 }, value.cell);
            try expectMoveOptions(room, runtime_session.heroWorldPosition(), value.move_options);
            try expectLocalTopology(room, value.cell, value.local_topology);
            try std.testing.expectEqual(runtime_session.heroWorldPosition(), value.hero_position);
        },
        else => return error.UnexpectedViewerLocomotionStatus,
    }
    const moved_value = switch (moved_status) {
        .last_move_accepted => |value| value,
        else => unreachable,
    };

    var moved_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const moved_display = viewer_shell.formatLocomotionStatusDisplay(&moved_buffer, moved_status);
    try std.testing.expectEqual(@as(usize, 7), moved_display.line_count);
    try std.testing.expectEqualStrings("MOVE SOUTH ACCEPTED", moved_display.lines[0]);
    try std.testing.expectEqualStrings("CELL 39/7 STATUS ALLOWED", moved_display.lines[1]);
    try expectDisplayMoveOptionLines(moved_display, 2, moved_value.move_options);
    try std.testing.expectEqualStrings("ZONES NONE", moved_display.lines[4]);
    var moved_topology_line_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatLocalTopologyHudLine(&moved_topology_line_buffer, moved_value.local_topology),
        moved_display.lines[5],
    );
    var moved_footing_line_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatCurrentFootingHudLine(&moved_footing_line_buffer, moved_value.local_topology),
        moved_display.lines[6],
    );
    try expectAdmittedPathSchematicCue(moved_display, moved_value.move_options);
    try expectAcceptedAttemptCue(
        moved_display,
        viewer_shell.CardinalDirection.south,
        viewer_shell.locomotion_fixture_cell,
        viewer_shell.GridCell{ .x = 39, .z = 7 },
    );

    const moved_diagnostic = try formatDiagnostic(allocator, moved_status);
    defer allocator.free(moved_diagnostic);
    var moved_move_options_buffer: [256]u8 = undefined;
    var moved_topology_buffer: [384]u8 = undefined;
    var moved_footing_buffer: [128]u8 = undefined;
    var moved_cell_buffer: [16]u8 = undefined;
    var moved_zone_buffer: [128]u8 = undefined;
    const expected_moved_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_move direction=south status=accepted cell={s} move_options={s} local_topology={s} current_footing={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatRequiredCellValue(&moved_cell_buffer, moved_value.cell),
            try formatMoveOptionsDiagnosticValue(&moved_move_options_buffer, moved_value.move_options),
            try formatLocalTopologyDiagnosticValue(&moved_topology_buffer, moved_value.local_topology),
            try formatCurrentFootingDiagnosticValue(&moved_footing_buffer, moved_value.local_topology),
            formatZoneDiagnosticValue(&moved_zone_buffer, moved_value.zone_membership),
            moved_value.hero_position.x,
            moved_value.hero_position.y,
            moved_value.hero_position.z,
        },
    );
    defer allocator.free(expected_moved_diagnostic);
    try std.testing.expectEqualStrings(expected_moved_diagnostic, moved_diagnostic);

    runtime_session.setHeroWorldPosition(seeded);
    const before_reject = runtime_session.heroWorldPosition();
    const rejected_status = try runtime_locomotion.applyStep(room, &runtime_session, .west);
    const query = runtime_query.init(room);
    const expected_target = query.evaluateHeroMoveTarget(steppedWorldPoint(before_reject, .west));
    try std.testing.expectEqual(before_reject, runtime_session.heroWorldPosition());
    switch (rejected_status) {
        .last_move_rejected => |value| {
            try std.testing.expectEqual(viewer_shell.CardinalDirection.west, value.direction);
            try std.testing.expectEqual(viewer_shell.ViewerLocomotionRejectedStage.target_rejected, value.rejection_stage);
            try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_empty, value.reason);
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, viewer_shell.locomotion_fixture_cell), value.current_cell);
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, .{ .x = 38, .z = 6 }), value.target_cell);
            try std.testing.expectEqual(expected_target.occupied_coverage, value.target_occupied_coverage orelse return error.MissingTargetOccupiedCoverage);
            try std.testing.expect(value.move_options != null);
            try std.testing.expect(value.local_topology != null);
            try expectMoveOptions(room, before_reject, value.move_options.?);
            try expectLocalTopology(room, viewer_shell.locomotion_fixture_cell, value.local_topology.?);
            try std.testing.expectEqual(before_reject, value.hero_position);
        },
        else => return error.UnexpectedViewerLocomotionStatus,
    }
    const rejected_value = switch (rejected_status) {
        .last_move_rejected => |value| value,
        else => unreachable,
    };

    var rejected_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const rejected_display = viewer_shell.formatLocomotionStatusDisplay(&rejected_buffer, rejected_status);
    try std.testing.expectEqual(@as(usize, 7), rejected_display.line_count);
    try std.testing.expectEqualStrings("MOVE WEST REJECTED", rejected_display.lines[0]);
    try std.testing.expectEqualStrings("STAY 39/6 TARGET_EMPTY", rejected_display.lines[1]);
    try expectDisplayMoveOptionLines(rejected_display, 2, rejected_value.move_options.?);
    try std.testing.expectEqualStrings("ZONES NONE", rejected_display.lines[4]);
    var rejected_topology_line_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatLocalTopologyHudLine(&rejected_topology_line_buffer, rejected_value.local_topology.?),
        rejected_display.lines[5],
    );
    var rejected_footing_line_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatCurrentFootingHudLine(&rejected_footing_line_buffer, rejected_value.local_topology.?),
        rejected_display.lines[6],
    );
    try expectAdmittedPathSchematicCue(rejected_display, rejected_value.move_options.?);
    try expectRejectedAttemptCue(
        rejected_display,
        viewer_shell.CardinalDirection.west,
        viewer_shell.locomotion_fixture_cell,
        viewer_shell.GridCell{ .x = 38, .z = 6 },
    );

    const rejected_diagnostic = try formatDiagnostic(allocator, rejected_status);
    defer allocator.free(rejected_diagnostic);
    var rejected_current_cell_buffer: [16]u8 = undefined;
    var rejected_target_cell_buffer: [16]u8 = undefined;
    var rejected_target_occupied_bounds_buffer: [32]u8 = undefined;
    var rejected_move_options_buffer: [256]u8 = undefined;
    var rejected_topology_buffer: [384]u8 = undefined;
    var rejected_footing_buffer: [128]u8 = undefined;
    var rejected_zone_buffer: [128]u8 = undefined;
    const expected_rejected_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_move direction=west status=rejected rejection_stage=target_rejected reason=target_empty current_cell={s} target_cell={s} target_occupied_coverage={s} target_occupied_bounds={s} target_occupied_bounds_dx={d} target_occupied_bounds_dz={d} move_options={s} local_topology={s} current_footing={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatOptionalCellValue(&rejected_current_cell_buffer, rejected_value.current_cell),
            try formatOptionalCellValue(&rejected_target_cell_buffer, rejected_value.target_cell),
            @tagName(rejected_value.target_occupied_coverage.?.relation),
            try formatOccupiedBoundsDiagnosticValue(&rejected_target_occupied_bounds_buffer, rejected_value.target_occupied_coverage.?),
            rejected_value.target_occupied_coverage.?.x_cells_from_bounds,
            rejected_value.target_occupied_coverage.?.z_cells_from_bounds,
            try formatMoveOptionsDiagnosticValue(&rejected_move_options_buffer, rejected_value.move_options.?),
            try formatLocalTopologyDiagnosticValue(&rejected_topology_buffer, rejected_value.local_topology.?),
            try formatCurrentFootingDiagnosticValue(&rejected_footing_buffer, rejected_value.local_topology.?),
            formatZoneDiagnosticValue(&rejected_zone_buffer, rejected_value.zone_membership),
            rejected_value.hero_position.x,
            rejected_value.hero_position.y,
            rejected_value.hero_position.z,
        },
    );
    defer allocator.free(expected_rejected_diagnostic);
    try std.testing.expectEqualStrings(expected_rejected_diagnostic, rejected_diagnostic);
}

test "viewer rejected move display tolerates out-of-bounds targets" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var runtime_session = try initViewerSession(&room);
    defer runtime_session.deinit(allocator);

    const query = runtime_query.init(&room);
    const west_edge_cell = viewer_shell.GridCell{ .x = 0, .z = 20 };
    const west_edge_surface = try query.cellTopSurface(west_edge_cell.x, west_edge_cell.z);
    runtime_session.setHeroWorldPosition(runtime_query.gridCellCenterWorldPosition(
        west_edge_cell.x,
        west_edge_cell.z,
        west_edge_surface.top_y,
    ));

    const rejected_status = try runtime_locomotion.applyStep(&room, &runtime_session, .west);
    const rejected_value = switch (rejected_status) {
        .last_move_rejected => |value| value,
        else => return error.UnexpectedViewerLocomotionStatus,
    };
    try std.testing.expectEqual(viewer_shell.CardinalDirection.west, rejected_value.direction);
    try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_out_of_bounds, rejected_value.reason);
    try std.testing.expectEqual(@as(?viewer_shell.GridCell, west_edge_cell), rejected_value.current_cell);
    try std.testing.expectEqual(@as(?viewer_shell.GridCell, null), rejected_value.target_cell);
    try std.testing.expect(rejected_value.move_options != null);

    var rejected_buffer: viewer_shell.ViewerLocomotionStatusDisplayBuffer = .{};
    const rejected_display = viewer_shell.formatLocomotionStatusDisplay(&rejected_buffer, rejected_status);
    try std.testing.expectEqual(@as(usize, 7), rejected_display.line_count);
    try std.testing.expectEqualStrings("MOVE WEST REJECTED", rejected_display.lines[0]);
    try std.testing.expectEqualStrings("STAY 0/20 TARGET_OUT_OF_BOUNDS", rejected_display.lines[1]);
    try expectDisplayMoveOptionLines(rejected_display, 2, rejected_value.move_options.?);
    try expectAdmittedPathSchematicCue(rejected_display, rejected_value.move_options.?);
    try expectNoAttemptCue(rejected_display);
}

test "viewer locomotion fixture seeding widens to guarded-positive rooms beyond 19/19" {
    try expectNearestStandableSeed(try room_fixtures.guarded22());
    try expectNearestStandableSeed(try room_fixtures.guarded1110());
    try expectNearestStandableSeed(try room_fixtures.guarded187187());
}

test "viewer render snapshots prefer runtime-owned object positions over immutable room positions" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();
    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);

    const original_object = runtime_session.objectSnapshotByIndex(2) orelse return error.MissingSessionObjectState;
    try std.testing.expectEqual(room.scene.objects[1], original_object);

    try runtime_session.setObjectWorldPosition(2, .{
        .x = original_object.x + 512,
        .y = original_object.y,
        .z = original_object.z + 512,
    });

    const snapshot = viewer_shell.buildRenderSnapshot(room, runtime_session);
    const moved_object = snapshot.objects[1];
    try std.testing.expectEqual(@as(usize, room.scene.objects.len), snapshot.objects.len);
    try std.testing.expectEqual(@as(usize, 2), moved_object.index);
    try std.testing.expectEqual(@as(i32, 3600), moved_object.x);
    try std.testing.expectEqual(@as(i32, 1248), moved_object.y);
    try std.testing.expectEqual(@as(i32, 2000), moved_object.z);
    try std.testing.expectEqual(@as(i32, 3088), room.scene.objects[1].x);
    try std.testing.expectEqual(@as(i32, 1248), room.scene.objects[1].y);
    try std.testing.expectEqual(@as(i32, 1488), room.scene.objects[1].z);
}

test "viewer key handling keeps fragment-room arrows on fragment navigation until locomotion is requested" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1110();
    var snapshot_session = try initViewerSession(room);
    defer snapshot_session.deinit(allocator);
    const snapshot = viewer_shell.buildRenderSnapshot(room, snapshot_session);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);
    const raw_start = runtime_session.heroWorldPosition();
    const locomotion_status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);
    const interaction = viewer_shell.initialInteractionState(catalog);
    const initial_focus = interaction.fragment_selection.focus orelse return error.MissingInitialFragmentFocus;

    try std.testing.expectEqual(viewer_shell.ViewerControlMode.fragment_navigation, interaction.control_mode);
    try std.testing.expectEqual(viewer_shell.ViewerSidebarTab.info, interaction.sidebar_tab);
    try std.testing.expectEqual(viewer_shell.ViewerZoomLevel.fit, interaction.zoom_level);
    try std.testing.expectEqual(viewer_shell.ViewerViewMode.isometric, interaction.view_mode);

    const nav_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        interaction,
        locomotion_status,
        .right,
    );
    try std.testing.expectEqual(viewer_shell.ViewerControlMode.fragment_navigation, nav_result.interaction.control_mode);
    try std.testing.expect(!nav_result.should_print_locomotion_diagnostic);
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, nav_result.post_key_action);
    try std.testing.expect(std.meta.eql(locomotion_status, nav_result.locomotion_status));
    try std.testing.expectEqual(raw_start, runtime_session.heroWorldPosition());
    try std.testing.expectEqual(@as(?runtime_locomotion.HeroIntent, null), runtime_session.pendingHeroIntent());
    try std.testing.expect(nav_result.interaction.fragment_selection.focus != null);
    try std.testing.expect(!std.meta.eql(initial_focus, nav_result.interaction.fragment_selection.focus.?));

    const toggle_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        interaction,
        locomotion_status,
        .tab,
    );
    try std.testing.expectEqual(viewer_shell.ViewerControlMode.locomotion, toggle_result.interaction.control_mode);
    try std.testing.expect(!toggle_result.should_print_locomotion_diagnostic);
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, toggle_result.post_key_action);
    try std.testing.expect(std.meta.eql(interaction.fragment_selection, toggle_result.interaction.fragment_selection));
    try std.testing.expectEqual(raw_start, runtime_session.heroWorldPosition());
    try std.testing.expectEqual(@as(?runtime_locomotion.HeroIntent, null), runtime_session.pendingHeroIntent());

    const sidebar_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        toggle_result.interaction,
        locomotion_status,
        .c,
    );
    try std.testing.expectEqual(viewer_shell.ViewerControlMode.locomotion, sidebar_result.interaction.control_mode);
    try std.testing.expectEqual(viewer_shell.ViewerSidebarTab.controls, sidebar_result.interaction.sidebar_tab);
    try std.testing.expectEqual(viewer_shell.ViewerZoomLevel.fit, sidebar_result.interaction.zoom_level);
    try std.testing.expectEqual(viewer_shell.ViewerViewMode.isometric, sidebar_result.interaction.view_mode);
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, sidebar_result.post_key_action);
    try std.testing.expect(std.meta.eql(toggle_result.interaction.fragment_selection, sidebar_result.interaction.fragment_selection));
    try std.testing.expectEqual(@as(?runtime_locomotion.HeroIntent, null), runtime_session.pendingHeroIntent());

    const view_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        sidebar_result.interaction,
        locomotion_status,
        .v,
    );
    try std.testing.expectEqual(viewer_shell.ViewerViewMode.grid, view_result.interaction.view_mode);
    try std.testing.expectEqual(viewer_shell.ViewerZoomLevel.fit, view_result.interaction.zoom_level);
    try std.testing.expectEqual(viewer_shell.ViewerSidebarTab.controls, view_result.interaction.sidebar_tab);
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, view_result.post_key_action);
    try std.testing.expectEqual(@as(?runtime_locomotion.HeroIntent, null), runtime_session.pendingHeroIntent());

    const zoom_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        view_result.interaction,
        locomotion_status,
        .zoom_in,
    );
    try std.testing.expectEqual(viewer_shell.ViewerZoomLevel.room, zoom_result.interaction.zoom_level);
    try std.testing.expectEqual(viewer_shell.ViewerViewMode.grid, zoom_result.interaction.view_mode);
    try std.testing.expectEqual(viewer_shell.ViewerSidebarTab.controls, zoom_result.interaction.sidebar_tab);
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, zoom_result.post_key_action);
    try std.testing.expectEqual(@as(?runtime_locomotion.HeroIntent, null), runtime_session.pendingHeroIntent());

    const reset_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        zoom_result.interaction,
        locomotion_status,
        .zoom_reset,
    );
    try std.testing.expectEqual(viewer_shell.ViewerZoomLevel.fit, reset_result.interaction.zoom_level);
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, reset_result.post_key_action);
}

test "viewer key handling seeds fragment rooms and leaves movement intent queued for the scheduler tick" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1110();
    var snapshot_session = try initViewerSession(room);
    defer snapshot_session.deinit(allocator);
    const snapshot = viewer_shell.buildRenderSnapshot(room, snapshot_session);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);
    const initial_status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);
    const initial_interaction = viewer_shell.initialInteractionState(catalog);

    const seed_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        initial_interaction,
        initial_status,
        .enter,
    );
    try std.testing.expectEqual(viewer_shell.ViewerControlMode.locomotion, seed_result.interaction.control_mode);
    try std.testing.expect(seed_result.should_print_locomotion_diagnostic);
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, seed_result.post_key_action);
    switch (seed_result.locomotion_status) {
        .seeded_valid => |value| {
            try std.testing.expectEqual(runtime_session.heroWorldPosition(), value.hero_position);
        },
        else => return error.UnexpectedViewerLocomotionStatus,
    }

    const seeded_fragment_selection = seed_result.interaction.fragment_selection;
    const seeded_position = runtime_session.heroWorldPosition();
    const move_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        seed_result.interaction,
        seed_result.locomotion_status,
        .right,
    );
    try std.testing.expectEqual(viewer_shell.ViewerControlMode.locomotion, move_result.interaction.control_mode);
    try std.testing.expect(!move_result.should_print_locomotion_diagnostic);
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, move_result.post_key_action);
    try std.testing.expect(std.meta.eql(seeded_fragment_selection, move_result.interaction.fragment_selection));
    try std.testing.expectEqual(seeded_position, runtime_session.heroWorldPosition());
    try std.testing.expectEqual(seed_result.locomotion_status, move_result.locomotion_status);
    try std.testing.expectEqual(@as(usize, 0), runtime_session.frame_index);
    try std.testing.expectEqual(
        runtime_locomotion.HeroIntent{ .move_cardinal = .east },
        runtime_session.pendingHeroIntent().?,
    );
    try std.testing.expectError(
        error.PendingHeroIntentAlreadySet,
        viewer_shell.handleKeyDown(
            room,
            &runtime_session,
            catalog,
            move_result.interaction,
            move_result.locomotion_status,
            .down,
        ),
    );

    const tick_result = try runtime_update.tick(room, &runtime_session);
    try std.testing.expectEqual(@as(?runtime_locomotion.HeroIntent, null), runtime_session.pendingHeroIntent());
    try std.testing.expect(tick_result.consumed_hero_intent);
    try std.testing.expectEqual(@as(usize, 1), runtime_session.frame_index);
    switch (tick_result.locomotion_status) {
        .last_move_accepted, .last_move_rejected => {},
        else => return error.UnexpectedViewerLocomotionStatus,
    }
}

test "viewer key handling routes Sendell room story input through queued runtime intents" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded3636();
    var snapshot_session = try initViewerSession(room);
    defer snapshot_session.deinit(allocator);
    const snapshot = viewer_shell.buildRenderSnapshot(room, snapshot_session);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);
    const initial_status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);
    const interaction = viewer_shell.initialInteractionState(catalog);

    const cast_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        interaction,
        initial_status,
        .f,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, cast_result.post_key_action);
    try std.testing.expectEqual(@as(usize, 0), runtime_session.frame_index);
    try std.testing.expectEqual(runtime_locomotion.HeroIntent.cast_lightning, runtime_session.pendingHeroIntent().?);

    const cast_tick = try runtime_update.tick(room, &runtime_session);
    try std.testing.expectEqual(@as(u8, 3), runtime_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 60), runtime_session.magicPoint());
    try std.testing.expectEqual(@as(?i16, 3), runtime_session.currentDialogId());
    const first_slice = runtime_object_behavior.currentSendellDialogSlice(runtime_session).?;
    try std.testing.expectEqual(@as(u8, 1), first_slice.page_number);
    try std.testing.expectEqualStrings(
        "You just found Sendell's Ball. Now you have reached a new level of magic: Red Ball. It will also enable ",
        first_slice.visible_text,
    );

    const advance_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        interaction,
        cast_tick.locomotion_status,
        .enter,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, advance_result.post_key_action);
    try std.testing.expectEqual(@as(usize, 1), runtime_session.frame_index);
    try std.testing.expectEqual(runtime_locomotion.HeroIntent.advance_story, runtime_session.pendingHeroIntent().?);

    _ = try runtime_update.tick(room, &runtime_session);
    try std.testing.expectEqual(@as(u8, 3), runtime_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 60), runtime_session.magicPoint());
    try std.testing.expectEqual(@as(?i16, 3), runtime_session.currentDialogId());
    const second_slice = runtime_object_behavior.currentSendellDialogSlice(runtime_session).?;
    try std.testing.expectEqual(@as(u8, 2), second_slice.page_number);
    try std.testing.expectEqualStrings("Sendell to contact you in case of danger.", second_slice.visible_text);
}

test "viewer key handling routes 0013 default action through queued runtime intent" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var snapshot_session = try initViewerSession(&room);
    defer snapshot_session.deinit(allocator);
    const snapshot = viewer_shell.buildRenderSnapshot(&room, snapshot_session);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    var runtime_session = try initViewerSession(&room);
    defer runtime_session.deinit(allocator);
    runtime_session.setHeroWorldPosition(.{ .x = 1280, .y = 2048, .z = 5376 });
    const initial_status = try runtime_locomotion.inspectCurrentStatus(&room, runtime_session);
    const interaction = viewer_shell.initialInteractionState(catalog);

    const key_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        catalog,
        interaction,
        initial_status,
        .w,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, key_result.post_key_action);
    try std.testing.expectEqual(runtime_locomotion.HeroIntent.default_action, runtime_session.pendingHeroIntent().?);

    const tick_result = try runtime_update.tick(&room, &runtime_session);
    try std.testing.expect(tick_result.consumed_hero_intent);
    try std.testing.expectEqual(@as(i16, 1), runtime_session.gameVar(0));
    try std.testing.expectEqual(@as(usize, 1), runtime_session.rewardCollectibles().len);

    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    const overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &room, runtime_session);
    try std.testing.expectEqualStrings("0013 KEY", overlay.title);
    try std.testing.expectEqualStrings("NAV / KEY", overlay.nav_title);
    try std.testing.expectEqualStrings("ROOM 2/1 KEYS 0 VAR0 1", overlay.lines[0]);
    try std.testing.expectEqualStrings("KEY DROP LIVE", overlay.lines[1]);
    try std.testing.expectEqualStrings("POS 1280 2048 5376 ZONES 4", overlay.lines[2]);
    try std.testing.expectEqualStrings("LAST KEY 1@0", overlay.lines[3]);
}

test "viewer key handling routes scene-2 cellar message actions through runtime intents" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var snapshot_session = try initViewerSession(&room);
    defer snapshot_session.deinit(allocator);
    const snapshot = viewer_shell.buildRenderSnapshot(&room, snapshot_session);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    var runtime_session = try initViewerSession(&room);
    defer runtime_session.deinit(allocator);
    runtime_session.setHeroWorldPosition(.{ .x = 7680, .y = 2048, .z = 768 });
    const initial_status = try runtime_locomotion.inspectCurrentStatus(&room, runtime_session);
    const interaction = viewer_shell.initialInteractionState(catalog);

    const action_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        catalog,
        interaction,
        initial_status,
        .w,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, action_result.post_key_action);
    try std.testing.expectEqual(runtime_locomotion.HeroIntent.default_action, runtime_session.pendingHeroIntent().?);

    const action_tick = try runtime_update.tick(&room, &runtime_session);
    try std.testing.expect(action_tick.consumed_hero_intent);
    try std.testing.expectEqual(@as(?i16, 284), runtime_session.currentDialogId());

    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    const overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &room, runtime_session);
    try std.testing.expectEqualStrings("CELLAR MESSAGE", overlay.title);
    try std.testing.expectEqualStrings("NAV / MESSAGE", overlay.nav_title);
    try std.testing.expectEqualStrings("DIALOG 284", overlay.lines[0]);
    try std.testing.expectEqualStrings("ZONE 6 FACING north", overlay.lines[1]);
    try std.testing.expectEqualStrings("ENTER ACK", overlay.lines[3]);

    const clear_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        catalog,
        interaction,
        action_tick.locomotion_status,
        .enter,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, clear_result.post_key_action);
    try std.testing.expectEqual(runtime_locomotion.HeroIntent.advance_story, runtime_session.pendingHeroIntent().?);

    _ = try runtime_update.tick(&room, &runtime_session);
    try std.testing.expectEqual(@as(?i16, null), runtime_session.currentDialogId());
}

test "viewer key handling lets default action no-op in guarded house room" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded22();
    var snapshot_session = try initViewerSession(room);
    defer snapshot_session.deinit(allocator);
    const snapshot = viewer_shell.buildRenderSnapshot(room, snapshot_session);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(allocator);
    _ = try viewer_shell.seedSessionToLocomotionFixture(room, &runtime_session);
    const initial_status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);
    const interaction = viewer_shell.initialInteractionState(catalog);

    const key_result = try viewer_shell.handleKeyDown(
        room,
        &runtime_session,
        catalog,
        interaction,
        initial_status,
        .w,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, key_result.post_key_action);
    try std.testing.expectEqual(runtime_locomotion.HeroIntent.default_action, runtime_session.pendingHeroIntent().?);

    const tick_result = try runtime_update.tick(room, &runtime_session);
    try std.testing.expect(tick_result.consumed_hero_intent);
    try std.testing.expect(!tick_result.triggered_room_transition);
    try std.testing.expectEqual(@as(i16, 0), runtime_session.gameVar(0));
    try std.testing.expectEqual(@as(usize, 0), runtime_session.rewardCollectibles().len);
}

test "viewer 0013 key overlay exposes source-ready state before default action" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var runtime_session = try initViewerSession(&room);
    defer runtime_session.deinit(allocator);

    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    const overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &room, runtime_session);

    try std.testing.expectEqualStrings("0013 KEY", overlay.title);
    try std.testing.expectEqualStrings("NAV / KEY", overlay.nav_title);
    try std.testing.expectEqualStrings("ROOM 2/1 KEYS 0 VAR0 0", overlay.lines[0]);
    try std.testing.expectEqualStrings("KEY SOURCE READY", overlay.lines[1]);
    try std.testing.expectEqualStrings("POS 9724 1024 782 ZONES NONE", overlay.lines[2]);
    try std.testing.expectEqualStrings("SRC N PICK N DOOR N RET N", overlay.lines[3]);
}

test "viewer secret-room validation hotkeys jump to proof positions" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var snapshot_session = try initViewerSession(&room);
    defer snapshot_session.deinit(allocator);
    const snapshot = viewer_shell.buildRenderSnapshot(&room, snapshot_session);
    const catalog = try fragment_compare.buildFragmentComparisonCatalog(allocator, snapshot);
    defer catalog.deinit(allocator);

    var runtime_session = try initViewerSession(&room);
    defer runtime_session.deinit(allocator);
    const initial_status = try runtime_locomotion.inspectCurrentStatus(&room, runtime_session);
    const interaction = viewer_shell.initialInteractionState(catalog);

    const source_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        catalog,
        interaction,
        initial_status,
        .proof_key_source,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, source_result.post_key_action);
    try std.testing.expect(source_result.should_print_locomotion_diagnostic);
    try std.testing.expectEqual(viewer_shell.WorldPointSnapshot{ .x = 1280, .y = 2048, .z = 5376 }, runtime_session.heroWorldPosition());

    const pickup_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        catalog,
        source_result.interaction,
        source_result.locomotion_status,
        .proof_key_pickup,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.none, pickup_result.post_key_action);
    const expected_pickup_cell = try runtime_query.init(&room).gridCellAtWorldPoint(3768, 4366);
    const expected_pickup_surface = try runtime_query.init(&room).cellTopSurface(expected_pickup_cell.x, expected_pickup_cell.z);
    try std.testing.expectEqual(
        viewer_shell.WorldPointSnapshot{ .x = 3768, .y = expected_pickup_surface.top_y, .z = 4366 },
        runtime_session.heroWorldPosition(),
    );

    const door_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        catalog,
        pickup_result.interaction,
        pickup_result.locomotion_status,
        .proof_house_door,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.apply_validation_zone_effects, door_result.post_key_action);
    try std.testing.expectEqual(viewer_shell.WorldPointSnapshot{ .x = 3050, .y = 2048, .z = 4034 }, runtime_session.heroWorldPosition());

    const tick_result = try viewer_shell.handleKeyDown(
        &room,
        &runtime_session,
        catalog,
        door_result.interaction,
        door_result.locomotion_status,
        .space,
    );
    try std.testing.expectEqual(viewer_shell.ViewerPostKeyAction.advance_world, tick_result.post_key_action);
}

test "viewer 0013 key overlay distinguishes exact zones from projected zone footprints" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var runtime_session = try initViewerSession(&room);
    defer runtime_session.deinit(allocator);
    runtime_session.setHeroWorldPosition(.{ .x = 1280, .y = 6400, .z = 5376 });

    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    const overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &room, runtime_session);

    try std.testing.expectEqualStrings("0013 KEY", overlay.title);
    try std.testing.expectEqualStrings("KEY SOURCE READY", overlay.lines[1]);
    try std.testing.expectEqualStrings("POS 1280 6400 5376 ZONES NONE XZ 4", overlay.lines[2]);
}

test "viewer zone probe overlay exposes projected zone footprints for manual navigation" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    var runtime_session = try initViewerSession(&room);
    defer runtime_session.deinit(allocator);
    runtime_session.setHeroWorldPosition(.{ .x = 1280, .y = 6400, .z = 5376 });

    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    const overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &room, runtime_session);

    try std.testing.expectEqualStrings("ZONE PROBE", overlay.title);
    try std.testing.expectEqualStrings("NAV / ZONE", overlay.nav_title);
    try std.testing.expectEqualStrings("POS 1280 6400 5376", overlay.lines[0]);
    try std.testing.expectEqualStrings("ZONES NONE", overlay.lines[1]);
    try std.testing.expectEqualStrings("XZ ZONES 4", overlay.lines[2]);
    try std.testing.expectEqualStrings("Y 6400 ZONE Y 1024..2304", overlay.lines[3]);
}

test "viewer 0013 key overlay follows pickup and cellar return state" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var runtime_session = try initViewerSession(&room);
    defer runtime_session.deinit(allocator);
    runtime_session.setHeroWorldPosition(.{ .x = 1280, .y = 2048, .z = 5376 });
    try runtime_session.submitHeroIntent(.default_action);
    _ = try runtime_update.tick(&room, &runtime_session);

    const key_landing_cell = try runtime_query.init(&room).gridCellAtWorldPoint(3768, 4366);
    const key_landing_surface = try runtime_query.init(&room).cellTopSurface(key_landing_cell.x, key_landing_cell.z);
    runtime_session.setHeroWorldPosition(.{ .x = 3768, .y = key_landing_surface.top_y, .z = 4366 });
    while (runtime_session.littleKeyCount() == 0) {
        _ = try runtime_update.tick(&room, &runtime_session);
    }

    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    const picked_overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &room, runtime_session);
    try std.testing.expectEqualStrings("ROOM 2/1 KEYS 1 VAR0 1", picked_overlay.lines[0]);
    try std.testing.expectEqualStrings("KEY TAKEN", picked_overlay.lines[1]);
    try std.testing.expectEqualStrings("PICK KEY 1@2", picked_overlay.lines[3]);

    var cellar_room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer cellar_room.deinit(allocator);
    try runtime_session.replaceRoomLocalState(
        allocator,
        .{ .x = 9730, .y = 1025, .z = 1126 },
        cellar_room.scene.objects,
        cellar_room.scene.object_behavior_seeds,
    );
    runtime_session.setLittleKeyCount(0);

    const cellar_ready_overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &cellar_room, runtime_session);
    try std.testing.expectEqualStrings("ROOM 2/0 KEYS 0 VAR0 1", cellar_ready_overlay.lines[0]);
    try std.testing.expectEqualStrings("CELLAR RETURN READY", cellar_ready_overlay.lines[1]);

    _ = try runtime_update.tick(&cellar_room, &runtime_session);
    try std.testing.expect(runtime_session.pendingRoomTransition() != null);
    const return_overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, &cellar_room, runtime_session);
    try std.testing.expectEqualStrings("ROOM 2/0 KEYS 0 VAR0 1", return_overlay.lines[0]);
    try std.testing.expectEqualStrings("CELLAR RETURN READY", return_overlay.lines[1]);
}

test "viewer Sendell dialog overlay is transient and scheduler-owned" {
    const room = try room_fixtures.guarded3636();

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), viewer_shell.formatSendellDialogOverlayDisplay(room, runtime_session).line_count);

    try runtime_session.submitHeroIntent(.cast_lightning);
    _ = try runtime_update.tick(room, &runtime_session);

    const first_overlay = viewer_shell.formatSendellDialogOverlayDisplay(room, runtime_session);
    try std.testing.expectEqualStrings("SENDELL DIAL", first_overlay.title);
    try std.testing.expectEqual(@as(usize, 4), first_overlay.line_count);
    try std.testing.expectEqualStrings("CURRENT DIAL 3", first_overlay.lines[0]);
    try std.testing.expectEqualStrings(
        "You just found Sendell's Ball. Now you have reached a new level of magic: Red Ball. It will also enable ",
        first_overlay.lines[1],
    );
    try std.testing.expectEqualStrings("Sendell to contact you in case of danger.", first_overlay.lines[2]);

    try runtime_session.submitHeroIntent(.advance_story);
    _ = try runtime_update.tick(room, &runtime_session);

    const second_overlay = viewer_shell.formatSendellDialogOverlayDisplay(room, runtime_session);
    try std.testing.expectEqual(@as(usize, 4), second_overlay.line_count);
    try std.testing.expectEqualStrings("CURRENT DIAL 3", second_overlay.lines[0]);
    try std.testing.expectEqualStrings("Sendell to contact you in case of danger.", second_overlay.lines[1]);
    try std.testing.expectEqualStrings("<END>", second_overlay.lines[2]);

    try runtime_session.submitHeroIntent(.advance_story);
    _ = try runtime_update.tick(room, &runtime_session);

    const completed_overlay = viewer_shell.formatSendellDialogOverlayDisplay(room, runtime_session);
    try std.testing.expectEqual(@as(usize, 0), completed_overlay.line_count);
}

test "viewer 19/19 reward overlay reflects the bounded object-2 bonus loop" {
    const room = try room_fixtures.guarded1919();

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(std.testing.allocator);
    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    try std.testing.expectEqual(@as(usize, 0), viewer_shell.formatScene1919RewardOverlayDisplay(&overlay_buffer, room, runtime_session).line_count);

    runtime_session.setHeroWorldPosition(.{
        .x = 2500,
        .y = 1000,
        .z = 1000,
    });
    _ = try runtime_object_behavior.stepSupportedObjects(room, &runtime_session);
    runtime_session.advanceFrameIndex();
    const primed_state = runtime_session.objectBehaviorStateByIndexPtr(2) orelse return error.MissingRuntimeObjectBehaviorState;
    primed_state.last_hit_by = 1;

    var reward_tick: ?usize = null;
    var tick_index: usize = 1;
    while (tick_index < 16) : (tick_index += 1) {
        _ = try runtime_object_behavior.stepSupportedObjects(room, &runtime_session);
        runtime_session.advanceFrameIndex();
        if (runtime_session.bonusSpawnEvents().len != 0) {
            reward_tick = tick_index + 1;
            break;
        }
    }

    try std.testing.expectEqual(@as(?usize, 13), reward_tick);
    const rewarded_state = runtime_session.objectBehaviorStateByIndex(2) orelse return error.MissingRuntimeObjectBehaviorState;
    const overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, room, runtime_session);
    try std.testing.expectEqualStrings("OBJ2 LOOP", overlay.title);
    try std.testing.expectEqualStrings("NAV / REWARD", overlay.nav_title);
    try std.testing.expectEqual(@as(usize, 4), overlay.line_count);
    var expected_line_0: [32]u8 = undefined;
    var expected_track: [8]u8 = undefined;
    const expected_line_0_slice = std.fmt.bufPrint(
        &expected_line_0,
        "TRACK {s} SPR {d}",
        .{
            if (rewarded_state.current_track_label) |value|
                std.fmt.bufPrint(&expected_track, "{d}", .{value}) catch unreachable
            else
                "NONE",
            rewarded_state.current_sprite,
        },
    ) catch unreachable;
    var expected_line_2: [32]u8 = undefined;
    const expected_line_2_slice = std.fmt.bufPrint(
        &expected_line_2,
        "CUBE0 {d} CUBE1 {d}",
        .{
            runtime_session.cubeVar(0),
            runtime_session.cubeVar(1),
        },
    ) catch unreachable;
    try std.testing.expectEqualStrings(expected_line_0_slice, overlay.lines[0]);
    try std.testing.expectEqualStrings("DROP 10 LIVE", overlay.lines[1]);
    try std.testing.expectEqualStrings(expected_line_2_slice, overlay.lines[2]);
    try std.testing.expectEqualStrings("LAST MAG 5@12", overlay.lines[3]);
}

test "viewer 19/19 reward overlay shows bounded pickup resolution once the magic bonus is collected" {
    const room = try room_fixtures.guarded1919();

    var runtime_session = try initViewerSession(room);
    defer runtime_session.deinit(std.testing.allocator);
    var overlay_buffer: viewer_shell.ViewerDialogOverlayDisplayBuffer = .{};
    runtime_session.setMagicLevelAndRefill(3);
    runtime_session.setMagicPoint(10);
    runtime_session.setHeroWorldPosition(.{
        .x = 2500,
        .y = 1000,
        .z = 1000,
    });

    _ = try runtime_object_behavior.stepSupportedObjects(room, &runtime_session);
    runtime_session.advanceFrameIndex();
    const primed_state = runtime_session.objectBehaviorStateByIndexPtr(2) orelse return error.MissingRuntimeObjectBehaviorState;
    primed_state.last_hit_by = 1;

    while (runtime_session.rewardCollectibles().len == 0) {
        _ = try runtime_object_behavior.stepSupportedObjects(room, &runtime_session);
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
        _ = try runtime_update.tick(room, &runtime_session);
    }

    runtime_session.setHeroWorldPosition(runtime_session.rewardCollectibles()[0].world_position);
    _ = try runtime_update.tick(room, &runtime_session);

    const overlay = viewer_shell.formatGameplayOverlayDisplay(&overlay_buffer, room, runtime_session);
    try std.testing.expectEqualStrings("DROP 9 LIVE", overlay.lines[1]);
    try std.testing.expectEqualStrings("PICK MAG 5@16", overlay.lines[3]);
}
