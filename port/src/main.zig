const std = @import("std");
const lba2 = @import("lba2");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const asset_root_override = try parseAssetRootArg(allocator, args[1..]);
    defer if (asset_root_override) |value| allocator.free(value);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    const resolved = lba2.foundation.paths.resolveFromExecutable(allocator, asset_root_override) catch |err| {
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

    try lba2.foundation.diagnostics.printLine(stderr, &.{
        .{ .key = "event", .value = "startup" },
        .{ .key = "repo_root", .value = resolved.repo_root },
        .{ .key = "asset_root", .value = resolved.asset_root },
        .{ .key = "work_root", .value = resolved.work_root },
    });
    try stderr.flush();

    lba2.platform.sdl.runSmokeWindow() catch |err| {
        const message = if (err == error.SdlInitFailed or err == error.SdlCreateWindowFailed)
            lba2.platform.sdl.lastError()
        else
            @errorName(err);
        lba2.foundation.diagnostics.printError(stderr, message);
        stderr.flush() catch {};
        return err;
    };

    try lba2.foundation.diagnostics.printLine(stderr, &.{
        .{ .key = "status", .value = "ok" },
        .{ .key = "event", .value = "shutdown" },
    });
    try stderr.flush();
}

fn parseAssetRootArg(allocator: std.mem.Allocator, args: []const []const u8) !?[]u8 {
    if (args.len == 0) return null;
    if (args.len == 2 and std.mem.eql(u8, args[0], "--asset-root")) {
        return allocator.dupe(u8, args[1]);
    }
    return error.InvalidArguments;
}
