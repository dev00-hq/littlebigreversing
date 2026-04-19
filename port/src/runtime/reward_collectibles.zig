const runtime_query = @import("world_query.zig");
const room_state = @import("room_state.zig");
const runtime_session = @import("session.zig");

const planar_pickup_distance_threshold: i32 = 256;
const denied_pickup_rebound_ticks: u8 = 2;
const denied_pickup_rebound_arc_height: i32 = 96;
const rebound_offset_distance_major: i32 = 128;
const rebound_offset_distance_minor: i32 = 80;

const PickupResolution = enum {
    unavailable,
    denied_capacity,
    allowed,
};

const rebound_offsets = [_]struct { x: i32, z: i32 }{
    .{ .x = rebound_offset_distance_major, .z = 0 },
    .{ .x = 0, .z = rebound_offset_distance_major },
    .{ .x = -rebound_offset_distance_major, .z = 0 },
    .{ .x = 0, .z = -rebound_offset_distance_major },
    .{ .x = rebound_offset_distance_minor, .z = rebound_offset_distance_minor },
    .{ .x = -rebound_offset_distance_minor, .z = rebound_offset_distance_minor },
    .{ .x = rebound_offset_distance_minor, .z = -rebound_offset_distance_minor },
    .{ .x = -rebound_offset_distance_minor, .z = -rebound_offset_distance_minor },
};

pub fn resolveHeroRewardPickups(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !void {
    var collectible_index: usize = 0;
    while (collectible_index < current_session.rewardCollectibles().len) {
        const collectible = current_session.rewardCollectiblePtrAt(collectible_index) orelse return error.UnknownRewardCollectibleIndex;
        advanceCollectibleMotion(collectible);

        switch (heroPickupResolution(room, current_session.*, collectible.*)) {
            .unavailable => {
                collectible_index += 1;
                continue;
            },
            .denied_capacity => {
                try applyDeniedPickupRebound(collectible);
                collectible_index += 1;
                continue;
            },
            .allowed => {},
        }

        try applyRewardPickup(current_session, collectible.*);
        try current_session.appendRewardPickupEvent(.{
            .pickup_frame_index = current_session.frame_index,
            .source_object_index = collectible.source_object_index,
            .kind = collectible.kind,
            .sprite_index = collectible.sprite_index,
            .quantity = collectible.quantity,
            .world_position = collectible.world_position,
        });
        try current_session.removeRewardCollectibleAt(collectible_index);
    }
}

fn advanceCollectibleMotion(
    collectible: *runtime_session.RewardCollectible,
) void {
    if (collectible.motion_ticks_remaining == 0) {
        collectible.world_position = collectible.motion_target_world_position;
        collectible.settled = true;
        return;
    }

    const elapsed_ticks = collectible.motion_total_ticks - collectible.motion_ticks_remaining + 1;
    collectible.motion_ticks_remaining -= 1;
    if (collectible.motion_ticks_remaining == 0) {
        collectible.world_position = collectible.motion_target_world_position;
        collectible.settled = true;
        return;
    }

    collectible.settled = false;
    collectible.world_position = .{
        .x = interpolateAxis(
            collectible.motion_start_world_position.x,
            collectible.motion_target_world_position.x,
            elapsed_ticks,
            collectible.motion_total_ticks,
        ),
        .y = interpolateAxis(
            collectible.motion_start_world_position.y,
            collectible.motion_target_world_position.y,
            elapsed_ticks,
            collectible.motion_total_ticks,
        ) + arcYOffset(elapsed_ticks, collectible.motion_total_ticks, collectible.motion_arc_height),
        .z = interpolateAxis(
            collectible.motion_start_world_position.z,
            collectible.motion_target_world_position.z,
            elapsed_ticks,
            collectible.motion_total_ticks,
        ),
    };
}

fn heroPickupResolution(
    room: *const room_state.RoomSnapshot,
    current_session: runtime_session.Session,
    collectible: runtime_session.RewardCollectible,
) PickupResolution {
    if (!collectible.settled) return .unavailable;

    const query = runtime_query.init(room);
    const hero_footing = query.admittedStandableFootingAtWorldPoint(current_session.heroWorldPosition()) catch return .unavailable;
    if (hero_footing.surface.top_y != collectible.admitted_surface_top_y) return .unavailable;
    if (absDiff(current_session.heroWorldPosition().x, collectible.world_position.x) > planar_pickup_distance_threshold) {
        return .unavailable;
    }
    if (absDiff(current_session.heroWorldPosition().z, collectible.world_position.z) > planar_pickup_distance_threshold) {
        return .unavailable;
    }

    return switch (collectible.kind) {
        .magic => if (current_session.magicLevel() == 0 or
            current_session.magicPoint() >= current_session.magicLevel() * 20)
            .denied_capacity
        else
            .allowed,
    };
}

fn applyDeniedPickupRebound(
    collectible: *runtime_session.RewardCollectible,
) !void {
    const center = runtime_query.gridCellCenterWorldPosition(
        collectible.admitted_surface_cell.x,
        collectible.admitted_surface_cell.z,
        collectible.admitted_surface_top_y,
    );
    const offset = rebound_offsets[
        @as(usize, @intCast((collectible.scatter_slot + collectible.rebound_count) % rebound_offsets.len))
    ];
    collectible.rebound_count +%= 1;
    collectible.motion_start_world_position = collectible.world_position;
    collectible.motion_target_world_position = .{
        .x = center.x + offset.x,
        .y = collectible.admitted_surface_top_y,
        .z = center.z + offset.z,
    };
    collectible.motion_total_ticks = denied_pickup_rebound_ticks;
    collectible.motion_ticks_remaining = denied_pickup_rebound_ticks;
    collectible.motion_arc_height = denied_pickup_rebound_arc_height;
    collectible.settled = false;
}

fn interpolateAxis(
    start: i32,
    target: i32,
    elapsed_ticks: u8,
    total_ticks: u8,
) i32 {
    const numerator = (@as(i64, start) * @as(i64, total_ticks - elapsed_ticks)) +
        (@as(i64, target) * @as(i64, elapsed_ticks));
    return @intCast(@divTrunc(numerator, total_ticks));
}

fn arcYOffset(
    elapsed_ticks: u8,
    total_ticks: u8,
    arc_height: i32,
) i32 {
    if (total_ticks <= 1 or arc_height == 0) return 0;
    const elapsed: i32 = elapsed_ticks;
    const total: i32 = total_ticks;
    const rise = if (elapsed * 2 <= total) elapsed else total - elapsed;
    return @divTrunc(rise * 2 * arc_height, total);
}

fn applyRewardPickup(
    current_session: *runtime_session.Session,
    collectible: runtime_session.RewardCollectible,
) !void {
    switch (collectible.kind) {
        .magic => {
            const current_magic: u16 = current_session.magicPoint();
            const quantity_delta: u16 = @as(u16, collectible.quantity) * 2;
            const max_magic: u16 = @as(u16, current_session.magicLevel()) * 20;
            const next_magic = @min(current_magic + quantity_delta, max_magic);
            current_session.setMagicPoint(@intCast(next_magic));
        },
    }
}

fn absDiff(lhs: i32, rhs: i32) i32 {
    return if (lhs >= rhs) lhs - rhs else rhs - lhs;
}
