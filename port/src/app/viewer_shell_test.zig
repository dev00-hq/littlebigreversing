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
        try std.testing.expectEqual(option.evaluation.status, move_options.options[index].status);
    }
}

fn upperAscii(buffer: []u8, text: []const u8) []const u8 {
    const len = @min(buffer.len, text.len);
    for (text[0..len], 0..) |char, index| {
        buffer[index] = if (char >= 'a' and char <= 'z') char - 32 else char;
    }
    return buffer[0..len];
}

fn expectDisplayMoveOptionLines(
    display: viewer_shell.ViewerLocomotionStatusDisplay,
    line_index: usize,
    move_options: viewer_shell.ViewerMoveOptions,
) !void {
    var north_status_buffer: [40]u8 = undefined;
    var east_status_buffer: [40]u8 = undefined;
    var south_status_buffer: [40]u8 = undefined;
    var west_status_buffer: [40]u8 = undefined;
    var first_line_buffer: [64]u8 = undefined;
    const first_line = try std.fmt.bufPrint(
        &first_line_buffer,
        "N {s} E {s}",
        .{
            upperAscii(&north_status_buffer, @tagName(move_options.options[0].status)),
            upperAscii(&east_status_buffer, @tagName(move_options.options[1].status)),
        },
    );
    var second_line_buffer: [64]u8 = undefined;
    const second_line = try std.fmt.bufPrint(
        &second_line_buffer,
        "S {s} W {s}",
        .{
            upperAscii(&south_status_buffer, @tagName(move_options.options[2].status)),
            upperAscii(&west_status_buffer, @tagName(move_options.options[3].status)),
        },
    );

    try std.testing.expectEqualStrings(first_line, display.lines[line_index]);
    try std.testing.expectEqualStrings(second_line, display.lines[line_index + 1]);
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

fn formatMoveOptionsDiagnosticValue(
    buffer: []u8,
    move_options: viewer_shell.ViewerMoveOptions,
) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "north:{s},east:{s},south:{s},west:{s}",
        .{
            @tagName(move_options.options[0].status),
            @tagName(move_options.options[1].status),
            @tagName(move_options.options[2].status),
            @tagName(move_options.options[3].status),
        },
    );
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
            try std.testing.expectEqual(@as(?viewer_shell.GridCell, .{ .x = 3, .z = 7 }), value.raw_cell);
            try std.testing.expectEqual(runtime_query.OccupiedCoverageRelation.outside_occupied_bounds, value.occupied_coverage);
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
    try std.testing.expectEqual(@as(usize, 3), display.line_count);
    try std.testing.expectEqualStrings("RAW START INVALID", display.lines[0]);
    try std.testing.expectEqualStrings("CELL 3/7 MAPPED_CELL_EMPTY", display.lines[1]);
    try std.testing.expectEqualStrings("BOUNDS OUTSIDE_OCCUPIED_BOUNDS", display.lines[2]);

    const raw_diagnostic = try formatDiagnostic(allocator, status);
    defer allocator.free(raw_diagnostic);
    const expected_raw_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_status status=raw_invalid_start exact_status={s} raw_cell=3/7 occupied_coverage={s} move_options=unavailable hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            @tagName(raw_value.exact_status),
            @tagName(raw_value.occupied_coverage),
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
    try std.testing.expectEqual(@as(usize, 6), display.line_count);
    try std.testing.expectEqualStrings("FIXTURE SEEDED VALID", display.lines[0]);
    try std.testing.expectEqualStrings("CELL 39/6 STATUS ALLOWED", display.lines[1]);
    try expectDisplayMoveOptionLines(display, 2, seeded_value.move_options);
    try std.testing.expectEqualStrings("ZONES NONE", display.lines[4]);
    try std.testing.expectEqualStrings("ARROWS MOVE FROM HERE", display.lines[5]);

    const diagnostic = try formatDiagnostic(allocator, status);
    defer allocator.free(diagnostic);
    var seeded_move_options_buffer: [128]u8 = undefined;
    var seeded_cell_buffer: [16]u8 = undefined;
    var seeded_zone_buffer: [128]u8 = undefined;
    const expected_seeded_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_seed status=seeded_valid cell={s} move_options={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatRequiredCellValue(&seeded_cell_buffer, seeded_value.cell),
            try formatMoveOptionsDiagnosticValue(&seeded_move_options_buffer, seeded_value.move_options),
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
            try std.testing.expectEqual(viewer_shell.GridCell{ .x = 39, .z = 7 }, value.cell);
            try expectMoveOptions(room, runtime_session.heroWorldPosition(), value.move_options);
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
    try std.testing.expectEqual(@as(usize, 6), moved_display.line_count);
    try std.testing.expectEqualStrings("MOVE SOUTH ACCEPTED", moved_display.lines[0]);
    try std.testing.expectEqualStrings("CELL 39/7 STATUS ALLOWED", moved_display.lines[1]);
    try expectDisplayMoveOptionLines(moved_display, 2, moved_value.move_options);
    try std.testing.expectEqualStrings("ZONES NONE", moved_display.lines[4]);
    try std.testing.expectEqualStrings("HERO POSITION UPDATED", moved_display.lines[5]);

    const moved_diagnostic = try formatDiagnostic(allocator, moved_status);
    defer allocator.free(moved_diagnostic);
    var moved_move_options_buffer: [128]u8 = undefined;
    var moved_cell_buffer: [16]u8 = undefined;
    var moved_zone_buffer: [128]u8 = undefined;
    const expected_moved_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_move direction=south status=accepted cell={s} move_options={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatRequiredCellValue(&moved_cell_buffer, moved_value.cell),
            try formatMoveOptionsDiagnosticValue(&moved_move_options_buffer, moved_value.move_options),
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
            try expectMoveOptions(room, before_reject, value.move_options.?);
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
    try std.testing.expectEqual(@as(usize, 6), rejected_display.line_count);
    try std.testing.expectEqualStrings("MOVE WEST REJECTED", rejected_display.lines[0]);
    try std.testing.expectEqualStrings("STAY CELL 39/6", rejected_display.lines[1]);
    try expectDisplayMoveOptionLines(rejected_display, 2, rejected_value.move_options.?);
    try std.testing.expectEqualStrings("ZONES NONE", rejected_display.lines[4]);
    try std.testing.expectEqualStrings("REASON TARGET_EMPTY", rejected_display.lines[5]);

    const rejected_diagnostic = try formatDiagnostic(allocator, rejected_status);
    defer allocator.free(rejected_diagnostic);
    var rejected_current_cell_buffer: [16]u8 = undefined;
    var rejected_target_cell_buffer: [16]u8 = undefined;
    var rejected_move_options_buffer: [128]u8 = undefined;
    var rejected_zone_buffer: [128]u8 = undefined;
    const expected_rejected_diagnostic = try std.fmt.allocPrint(
        allocator,
        "event=hero_move direction=west status=rejected rejection_stage=target_rejected reason=target_empty current_cell={s} target_cell={s} move_options={s} zones={s} hero_x={d} hero_y={d} hero_z={d}\n",
        .{
            try formatOptionalCellValue(&rejected_current_cell_buffer, rejected_value.current_cell),
            try formatOptionalCellValue(&rejected_target_cell_buffer, rejected_value.target_cell),
            try formatMoveOptionsDiagnosticValue(&rejected_move_options_buffer, rejected_value.move_options.?),
            formatZoneDiagnosticValue(&rejected_zone_buffer, rejected_value.zone_membership),
            rejected_value.hero_position.x,
            rejected_value.hero_position.y,
            rejected_value.hero_position.z,
        },
    );
    defer allocator.free(expected_rejected_diagnostic);
    try std.testing.expectEqualStrings(expected_rejected_diagnostic, rejected_diagnostic);
}
