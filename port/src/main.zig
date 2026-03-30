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
        lba2.foundation.diagnostics.printError(stderr, @errorName(err));
        stderr.flush() catch {};
        return err;
    };
    defer room.deinit(allocator);

    try lba2.app.viewer_shell.printStartupDiagnostics(stderr, resolved, room);
    const render = lba2.app.viewer_shell.buildRenderSnapshot(room);
    const fragment_catalog = try lba2.app.viewer_shell.buildFragmentComparisonCatalog(allocator, render);
    defer fragment_catalog.deinit(allocator);
    var fragment_selection = lba2.app.viewer_shell.initialFragmentComparisonSelection(fragment_catalog);
    const title = try lba2.app.viewer_shell.formatWindowTitleZ(allocator, room);
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

    lba2.app.viewer_shell.renderDebugViewWithSelection(&canvas, render, fragment_catalog, fragment_selection) catch |err| {
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
            .redraw => lba2.app.viewer_shell.renderDebugViewWithSelection(&canvas, render, fragment_catalog, fragment_selection) catch |err| {
                lba2.foundation.diagnostics.printError(stderr, sdlErrorMessage(err));
                stderr.flush() catch {};
                return err;
            },
            .key_down => |key| {
                fragment_selection = switch (key) {
                    .left => lba2.app.viewer_shell.stepRankedFragmentComparisonSelection(fragment_catalog, fragment_selection, -1),
                    .right => lba2.app.viewer_shell.stepRankedFragmentComparisonSelection(fragment_catalog, fragment_selection, 1),
                    .up => lba2.app.viewer_shell.stepCellFragmentComparisonSelection(fragment_catalog, fragment_selection, -1),
                    .down => lba2.app.viewer_shell.stepCellFragmentComparisonSelection(fragment_catalog, fragment_selection, 1),
                };
                lba2.app.viewer_shell.renderDebugViewWithSelection(&canvas, render, fragment_catalog, fragment_selection) catch |err| {
                    lba2.foundation.diagnostics.printError(stderr, sdlErrorMessage(err));
                    stderr.flush() catch {};
                    return err;
                };
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
