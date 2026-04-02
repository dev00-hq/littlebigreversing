const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const room_state = @import("room_state.zig");

pub const HeroWorldDelta = struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
};

pub const FrameUpdate = struct {
    hero_world_delta: HeroWorldDelta = .{},
};

pub const HeroState = struct {
    world_position: room_state.WorldPointSnapshot,
};

pub const Session = struct {
    frame_index: usize,
    hero: HeroState,

    pub fn init(room: *const room_state.RoomSnapshot) Session {
        return .{
            .frame_index = 0,
            .hero = .{
                .world_position = .{
                    .x = room.scene.hero_start.x,
                    .y = room.scene.hero_start.y,
                    .z = room.scene.hero_start.z,
                },
            },
        };
    }

    pub fn heroWorldPosition(self: Session) room_state.WorldPointSnapshot {
        return self.hero.world_position;
    }

    pub fn setHeroWorldPosition(self: *Session, position: room_state.WorldPointSnapshot) void {
        self.hero.world_position = position;
    }

    pub fn advanceFrame(self: *Session, update: FrameUpdate) void {
        self.frame_index += 1;
        self.hero.world_position.x += update.hero_world_delta.x;
        self.hero.world_position.y += update.hero_world_delta.y;
        self.hero.world_position.z += update.hero_world_delta.z;
    }
};

test "runtime session initializes mutable hero state from the guarded room snapshot" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    const runtime_session = Session.init(&room);
    try std.testing.expectEqual(@as(usize, 0), runtime_session.frame_index);
    try std.testing.expectEqual(@as(i32, 1987), runtime_session.hero.world_position.x);
    try std.testing.expectEqual(@as(i32, 512), runtime_session.hero.world_position.y);
    try std.testing.expectEqual(@as(i32, 3743), runtime_session.hero.world_position.z);
}

test "runtime session updates stay separate from immutable room snapshot ownership" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var runtime_session = Session.init(&room);
    runtime_session.advanceFrame(.{
        .hero_world_delta = .{ .x = 32, .y = -16, .z = 64 },
    });

    try std.testing.expectEqual(@as(usize, 1), runtime_session.frame_index);
    try std.testing.expectEqual(@as(i32, 2019), runtime_session.hero.world_position.x);
    try std.testing.expectEqual(@as(i32, 496), runtime_session.hero.world_position.y);
    try std.testing.expectEqual(@as(i32, 3807), runtime_session.hero.world_position.z);
    try std.testing.expectEqual(@as(i16, 1987), room.scene.hero_start.x);
    try std.testing.expectEqual(@as(i16, 512), room.scene.hero_start.y);
    try std.testing.expectEqual(@as(i16, 3743), room.scene.hero_start.z);
}

test "runtime render snapshots consume session state without duplicating guarded loading" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var runtime_session = Session.init(&room);
    runtime_session.setHeroWorldPosition(.{
        .x = 2222,
        .y = 640,
        .z = 3333,
    });

    const render = room_state.buildRenderSnapshotWithHeroPosition(room, runtime_session.heroWorldPosition());
    try std.testing.expectEqual(@as(i32, 2222), render.hero_position.x);
    try std.testing.expectEqual(@as(i32, 640), render.hero_position.y);
    try std.testing.expectEqual(@as(i32, 3333), render.hero_position.z);
    try std.testing.expectEqual(@as(i16, 1987), room.scene.hero_start.x);
    try std.testing.expectEqual(@as(i16, 512), room.scene.hero_start.y);
    try std.testing.expectEqual(@as(i16, 3743), room.scene.hero_start.z);
}
