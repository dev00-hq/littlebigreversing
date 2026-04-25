const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const room_state = @import("../runtime/room_state.zig");
const runtime_session = @import("../runtime/session.zig");

var guarded_1919_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var guarded_1919_initialized = false;
var guarded_1919_room: ?*const room_state.RoomSnapshot = null;
var guarded_1919_error: ?anyerror = null;

var guarded_1110_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var guarded_1110_initialized = false;
var guarded_1110_room: ?*const room_state.RoomSnapshot = null;
var guarded_1110_error: ?anyerror = null;

var guarded_22_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var guarded_22_initialized = false;
var guarded_22_room: ?*const room_state.RoomSnapshot = null;
var guarded_22_error: ?anyerror = null;

var guarded_187187_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var guarded_187187_initialized = false;
var guarded_187187_room: ?*const room_state.RoomSnapshot = null;
var guarded_187187_error: ?anyerror = null;

var guarded_3636_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var guarded_3636_initialized = false;
var guarded_3636_room: ?*const room_state.RoomSnapshot = null;
var guarded_3636_error: ?anyerror = null;

pub fn guarded1919() !*const room_state.RoomSnapshot {
    if (!guarded_1919_initialized) {
        initGuarded1919();
        guarded_1919_initialized = true;
    }
    if (guarded_1919_error) |err| return err;
    return guarded_1919_room orelse return error.MissingGuarded1919Fixture;
}

pub fn guarded1110() !*const room_state.RoomSnapshot {
    if (!guarded_1110_initialized) {
        initGuarded1110();
        guarded_1110_initialized = true;
    }
    if (guarded_1110_error) |err| return err;
    return guarded_1110_room orelse return error.MissingGuarded1110Fixture;
}

pub fn guarded22() !*const room_state.RoomSnapshot {
    if (!guarded_22_initialized) {
        initGuarded22();
        guarded_22_initialized = true;
    }
    if (guarded_22_error) |err| return err;
    return guarded_22_room orelse return error.MissingGuarded22Fixture;
}

pub fn guarded187187() !*const room_state.RoomSnapshot {
    if (!guarded_187187_initialized) {
        initGuarded187187();
        guarded_187187_initialized = true;
    }
    if (guarded_187187_error) |err| return err;
    return guarded_187187_room orelse return error.MissingGuarded187187Fixture;
}

pub fn guarded3636() !*const room_state.RoomSnapshot {
    if (!guarded_3636_initialized) {
        initGuarded3636();
        guarded_3636_initialized = true;
    }
    if (guarded_3636_error) |err| return err;
    return guarded_3636_room orelse return error.MissingGuarded3636Fixture;
}

fn initGuarded1919() void {
    guarded_1919_room = loadRoomFixture(&guarded_1919_arena, 19, 19, .guarded) catch |err| {
        guarded_1919_error = err;
        return;
    };
}

fn initGuarded1110() void {
    guarded_1110_room = loadRoomFixture(&guarded_1110_arena, 11, 10, .guarded) catch |err| {
        guarded_1110_error = err;
        return;
    };
}

fn initGuarded22() void {
    guarded_22_room = loadRoomFixture(&guarded_22_arena, 2, 2, .guarded) catch |err| {
        guarded_22_error = err;
        return;
    };
}

fn initGuarded187187() void {
    guarded_187187_room = loadRoomFixture(&guarded_187187_arena, 187, 187, .guarded) catch |err| {
        guarded_187187_error = err;
        return;
    };
}

fn initGuarded3636() void {
    guarded_3636_room = loadRoomFixture(&guarded_3636_arena, 36, 36, .guarded) catch |err| {
        guarded_3636_error = err;
        return;
    };
}

const FixtureLoadMode = enum {
    guarded,
    unchecked,
};

fn loadRoomFixture(
    arena: *std.heap.ArenaAllocator,
    scene_entry_index: usize,
    background_entry_index: usize,
    mode: FixtureLoadMode,
) !*const room_state.RoomSnapshot {
    const allocator = arena.allocator();
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    const room = try allocator.create(room_state.RoomSnapshot);
    room.* = switch (mode) {
        .guarded => try room_state.loadRoomSnapshot(allocator, resolved, scene_entry_index, background_entry_index),
        .unchecked => try room_state.loadRoomSnapshotUncheckedForTests(allocator, resolved, scene_entry_index, background_entry_index),
    };
    return room;
}

test "memoized room fixtures return stable borrowed snapshots" {
    const first_guarded = try guarded1919();
    const second_guarded = try guarded1919();
    const first_guarded_1110 = try guarded1110();
    const second_guarded_1110 = try guarded1110();
    const first_guarded_22 = try guarded22();
    const second_guarded_22 = try guarded22();
    const first_guarded_187187 = try guarded187187();
    const second_guarded_187187 = try guarded187187();
    const first_guarded_3636 = try guarded3636();
    const second_guarded_3636 = try guarded3636();

    try std.testing.expect(first_guarded == second_guarded);
    try std.testing.expect(first_guarded_1110 == second_guarded_1110);
    try std.testing.expect(first_guarded_22 == second_guarded_22);
    try std.testing.expect(first_guarded_187187 == second_guarded_187187);
    try std.testing.expect(first_guarded_3636 == second_guarded_3636);
    try std.testing.expectEqual(@as(usize, 19), first_guarded.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 11), first_guarded_1110.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 2), first_guarded_22.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 187), first_guarded_187187.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 36), first_guarded_3636.scene.entry_index);
}

test "memoized room fixtures stay immutable across session mutations" {
    const room = try guarded1919();
    var runtime = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    runtime.advanceFrame(.{
        .hero_world_delta = .{ .x = 32, .y = -16, .z = 64 },
    });

    try std.testing.expectEqual(@as(i16, 1987), room.scene.hero_start.x);
    try std.testing.expectEqual(@as(i16, 512), room.scene.hero_start.y);
    try std.testing.expectEqual(@as(i16, 3743), room.scene.hero_start.z);
    try std.testing.expectEqual(@as(i32, 2019), runtime.heroWorldPosition().x);
    try std.testing.expectEqual(@as(i32, 496), runtime.heroWorldPosition().y);
    try std.testing.expectEqual(@as(i32, 3807), runtime.heroWorldPosition().z);
}
