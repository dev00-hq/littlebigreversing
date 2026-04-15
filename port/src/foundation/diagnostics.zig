const std = @import("std");

pub const Pair = struct {
    key: []const u8,
    value: []const u8,
};

pub fn printLine(writer: anytype, pairs: []const Pair) !void {
    for (pairs, 0..) |pair, index| {
        if (index != 0) try writer.writeByte(' ');
        try writer.print("{s}={s}", .{ pair.key, pair.value });
    }
    try writer.writeByte('\n');
}

pub fn printError(writer: anytype, message: []const u8) !void {
    try writer.print("level=error message=\"{s}\"\n", .{message});
}

pub fn reportError(writer: anytype, message: []const u8) void {
    printError(writer, message) catch {};
    writer.flush() catch {};
}
