const std = @import("std");
const builtin = @import("builtin");
const room_fixtures = if (builtin.is_test) @import("../testing/room_fixtures.zig") else struct {};
const room_state = @import("room_state.zig");
const world_geometry = @import("world_geometry.zig");

pub const HeroWorldDelta = struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
};

pub const HeroIntent = union(enum) {
    move_cardinal: world_geometry.CardinalDirection,
    default_action,
    cast_lightning,
    advance_story,
};

pub const FrameUpdate = struct {
    hero_world_delta: HeroWorldDelta = .{},
};

pub const HeroState = struct {
    world_position: world_geometry.WorldPointSnapshot,
};

pub const ObjectState = room_state.ObjectPositionSnapshot;
pub const ObjectBehaviorSeedState = room_state.ObjectBehaviorSeedSnapshot;
pub const RuntimeBonusKind = enum {
    magic,
    little_key,
};

pub const BonusSpawnEvent = struct {
    frame_index: usize,
    source_object_index: usize,
    kind: RuntimeBonusKind,
    sprite_index: i16,
    quantity: u8,
};

pub const RewardCollectible = struct {
    spawn_frame_index: usize,
    source_object_index: usize,
    kind: RuntimeBonusKind,
    sprite_index: i16,
    quantity: u8,
    admitted_surface_cell: world_geometry.GridCell,
    admitted_surface_top_y: i32,
    scatter_slot: u8,
    rebound_count: u8,
    settled: bool,
    motion_start_world_position: world_geometry.WorldPointSnapshot,
    motion_target_world_position: world_geometry.WorldPointSnapshot,
    motion_total_ticks: u8,
    motion_ticks_remaining: u8,
    motion_arc_height: i32,
    world_position: world_geometry.WorldPointSnapshot,
};

pub const RewardPickupEvent = struct {
    pickup_frame_index: usize,
    source_object_index: usize,
    kind: RuntimeBonusKind,
    sprite_index: i16,
    quantity: u8,
    world_position: world_geometry.WorldPointSnapshot,
};

pub const PendingRoomTransitionDestinationPositionKind = enum {
    provisional_zone_relative,
    final_landing,
    saved_cube_start_context,
};

pub const PendingRoomTransition = struct {
    source_zone_index: usize,
    destination_cube: i16,
    destination_world_position_kind: PendingRoomTransitionDestinationPositionKind,
    destination_world_position: world_geometry.WorldPointSnapshot,
    yaw: i32,
    test_brick: bool,
    dont_readjust_twinsen: bool,
};

const max_bonus_spawn_events = 16;
const max_reward_collectibles = 16;
const max_reward_pickup_events = 16;
const max_game_vars = 256;

pub const SendellBallPhase = enum(u8) {
    idle,
    awaiting_dialog_open,
    awaiting_first_dialog_ack,
    awaiting_second_dialog_ack,
    completed,
};

pub const ObjectBehaviorState = struct {
    index: usize,
    current_track_offset: ?i16,
    current_track_resume_offset: ?i16,
    current_track_label: ?u8,
    current_sprite: i16,
    wait_ticks_remaining: u8,
    last_hit_by: i8,
    sendell_ball_phase: SendellBallPhase,
    emitted_bonus_count: u8,
    bonus_exhausted: bool,
    life_bytes: []u8,
};

pub const Session = struct {
    frame_index: usize,
    hero: HeroState,
    pending_hero_intent: ?HeroIntent,
    cube_vars: [256]u8,
    game_vars: [max_game_vars]i16,
    magic_level: u8,
    magic_point: u8,
    little_key_count: u8,
    secret_room_house_door_unlocked: bool,
    current_dialog_id: ?i16,
    objects: []ObjectState,
    object_behaviors: []ObjectBehaviorState,
    bonus_spawn_event_count: usize,
    bonus_spawn_events: [max_bonus_spawn_events]BonusSpawnEvent,
    reward_collectible_count: usize,
    reward_collectibles: [max_reward_collectibles]RewardCollectible,
    reward_pickup_event_count: usize,
    reward_pickup_events: [max_reward_pickup_events]RewardPickupEvent,
    pending_room_transition: ?PendingRoomTransition,
    owns_objects: bool,
    owns_object_behaviors: bool,

    pub fn init(hero_world_position: world_geometry.WorldPointSnapshot) Session {
        return .{
            .frame_index = 0,
            .hero = .{
                .world_position = hero_world_position,
            },
            .pending_hero_intent = null,
            .cube_vars = [_]u8{0} ** 256,
            .game_vars = [_]i16{0} ** max_game_vars,
            .magic_level = 0,
            .magic_point = 0,
            .little_key_count = 0,
            .secret_room_house_door_unlocked = false,
            .current_dialog_id = null,
            .objects = &.{},
            .object_behaviors = &.{},
            .bonus_spawn_event_count = 0,
            .bonus_spawn_events = undefined,
            .reward_collectible_count = 0,
            .reward_collectibles = undefined,
            .reward_pickup_event_count = 0,
            .reward_pickup_events = undefined,
            .pending_room_transition = null,
            .owns_objects = false,
            .owns_object_behaviors = false,
        };
    }

    pub fn initWithObjects(
        allocator: std.mem.Allocator,
        hero_world_position: world_geometry.WorldPointSnapshot,
        objects: []const ObjectState,
        behavior_seeds: []const ObjectBehaviorSeedState,
    ) !Session {
        const owned_objects = try allocator.dupe(ObjectState, objects);
        errdefer allocator.free(owned_objects);
        const owned_object_behaviors = try copyObjectBehaviorStates(allocator, behavior_seeds);
        errdefer allocator.free(owned_object_behaviors);

        return .{
            .frame_index = 0,
            .hero = .{
                .world_position = hero_world_position,
            },
            .pending_hero_intent = null,
            .cube_vars = [_]u8{0} ** 256,
            .game_vars = [_]i16{0} ** max_game_vars,
            .magic_level = 0,
            .magic_point = 0,
            .little_key_count = 0,
            .secret_room_house_door_unlocked = false,
            .current_dialog_id = null,
            .objects = owned_objects,
            .object_behaviors = owned_object_behaviors,
            .bonus_spawn_event_count = 0,
            .bonus_spawn_events = undefined,
            .reward_collectible_count = 0,
            .reward_collectibles = undefined,
            .reward_pickup_event_count = 0,
            .reward_pickup_events = undefined,
            .pending_room_transition = null,
            .owns_objects = true,
            .owns_object_behaviors = true,
        };
    }

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        if (self.owns_objects) allocator.free(self.objects);
        if (self.owns_object_behaviors) {
            for (self.object_behaviors) |object_behavior| allocator.free(object_behavior.life_bytes);
            allocator.free(self.object_behaviors);
        }
        self.objects = &.{};
        self.object_behaviors = &.{};
        self.bonus_spawn_event_count = 0;
        self.reward_collectible_count = 0;
        self.reward_pickup_event_count = 0;
        self.current_dialog_id = null;
        self.pending_room_transition = null;
        self.owns_objects = false;
        self.owns_object_behaviors = false;
    }

    pub fn replaceRoomLocalState(
        self: *Session,
        allocator: std.mem.Allocator,
        hero_world_position: world_geometry.WorldPointSnapshot,
        objects: []const ObjectState,
        behavior_seeds: []const ObjectBehaviorSeedState,
    ) !void {
        const owned_objects = try allocator.dupe(ObjectState, objects);
        errdefer allocator.free(owned_objects);
        const owned_object_behaviors = try copyObjectBehaviorStates(allocator, behavior_seeds);
        errdefer {
            for (owned_object_behaviors) |object_behavior| allocator.free(object_behavior.life_bytes);
            allocator.free(owned_object_behaviors);
        }

        if (self.owns_objects) allocator.free(self.objects);
        if (self.owns_object_behaviors) {
            for (self.object_behaviors) |object_behavior| allocator.free(object_behavior.life_bytes);
            allocator.free(self.object_behaviors);
        }

        self.hero.world_position = hero_world_position;
        self.pending_hero_intent = null;
        self.current_dialog_id = null;
        self.objects = owned_objects;
        self.object_behaviors = owned_object_behaviors;
        self.bonus_spawn_event_count = 0;
        self.reward_collectible_count = 0;
        self.reward_pickup_event_count = 0;
        self.pending_room_transition = null;
        self.owns_objects = true;
        self.owns_object_behaviors = true;
    }

    pub fn heroWorldPosition(self: Session) world_geometry.WorldPointSnapshot {
        return self.hero.world_position;
    }

    pub fn setHeroWorldPosition(self: *Session, position: world_geometry.WorldPointSnapshot) void {
        self.hero.world_position = position;
    }

    pub fn pendingHeroIntent(self: Session) ?HeroIntent {
        return self.pending_hero_intent;
    }

    pub fn cubeVar(self: Session, index: u8) u8 {
        return self.cube_vars[index];
    }

    pub fn setCubeVar(self: *Session, index: u8, value: u8) void {
        self.cube_vars[index] = value;
    }

    pub fn addCubeVar(self: *Session, index: u8, delta: u8) void {
        self.cube_vars[index] +%= delta;
    }

    pub fn addCubeVarSaturating(self: *Session, index: u8, delta: u8) void {
        const current: u16 = self.cube_vars[index];
        const addition: u16 = delta;
        self.cube_vars[index] = @intCast(@min(current + addition, std.math.maxInt(u8)));
    }

    pub fn gameVar(self: Session, index: u8) i16 {
        return self.game_vars[index];
    }

    pub fn setGameVar(self: *Session, index: u8, value: i16) void {
        self.game_vars[index] = value;
    }

    pub fn magicLevel(self: Session) u8 {
        return self.magic_level;
    }

    pub fn magicPoint(self: Session) u8 {
        return self.magic_point;
    }

    pub fn littleKeyCount(self: Session) u8 {
        return self.little_key_count;
    }

    pub fn secretRoomHouseDoorUnlocked(self: Session) bool {
        return self.secret_room_house_door_unlocked;
    }

    pub fn currentDialogId(self: Session) ?i16 {
        return self.current_dialog_id;
    }

    pub fn setMagicLevelAndRefill(self: *Session, level: u8) void {
        self.magic_level = level;
        self.magic_point = level * 20;
    }

    pub fn setMagicPoint(self: *Session, value: u8) void {
        self.magic_point = value;
    }

    pub fn setLittleKeyCount(self: *Session, value: u8) void {
        self.little_key_count = value;
    }

    pub fn addLittleKeysSaturating(self: *Session, delta: u8) void {
        const current: u16 = self.little_key_count;
        const addition: u16 = delta;
        self.little_key_count = @intCast(@min(current + addition, std.math.maxInt(u8)));
    }

    pub fn consumeLittleKey(self: *Session) bool {
        if (self.little_key_count == 0) return false;
        self.little_key_count -= 1;
        return true;
    }

    pub fn setSecretRoomHouseDoorUnlocked(self: *Session, unlocked: bool) void {
        self.secret_room_house_door_unlocked = unlocked;
    }

    pub fn setCurrentDialogId(self: *Session, dialog_id: i16) !void {
        if (self.current_dialog_id != null) return error.CurrentDialogAlreadySet;
        self.current_dialog_id = dialog_id;
    }

    pub fn clearCurrentDialogId(self: *Session) void {
        self.current_dialog_id = null;
    }

    pub fn objectSnapshots(self: Session) []const ObjectState {
        return self.objects;
    }

    pub fn objectSnapshotByIndex(self: Session, object_index: usize) ?ObjectState {
        for (self.objects) |object| {
            if (object.index == object_index) return object;
        }
        return null;
    }

    pub fn objectBehaviorStates(self: Session) []const ObjectBehaviorState {
        return self.object_behaviors;
    }

    pub fn bonusSpawnEvents(self: Session) []const BonusSpawnEvent {
        return self.bonus_spawn_events[0..self.bonus_spawn_event_count];
    }

    pub fn rewardCollectibles(self: Session) []const RewardCollectible {
        return self.reward_collectibles[0..self.reward_collectible_count];
    }

    pub fn rewardCollectiblePtrAt(self: *Session, collectible_index: usize) ?*RewardCollectible {
        if (collectible_index >= self.reward_collectible_count) return null;
        return &self.reward_collectibles[collectible_index];
    }

    pub fn rewardPickupEvents(self: Session) []const RewardPickupEvent {
        return self.reward_pickup_events[0..self.reward_pickup_event_count];
    }

    pub fn pendingRoomTransition(self: Session) ?PendingRoomTransition {
        return self.pending_room_transition;
    }

    pub fn objectBehaviorStateByIndex(self: Session, object_index: usize) ?ObjectBehaviorState {
        for (self.object_behaviors) |object_behavior| {
            if (object_behavior.index == object_index) return object_behavior;
        }
        return null;
    }

    pub fn objectBehaviorStateByIndexPtr(
        self: *Session,
        object_index: usize,
    ) ?*ObjectBehaviorState {
        for (self.object_behaviors) |*object_behavior| {
            if (object_behavior.index == object_index) return object_behavior;
        }
        return null;
    }

    pub fn setObjectWorldPosition(
        self: *Session,
        object_index: usize,
        position: world_geometry.WorldPointSnapshot,
    ) !void {
        for (self.objects) |*object| {
            if (object.index != object_index) continue;
            object.x = position.x;
            object.y = position.y;
            object.z = position.z;
            return;
        }
        return error.UnknownSessionObjectIndex;
    }

    pub fn submitHeroIntent(self: *Session, intent: HeroIntent) !void {
        if (self.pending_hero_intent != null) return error.PendingHeroIntentAlreadySet;
        self.pending_hero_intent = intent;
    }

    pub fn consumeHeroIntent(self: *Session) ?HeroIntent {
        const intent = self.pending_hero_intent;
        self.pending_hero_intent = null;
        return intent;
    }

    pub fn appendBonusSpawnEvent(self: *Session, event: BonusSpawnEvent) !void {
        if (self.bonus_spawn_event_count >= self.bonus_spawn_events.len) {
            return error.BonusSpawnEventCapacityExceeded;
        }
        self.bonus_spawn_events[self.bonus_spawn_event_count] = event;
        self.bonus_spawn_event_count += 1;
    }

    pub fn appendRewardCollectible(self: *Session, collectible: RewardCollectible) !void {
        if (self.reward_collectible_count >= self.reward_collectibles.len) {
            return error.RewardCollectibleCapacityExceeded;
        }
        self.reward_collectibles[self.reward_collectible_count] = collectible;
        self.reward_collectible_count += 1;
    }

    pub fn appendRewardPickupEvent(self: *Session, event: RewardPickupEvent) !void {
        if (self.reward_pickup_event_count >= self.reward_pickup_events.len) {
            return error.RewardPickupEventCapacityExceeded;
        }
        self.reward_pickup_events[self.reward_pickup_event_count] = event;
        self.reward_pickup_event_count += 1;
    }

    pub fn removeRewardCollectibleAt(self: *Session, collectible_index: usize) !void {
        if (collectible_index >= self.reward_collectible_count) return error.UnknownRewardCollectibleIndex;
        const last_index = self.reward_collectible_count - 1;
        if (collectible_index != last_index) {
            self.reward_collectibles[collectible_index] = self.reward_collectibles[last_index];
        }
        self.reward_collectible_count = last_index;
    }

    pub fn setPendingRoomTransition(
        self: *Session,
        transition: PendingRoomTransition,
    ) !void {
        if (self.pending_room_transition != null) return error.PendingRoomTransitionAlreadySet;
        self.pending_room_transition = transition;
    }

    pub fn clearPendingRoomTransition(self: *Session) void {
        self.pending_room_transition = null;
    }

    pub fn advanceFrameIndex(self: *Session) void {
        self.frame_index += 1;
    }

    pub fn advanceFrame(self: *Session, update: FrameUpdate) void {
        self.advanceFrameIndex();
        self.hero.world_position.x += update.hero_world_delta.x;
        self.hero.world_position.y += update.hero_world_delta.y;
        self.hero.world_position.z += update.hero_world_delta.z;
    }
};

fn copyObjectBehaviorStates(
    allocator: std.mem.Allocator,
    behavior_seeds: []const ObjectBehaviorSeedState,
) ![]ObjectBehaviorState {
    const copied = try allocator.alloc(ObjectBehaviorState, behavior_seeds.len);
    var initialized_count: usize = 0;
    errdefer {
        for (copied[0..initialized_count]) |object_behavior| allocator.free(object_behavior.life_bytes);
        allocator.free(copied);
    }

    for (behavior_seeds, copied) |seed, *slot| {
        const life_bytes = try allocator.dupe(u8, seed.life_bytes);
        slot.* = .{
            .index = seed.index,
            .current_track_offset = null,
            .current_track_resume_offset = null,
            .current_track_label = null,
            .current_sprite = seed.sprite,
            .wait_ticks_remaining = 0,
            .last_hit_by = 0,
            .sendell_ball_phase = .idle,
            .emitted_bonus_count = 0,
            .bonus_exhausted = false,
            .life_bytes = life_bytes,
        };
        initialized_count += 1;
    }
    return copied;
}

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
    try std.testing.expectEqual(@as(?HeroIntent, null), runtime_session.pendingHeroIntent());
    try std.testing.expectEqual(@as(u8, 0), runtime_session.cubeVar(0));
    try std.testing.expectEqual(@as(i16, 0), runtime_session.gameVar(0));
    try std.testing.expectEqual(@as(u8, 0), runtime_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 0), runtime_session.magicPoint());
    try std.testing.expectEqual(@as(u8, 0), runtime_session.littleKeyCount());
    try std.testing.expectEqual(@as(?i16, null), runtime_session.currentDialogId());
    try std.testing.expectEqual(@as(usize, 0), runtime_session.objectSnapshots().len);
    try std.testing.expectEqual(@as(usize, 0), runtime_session.objectBehaviorStates().len);
    try std.testing.expectEqual(@as(?PendingRoomTransition, null), runtime_session.pendingRoomTransition());
}

test "runtime session updates stay separate from immutable room snapshot ownership" {
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

test "runtime session can own copied object snapshots separately from immutable room state" {
    const room = try room_fixtures.guarded1919();

    var runtime_session = try Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
    defer runtime_session.deinit(std.testing.allocator);

    try std.testing.expectEqual(room.scene.objects.len, runtime_session.objectSnapshots().len);
    try std.testing.expectEqual(room.scene.objects[1], runtime_session.objectSnapshotByIndex(2).?);
    try std.testing.expectEqual(@as(usize, 1), runtime_session.objectBehaviorStates().len);
    try std.testing.expectEqual(@as(i16, 137), runtime_session.objectBehaviorStateByIndex(2).?.current_sprite);
    try std.testing.expectEqual(SendellBallPhase.idle, runtime_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try runtime_session.setObjectWorldPosition(2, .{
        .x = 4096,
        .y = 1408,
        .z = 2048,
    });

    try std.testing.expectEqual(@as(i32, 4096), runtime_session.objectSnapshotByIndex(2).?.x);
    try std.testing.expectEqual(@as(i32, 1408), runtime_session.objectSnapshotByIndex(2).?.y);
    try std.testing.expectEqual(@as(i32, 2048), runtime_session.objectSnapshotByIndex(2).?.z);
    try std.testing.expectEqual(@as(i32, 3088), room.scene.objects[1].x);
    try std.testing.expectEqual(@as(i32, 1248), room.scene.objects[1].y);
    try std.testing.expectEqual(@as(i32, 1488), room.scene.objects[1].z);
    try std.testing.expectEqual(@as(i16, 137), room.scene.object_behavior_seeds[0].sprite);
    try std.testing.expectEqual(@as(?i16, null), runtime_session.objectBehaviorStateByIndex(2).?.current_track_offset);
}

test "runtime session hero intents are single-slot and consumed explicitly" {
    var runtime_session = Session.init(.{
        .x = 1987,
        .y = 512,
        .z = 3743,
    });
    const expected_intent: HeroIntent = .{ .move_cardinal = .south };

    try runtime_session.submitHeroIntent(expected_intent);
    try std.testing.expectEqual(expected_intent, runtime_session.pendingHeroIntent().?);
    try std.testing.expectError(
        error.PendingHeroIntentAlreadySet,
        runtime_session.submitHeroIntent(.{ .move_cardinal = .north }),
    );

    try std.testing.expectEqual(expected_intent, runtime_session.consumeHeroIntent().?);
    try std.testing.expectEqual(@as(?HeroIntent, null), runtime_session.pendingHeroIntent());
    try std.testing.expectEqual(@as(?HeroIntent, null), runtime_session.consumeHeroIntent());
}

test "runtime session tracks mutable game vars and magic state separately from cube vars" {
    var runtime_session = Session.init(.{
        .x = 1987,
        .y = 512,
        .z = 3743,
    });

    runtime_session.setGameVar(3, 1);
    runtime_session.setMagicLevelAndRefill(3);
    runtime_session.setMagicPoint(0);

    try std.testing.expectEqual(@as(i16, 1), runtime_session.gameVar(3));
    try std.testing.expectEqual(@as(u8, 3), runtime_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 0), runtime_session.magicPoint());
    try std.testing.expectEqual(@as(u8, 0), runtime_session.cubeVar(3));
}

test "runtime session tracks little keys as durable inventory state" {
    var runtime_session = Session.init(.{
        .x = 1987,
        .y = 512,
        .z = 3743,
    });

    runtime_session.setLittleKeyCount(1);
    runtime_session.addLittleKeysSaturating(2);

    try std.testing.expectEqual(@as(u8, 3), runtime_session.littleKeyCount());

    runtime_session.setLittleKeyCount(254);
    runtime_session.addLittleKeysSaturating(3);
    try std.testing.expectEqual(@as(u8, 255), runtime_session.littleKeyCount());

    try std.testing.expect(runtime_session.consumeLittleKey());
    try std.testing.expectEqual(@as(u8, 254), runtime_session.littleKeyCount());
    runtime_session.setLittleKeyCount(0);
    try std.testing.expect(!runtime_session.consumeLittleKey());
}

test "runtime session keeps transient current dialog state explicit and single-slot" {
    var runtime_session = Session.init(.{
        .x = 1987,
        .y = 512,
        .z = 3743,
    });

    try std.testing.expectEqual(@as(?i16, null), runtime_session.currentDialogId());
    try runtime_session.setCurrentDialogId(42);
    try std.testing.expectEqual(@as(?i16, 42), runtime_session.currentDialogId());
    try std.testing.expectError(error.CurrentDialogAlreadySet, runtime_session.setCurrentDialogId(43));

    runtime_session.clearCurrentDialogId();
    try std.testing.expectEqual(@as(?i16, null), runtime_session.currentDialogId());
    try runtime_session.setCurrentDialogId(44);
    try std.testing.expectEqual(@as(?i16, 44), runtime_session.currentDialogId());
}

test "runtime session keeps pending room transitions explicit and single-slot" {
    var runtime_session = Session.init(.{
        .x = 1987,
        .y = 512,
        .z = 3743,
    });
    const expected_transition = PendingRoomTransition{
        .source_zone_index = 0,
        .destination_cube = 42,
        .destination_world_position_kind = .final_landing,
        .destination_world_position = .{
            .x = 2560,
            .y = 2048,
            .z = 3072,
        },
        .yaw = 3,
        .test_brick = false,
        .dont_readjust_twinsen = false,
    };

    try runtime_session.setPendingRoomTransition(expected_transition);
    try std.testing.expectEqual(expected_transition, runtime_session.pendingRoomTransition().?);
    try std.testing.expectError(
        error.PendingRoomTransitionAlreadySet,
        runtime_session.setPendingRoomTransition(expected_transition),
    );

    runtime_session.clearPendingRoomTransition();
    try std.testing.expectEqual(@as(?PendingRoomTransition, null), runtime_session.pendingRoomTransition());
}

test "runtime session can advance frame ownership without mutating hero position" {
    var runtime_session = Session.init(.{
        .x = 1987,
        .y = 512,
        .z = 3743,
    });

    runtime_session.advanceFrameIndex();

    try std.testing.expectEqual(@as(usize, 1), runtime_session.frame_index);
    try std.testing.expectEqual(@as(i32, 1987), runtime_session.heroWorldPosition().x);
    try std.testing.expectEqual(@as(i32, 512), runtime_session.heroWorldPosition().y);
    try std.testing.expectEqual(@as(i32, 3743), runtime_session.heroWorldPosition().z);
}

test "runtime render snapshots consume session state without duplicating guarded loading" {
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

test "runtime session can replace room-local state while preserving durable runtime state" {
    const source_room = try room_fixtures.guarded1919();
    const destination_room = try room_fixtures.guarded22();

    var runtime_session = try Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(source_room),
        source_room.scene.objects,
        source_room.scene.object_behavior_seeds,
    );
    defer runtime_session.deinit(std.testing.allocator);

    runtime_session.advanceFrameIndex();
    runtime_session.setCubeVar(7, 3);
    runtime_session.setGameVar(9, 12);
    runtime_session.setMagicLevelAndRefill(2);
    runtime_session.setMagicPoint(17);
    runtime_session.setLittleKeyCount(1);
    runtime_session.setSecretRoomHouseDoorUnlocked(true);
    try runtime_session.setCurrentDialogId(42);
    try runtime_session.setPendingRoomTransition(.{
        .source_zone_index = 0,
        .destination_cube = 0,
        .destination_world_position_kind = .final_landing,
        .destination_world_position = .{ .x = 2560, .y = 2048, .z = 3072 },
        .yaw = 0,
        .test_brick = false,
        .dont_readjust_twinsen = false,
    });

    try runtime_session.replaceRoomLocalState(
        std.testing.allocator,
        .{ .x = 2560, .y = 2048, .z = 3072 },
        destination_room.scene.objects,
        destination_room.scene.object_behavior_seeds,
    );

    try std.testing.expectEqual(@as(usize, 1), runtime_session.frame_index);
    try std.testing.expectEqual(@as(u8, 3), runtime_session.cubeVar(7));
    try std.testing.expectEqual(@as(i16, 12), runtime_session.gameVar(9));
    try std.testing.expectEqual(@as(u8, 2), runtime_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 17), runtime_session.magicPoint());
    try std.testing.expectEqual(@as(u8, 1), runtime_session.littleKeyCount());
    try std.testing.expect(runtime_session.secretRoomHouseDoorUnlocked());
    try std.testing.expectEqual(@as(?i16, null), runtime_session.currentDialogId());
    try std.testing.expectEqual(@as(?PendingRoomTransition, null), runtime_session.pendingRoomTransition());
    try std.testing.expectEqual(@as(i32, 2560), runtime_session.heroWorldPosition().x);
    try std.testing.expectEqual(@as(i32, 2048), runtime_session.heroWorldPosition().y);
    try std.testing.expectEqual(@as(i32, 3072), runtime_session.heroWorldPosition().z);
    try std.testing.expectEqual(destination_room.scene.objects.len, runtime_session.objectSnapshots().len);
    try std.testing.expectEqual(destination_room.scene.object_behavior_seeds.len, runtime_session.objectBehaviorStates().len);
}
