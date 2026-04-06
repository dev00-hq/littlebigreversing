const std = @import("std");
const lba2 = @import("lba2");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const parsed = lba2.app.viewer_shell.parseArgs(allocator, args[1..]) catch |err| {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        const stderr = &stderr_writer.interface;
        lba2.foundation.diagnostics.printError(stderr, @errorName(err));
        stderr.flush() catch {};
        return err;
    };
    defer parsed.deinit(allocator);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    const resolved = lba2.foundation.paths.resolveFromExecutable(allocator, parsed.asset_root_override) catch |err| {
        lba2.foundation.diagnostics.printError(stderr, @errorName(err));
        stderr.flush() catch {};
        return err;
    };
    defer resolved.deinit(allocator);

    lba2.assets.catalog.validateExplicitRequirements(resolved.asset_root) catch |err| {
        lba2.foundation.diagnostics.printError(stderr, @errorName(err));
        stderr.flush() catch {};
        return err;
    };

    const room = lba2.app.viewer_shell.loadRoomSnapshot(
        allocator,
        resolved,
        parsed.scene_entry,
        parsed.background_entry,
    ) catch |err| {
        if (err == error.ViewerUnsupportedSceneLife) {
            const hit = try lba2.runtime.room_state.inspectUnsupportedSceneLifeHit(
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
        lba2.foundation.diagnostics.printError(stderr, @errorName(err));
        stderr.flush() catch {};
        return err;
    };
    defer room.deinit(allocator);

    var runtime_session = lba2.app.viewer_shell.initSession(&room);
    var locomotion_status = try lba2.runtime.locomotion.inspectCurrentStatus(&room, runtime_session);
    try lba2.app.viewer_shell.printStartupDiagnostics(stderr, allocator, resolved, &room);
    try lba2.app.viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status);
    var render = lba2.app.viewer_shell.buildRenderSnapshot(&room, runtime_session);
    var fragment_catalog = try lba2.app.viewer_shell.buildFragmentComparisonCatalog(allocator, render);
    defer fragment_catalog.deinit(allocator);
    var fragment_selection = lba2.app.viewer_shell.initialFragmentComparisonSelection(fragment_catalog);
    const title = try lba2.app.viewer_shell.formatWindowTitleZ(allocator, &room);
    defer allocator.free(title);
    try stderr.flush();

    var canvas = lba2.platform.sdl.Canvas.init(
        title,
        lba2.app.viewer_shell.window_width,
        lba2.app.viewer_shell.window_height,
    ) catch |err| {
        lba2.foundation.diagnostics.printError(stderr, sdlErrorMessage(err));
        stderr.flush() catch {};
        return err;
    };
    defer canvas.deinit();

    lba2.app.viewer_shell.renderDebugViewWithSelection(
        &canvas,
        render,
        fragment_catalog,
        fragment_selection,
        locomotion_status,
    ) catch |err| {
        lba2.foundation.diagnostics.printError(stderr, sdlErrorMessage(err));
        stderr.flush() catch {};
        return err;
    };

    while (true) {
        const event = canvas.waitEvent() catch |err| {
            lba2.foundation.diagnostics.printError(stderr, sdlErrorMessage(err));
            stderr.flush() catch {};
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
                fragment_selection,
                locomotion_status,
            ),
            .key_down => |key| {
                switch (key) {
                    .enter => {
                        _ = try lba2.app.viewer_shell.seedSessionToLocomotionFixture(&room, &runtime_session);
                        locomotion_status = try lba2.runtime.locomotion.inspectCurrentStatus(&room, runtime_session);
                        try lba2.app.viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status);
                    },
                    .left, .right, .up, .down => {
                        if (fragment_selection.focus != null) {
                            fragment_selection = switch (key) {
                                .left => lba2.app.viewer_shell.stepRankedFragmentComparisonSelection(fragment_catalog, fragment_selection, -1),
                                .right => lba2.app.viewer_shell.stepRankedFragmentComparisonSelection(fragment_catalog, fragment_selection, 1),
                                .up => lba2.app.viewer_shell.stepCellFragmentComparisonSelection(fragment_catalog, fragment_selection, -1),
                                .down => lba2.app.viewer_shell.stepCellFragmentComparisonSelection(fragment_catalog, fragment_selection, 1),
                                else => unreachable,
                            };
                        } else {
                            const direction: lba2.app.viewer_shell.CardinalDirection = switch (key) {
                                .left => .west,
                                .right => .east,
                                .up => .north,
                                .down => .south,
                                else => unreachable,
                            };
                            locomotion_status = try lba2.runtime.locomotion.applyStep(&room, &runtime_session, direction);
                            try lba2.app.viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status);
                        }
                    },
                }
                try stderr.flush();
                try renderCurrentFrame(
                    allocator,
                    &canvas,
                    stderr,
                    &room,
                    runtime_session,
                    &render,
                    &fragment_catalog,
                    fragment_selection,
                    locomotion_status,
                );
            },
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
        lba2.platform.sdl.lastError()
    else
        @errorName(err);
}

fn printUnsupportedSceneLifeDiagnostic(
    writer: anytype,
    scene_entry_index: usize,
    background_entry_index: usize,
    hit: lba2.runtime.room_state.UnsupportedSceneLifeHit,
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
    canvas: *lba2.platform.sdl.Canvas,
    stderr: anytype,
    room: *const lba2.app.viewer_shell.RoomSnapshot,
    runtime_session: lba2.app.viewer_shell.Session,
    render: *lba2.app.viewer_shell.RenderSnapshot,
    fragment_catalog: *lba2.app.viewer_shell.FragmentComparisonCatalog,
    fragment_selection: lba2.app.viewer_shell.FragmentComparisonSelection,
    locomotion_status: lba2.app.viewer_shell.ViewerLocomotionStatus,
) !void {
    const next_render = lba2.app.viewer_shell.buildRenderSnapshot(room, runtime_session);
    const next_catalog = try lba2.app.viewer_shell.buildFragmentComparisonCatalog(allocator, next_render);
    fragment_catalog.deinit(allocator);
    render.* = next_render;
    fragment_catalog.* = next_catalog;
    lba2.app.viewer_shell.renderDebugViewWithSelection(
        canvas,
        render.*,
        fragment_catalog.*,
        fragment_selection,
        locomotion_status,
    ) catch |err| {
        lba2.foundation.diagnostics.printError(stderr, sdlErrorMessage(err));
        stderr.flush() catch {};
        return err;
    };
}
