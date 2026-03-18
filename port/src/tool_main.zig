const std = @import("std");
const lba2 = @import("lba2");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    lba2.tools.cli.run(allocator, args[1..]) catch |err| {
        lba2.foundation.diagnostics.printError(stderr, @errorName(err));
        stderr.flush() catch {};
        return err;
    };
}
