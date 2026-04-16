const std = @import("std");
const diagnostics = @import("foundation/diagnostics.zig");
const process = @import("foundation/process.zig");
const cli = @import("tools/cli.zig");

pub fn main() !void {
    return process.runWithArgs(run);
}

fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    cli.run(allocator, args) catch |err| {
        if (err == error.MachineReadableReported) std.process.exit(1);
        diagnostics.reportError(stderr, @errorName(err));
        return err;
    };
}
