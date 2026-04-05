const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const room_state = @import("../runtime/room_state.zig");
const runtime_session = @import("../runtime/session.zig");

var guarded_1919_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var guarded_1919_once = std.once(initGuarded1919);
var guarded_1919_room: ?*const room_state.RoomSnapshot = null;
var guarded_1919_error: ?anyerror = null;

var unchecked_1110_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var unchecked_1110_once = std.once(initUnchecked1110);
var unchecked_1110_room: ?*const room_state.RoomSnapshot = null;
var unchecked_1110_error: ?anyerror = null;

pub fn guarded1919() !*const room_state.RoomSnapshot {
    guarded_1919_once.call();
    if (guarded_1919_error) |err| return err;
    return guarded_1919_room orelse return error.MissingGuarded1919Fixture;
}

pub fn unchecked1110() !*const room_state.RoomSnapshot {
    unchecked_1110_once.call();
    if (unchecked_1110_error) |err| return err;
    return unchecked_1110_room orelse return error.MissingUnchecked1110Fixture;
}

fn initGuarded1919() void {
    guarded_1919_room = loadRoomFixture(&guarded_1919_arena, 19, 19, .guarded) catch |err| {
        guarded_1919_error = err;
        return;
    };
}

fn initUnchecked1110() void {
    unchecked_1110_room = loadRoomFixture(&unchecked_1110_arena, 11, 10, .unchecked) catch |err| {
        unchecked_1110_error = err;
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
    const first_unchecked = try unchecked1110();
    const second_unchecked = try unchecked1110();

    try std.testing.expect(first_guarded == second_guarded);
    try std.testing.expect(first_unchecked == second_unchecked);
    try std.testing.expectEqual(@as(usize, 19), first_guarded.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 11), first_unchecked.scene.entry_index);
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
