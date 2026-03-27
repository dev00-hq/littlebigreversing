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
    const title = try lba2.app.viewer_shell.formatWindowTitleZ(allocator, room);
    defer allocator.free(title);
    try stderr.flush();

    lba2.platform.sdl.runWindow(title) catch |err| {
        const message = if (err == error.SdlInitFailed or err == error.SdlCreateWindowFailed or err == error.SdlWaitEventFailed)
            lba2.platform.sdl.lastError()
        else
            @errorName(err);
        lba2.foundation.diagnostics.printError(stderr, message);
        stderr.flush() catch {};
        return err;
    };

    try stderr.print(
        "status=ok event=shutdown scene_entry={d} background_entry={d}\n",
        .{ parsed.scene_entry, parsed.background_entry },
    );
    try stderr.flush();
}
