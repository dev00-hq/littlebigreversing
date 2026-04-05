const std = @import("std");
const builtin = @import("builtin");
const room_fixtures = if (builtin.is_test) @import("../testing/room_fixtures.zig") else struct {};
const world_geometry = @import("world_geometry.zig");

pub const HeroWorldDelta = struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
};

pub const FrameUpdate = struct {
    hero_world_delta: HeroWorldDelta = .{},
};

pub const HeroState = struct {
    world_position: world_geometry.WorldPointSnapshot,
};

pub const Session = struct {
    frame_index: usize,
    hero: HeroState,

    pub fn init(hero_world_position: world_geometry.WorldPointSnapshot) Session {
        return .{
            .frame_index = 0,
            .hero = .{
                .world_position = hero_world_position,
            },
        };
    }

    pub fn heroWorldPosition(self: Session) world_geometry.WorldPointSnapshot {
        return self.hero.world_position;
    }

    pub fn setHeroWorldPosition(self: *Session, position: world_geometry.WorldPointSnapshot) void {
        self.hero.world_position = position;
    }

    pub fn advanceFrame(self: *Session, update: FrameUpdate) void {
        self.frame_index += 1;
        self.hero.world_position.x += update.hero_world_delta.x;
        self.hero.world_position.y += update.hero_world_delta.y;
        self.hero.world_position.z += update.hero_world_delta.z;
    }
};

test "runtime session initializes mutable hero state from an explicit world-position seed" {
    const runtime_session = Session.init(.{
        .x = 1987,
        .y = 512,
        .z = 3743,
    });
    try std.testing.expectEqual(@as(usize, 0), runtime_session.frame_index);
    try std.testing.expectEqual(@as(i32, 1987), runtime_session.hero.world_position.x);
    try std.testing.expectEqual(@as(i32, 512), runtime_session.hero.world_position.y);
    try std.testing.expectEqual(@as(i32, 3743), runtime_session.hero.world_position.z);
}

test "runtime session updates stay separate from immutable room snapshot ownership" {
    const room_state = @import("room_state.zig");
    const room = try room_fixtures.guarded1919();

    var runtime_session = Session.init(room_state.heroStartWorldPoint(room));
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
    const room_state = @import("room_state.zig");
    const room = try room_fixtures.guarded1919();

    var runtime_session = Session.init(room_state.heroStartWorldPoint(room));
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
