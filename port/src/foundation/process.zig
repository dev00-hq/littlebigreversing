const std = @import("std");
const builtin = @import("builtin");

pub const RuntimeIo = if (builtin.is_test) struct {
    pub fn init() RuntimeIo {
        return .{};
    }

    pub fn deinit(self: *RuntimeIo) void {
        _ = self;
    }

    pub fn io(self: *RuntimeIo) std.Io {
        _ = self;
        return std.testing.io;
    }
} else struct {
    threaded: std.Io.Threaded,

    pub fn init() RuntimeIo {
        return .{ .threaded = .init(std.heap.page_allocator, .{}) };
    }

    pub fn deinit(self: *RuntimeIo) void {
        self.threaded.deinit();
    }

    pub fn io(self: *RuntimeIo) std.Io {
        return self.threaded.io();
    }
};

pub fn currentPathAlloc(allocator: std.mem.Allocator) ![:0]u8 {
    var runtime_io = RuntimeIo.init();
    defer runtime_io.deinit();
    return std.process.currentPathAlloc(runtime_io.io(), allocator);
}

pub fn executablePathAlloc(allocator: std.mem.Allocator) ![:0]u8 {
    var runtime_io = RuntimeIo.init();
    defer runtime_io.deinit();
    return std.process.executablePathAlloc(runtime_io.io(), allocator);
}

pub fn runWithArgs(init: std.process.Init, comptime callback: anytype) !void {
    const allocator = init.gpa;

    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer iterator.deinit();
    _ = iterator.skip();

    var args: std.ArrayList([]const u8) = .empty;
    defer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit(allocator);
    }

    while (iterator.next()) |arg| {
        try args.append(allocator, try allocator.dupe(u8, arg));
    }

    try callback(allocator, args.items, init.io);
}
