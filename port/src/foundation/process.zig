const std = @import("std");
const builtin = @import("builtin");

pub fn currentIo() std.Io {
    if (builtin.is_test) return std.testing.io;
    return .default;
}

pub fn runWithArgs(comptime callback: anytype) !void {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);
    const args = if (raw_args.len > 0) raw_args[1..] else raw_args[0..0];

    try callback(allocator, args);
}
