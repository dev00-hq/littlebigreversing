const std = @import("std");
const fragment_compare = @import("app/viewer/fragment_compare.zig");
const viewer_shell = @import("app/viewer_shell.zig");
const catalog = @import("assets/catalog.zig");
const diagnostics = @import("foundation/diagnostics.zig");
const paths = @import("foundation/paths.zig");
const process = @import("foundation/process.zig");
const sdl = @import("platform/sdl.zig");
const locomotion = @import("runtime/locomotion.zig");
const room_state = @import("runtime/room_state.zig");
const runtime_update = @import("runtime/update.zig");

pub fn main() !void {
    return process.runWithArgs(run);
}

fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
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

    const room = room_state.loadRoomSnapshot(
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
        viewer_shell.formatSendellDialogOverlayDisplay(&room, runtime_session),
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
        viewer_shell.formatSendellDialogOverlayDisplay(room, runtime_session),
    ) catch |err| {
        diagnostics.reportError(stderr, sdlErrorMessage(err));
        return err;
    };
}

fn processKeyDownEvent(
    allocator: std.mem.Allocator,
    canvas: *sdl.Canvas,
    stderr: anytype,
    room: *const viewer_shell.RoomSnapshot,
    runtime_session: *viewer_shell.Session,
    render: *viewer_shell.RenderSnapshot,
    fragment_catalog: *viewer_shell.FragmentComparisonCatalog,
    interaction: *viewer_shell.ViewerInteractionState,
    locomotion_status: *viewer_shell.ViewerLocomotionStatus,
    key: viewer_shell.ViewerKey,
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
    try applyScheduledWorldStep(stderr, room, runtime_session, locomotion_status, key_result);
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
    stderr: anytype,
    room: *const viewer_shell.RoomSnapshot,
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
        .advance_world => {
            const tick_result = try runtime_update.tick(room, runtime_session);
            locomotion_status.* = tick_result.locomotion_status;
            if (tick_result.consumed_hero_intent or key_result.should_print_locomotion_diagnostic) {
                try viewer_shell.printLocomotionStatusDiagnostic(stderr, locomotion_status.*);
            }
        },
    }
}
