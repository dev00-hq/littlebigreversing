const std = @import("std");
const room_fixtures = @import("../testing/room_fixtures.zig");
const runtime_locomotion = @import("../runtime/locomotion.zig");
const runtime_query = @import("../runtime/world_query.zig");
const viewer_shell = @import("viewer_shell.zig");

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
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try viewer_shell.printLocomotionStatusDiagnostic(output.writer(allocator), status);
    return output.toOwnedSlice(allocator);
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
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    for (move_options.options, 0..) |option, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.print(
            "{s}:{s}:{s}",
            .{
                directionLabel(option.direction),
                try formatOptionalCellValue(&cell_buffers[index], option.target_cell),
                @tagName(option.status),
            },
        );
    }
    return stream.getWritten();
}

fn formatZoneDiagnosticValue(
    buffer: []u8,
    zone_membership: runtime_query.ContainingZoneSet,
) []const u8 {
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

fn formatLocalTopologyHudLine(
    buffer: []u8,
    local_topology: viewer_shell.ViewerLocalNeighborTopology,
) ![]const u8 {
    var token_buffers: [4][16]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
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
    return stream.getWritten();
}

fn formatLocalTopologyDiagnosticValue(
    buffer: []u8,
    local_topology: viewer_shell.ViewerLocalNeighborTopology,
) ![]const u8 {
    var cell_buffers: [4][16]u8 = undefined;
    var standability_buffers: [4][16]u8 = undefined;
    var delta_buffers: [4][16]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
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
    return stream.getWritten();
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

test "viewer locomotion harness consumes runtime-owned raw invalid 19/19 status without mutation" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    var runtime_session = viewer_shell.initSession(room);
    const raw_start = runtime_session.heroWorldPosition();
    const status = try runtime_locomotion.inspectCurrentStatus(room, runtime_session);
    const rejected_status = try runtime_locomotion.applyStep(room, &runtime_session, .south);

    switch (status) {
        .raw_invalid_start => |value| {
            try std.testing.expectEqual(runtime_query.HeroStartExactStatus.mapped_cell_empty, value.exact_status);
            try std.testing.expectEqual(runtime_query.HeroStartDiagnosticStatus.exact_invalid_mapping_mismatch, value.diagnostic_status);
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, .{ .x = 3, .z = 7 }), value.raw_cell);
            try std.testing.expectEqual(runtime_query.OccupiedCoverageRelation.outside_occupied_bounds, value.occupied_coverage);
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
    try std.testing.expectEqual(@as(usize, 6), display.line_count);
    try std.testing.expectEqualStrings("RAW START INVALID", display.lines[0]);
    try std.testing.expectEqualStrings("CELL 3/7 MAPPED_CELL_EMPTY", display.lines[1]);
    try std.testing.expectEqualStrings("DIAG EXACT_INVALID_MAPPING_MISMATCH", display.lines[2]);
    try std.testing.expectEqualStrings("BOUNDS OUTSIDE_OCCUPIED_BOUNDS", display.lines[3]);
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
    try expectNoSchematicCue(display);
    try expectNoAttemptCue(display);

    const raw_diagnostic = try formatDiagnostic(allocator, status);
    defer allocator.free(raw_diagnostic);
    var nearest_occupied_buffer: [48]u8 = undefined;
    var nearest_standable_buffer: [48]u8 = undefined;
    const expected_raw_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_status status=raw_invalid_start exact_status={s} diagnostic_status={s} raw_cell=3/7 occupied_coverage={s} nearest_occupied={s} nearest_standable={s} move_options=unavailable hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            @tagName(raw_value.exact_status),
            @tagName(raw_value.diagnostic_status),
            @tagName(raw_value.occupied_coverage),
            try formatRawInvalidStartCandidateDiagnosticValue(&nearest_occupied_buffer, raw_value.nearest_occupied),
            try formatRawInvalidStartCandidateDiagnosticValue(&nearest_standable_buffer, raw_value.nearest_standable),
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

    var runtime_session = viewer_shell.initSession(room);
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
    try std.testing.expectEqualStrings("ARROWS MOVE FROM HERE", display.lines[6]);
    try expectAdmittedPathSchematicCue(display, seeded_value.move_options);
    try expectNoAttemptCue(display);

    const diagnostic = try formatDiagnostic(allocator, status);
    defer allocator.free(diagnostic);
    var seeded_move_options_buffer: [256]u8 = undefined;
    var seeded_topology_buffer: [384]u8 = undefined;
    var seeded_cell_buffer: [16]u8 = undefined;
    var seeded_zone_buffer: [128]u8 = undefined;
    const expected_seeded_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_seed status=seeded_valid cell={s} move_options={s} local_topology={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatRequiredCellValue(&seeded_cell_buffer, seeded_value.cell),
            try formatMoveOptionsDiagnosticValue(&seeded_move_options_buffer, seeded_value.move_options),
            try formatLocalTopologyDiagnosticValue(&seeded_topology_buffer, seeded_value.local_topology),
            formatZoneDiagnosticValue(&seeded_zone_buffer, seeded_value.zone_membership),
            seeded_value.hero_position.x,
            seeded_value.hero_position.y,
            seeded_value.hero_position.z,
        },
    );
    defer allocator.free(expected_seeded_diagnostic);
    try std.testing.expectEqualStrings(expected_seeded_diagnostic, diagnostic);
}

test "viewer locomotion harness consumes runtime-owned accepted and rejected seeded steps" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    var runtime_session = viewer_shell.initSession(room);
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
    try std.testing.expectEqualStrings("HERO POSITION UPDATED", moved_display.lines[6]);
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
    var moved_cell_buffer: [16]u8 = undefined;
    var moved_zone_buffer: [128]u8 = undefined;
    const expected_moved_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_move direction=south status=accepted cell={s} move_options={s} local_topology={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatRequiredCellValue(&moved_cell_buffer, moved_value.cell),
            try formatMoveOptionsDiagnosticValue(&moved_move_options_buffer, moved_value.move_options),
            try formatLocalTopologyDiagnosticValue(&moved_topology_buffer, moved_value.local_topology),
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
    try std.testing.expectEqual(before_reject, runtime_session.heroWorldPosition());
    switch (rejected_status) {
        .last_move_rejected => |value| {
            try std.testing.expectEqual(viewer_shell.CardinalDirection.west, value.direction);
            try std.testing.expectEqual(viewer_shell.ViewerLocomotionRejectedStage.target_rejected, value.rejection_stage);
            try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_empty, value.reason);
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, viewer_shell.locomotion_fixture_cell), value.current_cell);
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, .{ .x = 38, .z = 6 }), value.target_cell);
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
    try std.testing.expectEqualStrings("STAY CELL 39/6", rejected_display.lines[1]);
    try expectDisplayMoveOptionLines(rejected_display, 2, rejected_value.move_options.?);
    try std.testing.expectEqualStrings("ZONES NONE", rejected_display.lines[4]);
    var rejected_topology_line_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        try formatLocalTopologyHudLine(&rejected_topology_line_buffer, rejected_value.local_topology.?),
        rejected_display.lines[5],
    );
    try std.testing.expectEqualStrings("REASON TARGET_EMPTY", rejected_display.lines[6]);
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
    var rejected_move_options_buffer: [256]u8 = undefined;
    var rejected_topology_buffer: [384]u8 = undefined;
    var rejected_zone_buffer: [128]u8 = undefined;
    const expected_rejected_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_move direction=west status=rejected rejection_stage=target_rejected reason=target_empty current_cell={s} target_cell={s} move_options={s} local_topology={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatOptionalCellValue(&rejected_current_cell_buffer, rejected_value.current_cell),
            try formatOptionalCellValue(&rejected_target_cell_buffer, rejected_value.target_cell),
            try formatMoveOptionsDiagnosticValue(&rejected_move_options_buffer, rejected_value.move_options.?),
            try formatLocalTopologyDiagnosticValue(&rejected_topology_buffer, rejected_value.local_topology.?),
            formatZoneDiagnosticValue(&rejected_zone_buffer, rejected_value.zone_membership),
            rejected_value.hero_position.x,
            rejected_value.hero_position.y,
            rejected_value.hero_position.z,
        },
    );
    defer allocator.free(expected_rejected_diagnostic);
    try std.testing.expectEqualStrings(expected_rejected_diagnostic, rejected_diagnostic);
}
