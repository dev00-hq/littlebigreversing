const std = @import("std");
const builtin = @import("builtin");

var active_io: ?std.Io = null;
var active_environ_map: ?*std.process.Environ.Map = null;

pub fn currentIo() std.Io {
    if (builtin.is_test) return std.testing.io;
    return active_io orelse std.debug.panic("process IO used before process.runWithArgs initialized it", .{});
}

pub fn currentEnv() *std.process.Environ.Map {
    return active_environ_map orelse std.debug.panic("process environment used before process.runWithArgs initialized it", .{});
}

pub fn runWithArgs(init: std.process.Init, comptime callback: anytype) !void {
    active_io = init.io;
    active_environ_map = init.environ_map;
    defer {
        active_io = null;
        active_environ_map = null;
    }

    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    var args_iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iterator.deinit();

    _ = args_iterator.skip();

    var args = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit();
    }
    while (args_iterator.next()) |arg| {
        try args.append(try allocator.dupe(u8, arg));
    }

    try callback(allocator, args.items);
}
