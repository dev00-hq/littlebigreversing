const runtime_session = @import("session.zig");

pub fn applyPromotedMagicBallImpact(
    current_session: *runtime_session.Session,
    projectile: runtime_session.MagicBallProjectile,
) !void {
    switch (projectile.script) {
        .tralu_level1_damage => try applyTraluLevel1MagicBallDamage(current_session, projectile),
        .emerald_moon_switch_object3 => try applyEmeraldMoonSwitchActivation(current_session, projectile, 3, 2),
        .emerald_moon_switch_object4 => try applyEmeraldMoonSwitchActivation(current_session, projectile, 4, 4),
        .radar_room_lever_primary => try applyRadarRoomLeverActivation(current_session, projectile),
        .wizard_tent_lever_primary => try applyWizardTentLeverActivation(current_session, projectile),
        .warehouse_blocked_lever => try appendMagicBallImpactEvent(current_session, projectile, .blocked_impact, 25, null, null),
        .none,
        .level1_wall_normal,
        .fire_wall_normal,
        => return error.UnsupportedMagicBallImpactScript,
    }
}

fn applyTraluLevel1MagicBallDamage(
    current_session: *runtime_session.Session,
    projectile: runtime_session.MagicBallProjectile,
) !void {
    const target_object_index: usize = 3;
    const damage = try current_session.applyObjectLifeDamageSaturating(target_object_index, 9);
    try appendMagicBallImpactEvent(
        current_session,
        projectile,
        .damage_applied,
        target_object_index,
        @intCast(damage.before),
        @intCast(damage.after),
    );
}

fn applyEmeraldMoonSwitchActivation(
    current_session: *runtime_session.Session,
    projectile: runtime_session.MagicBallProjectile,
    target_object_index: usize,
    final_label: u8,
) !void {
    const target = current_session.objectBehaviorStateByIndexPtr(target_object_index) orelse return error.MissingRuntimeObjectBehaviorState;
    const before = target.current_track_label;
    target.current_track_label = final_label;
    try appendMagicBallImpactEvent(
        current_session,
        projectile,
        .switch_activated,
        target_object_index,
        optionalU8ToI16(before),
        @intCast(final_label),
    );
}

fn applyRadarRoomLeverActivation(
    current_session: *runtime_session.Session,
    projectile: runtime_session.MagicBallProjectile,
) !void {
    const target_object_index: usize = 19;
    const target = current_session.objectBehaviorStateByIndexPtr(target_object_index) orelse return error.MissingRuntimeObjectBehaviorState;
    const before = target.current_gen_anim;
    target.current_gen_anim = 244;
    target.next_gen_anim = 244;
    if (current_session.objectBehaviorStateByIndexPtr(21)) |linked| linked.current_track_label = 0;
    try appendMagicBallImpactEvent(current_session, projectile, .lever_activated, target_object_index, before, 244);
}

fn applyWizardTentLeverActivation(
    current_session: *runtime_session.Session,
    projectile: runtime_session.MagicBallProjectile,
) !void {
    const target_object_index: usize = 2;
    const target = current_session.objectBehaviorStateByIndexPtr(target_object_index) orelse return error.MissingRuntimeObjectBehaviorState;
    const before = target.current_track_label;
    target.current_track_label = 9;
    target.current_gen_anim = 0;
    target.next_gen_anim = 0;
    if (current_session.objectSnapshotByIndex(3)) |linked| {
        try current_session.setObjectWorldPosition(3, .{ .x = linked.x, .y = linked.y, .z = 5632 });
    }
    try appendMagicBallImpactEvent(
        current_session,
        projectile,
        .lever_activated,
        target_object_index,
        optionalU8ToI16(before),
        9,
    );
}

fn appendMagicBallImpactEvent(
    current_session: *runtime_session.Session,
    projectile: runtime_session.MagicBallProjectile,
    kind: runtime_session.MagicBallProjectileEventKind,
    target_object_index: usize,
    before: ?i16,
    after: ?i16,
) !void {
    try current_session.appendMagicBallProjectileEvent(.{
        .frame_index = current_session.frame_index,
        .kind = kind,
        .script = projectile.script,
        .target_object_index = target_object_index,
        .value_before = before,
        .value_after = after,
        .sprite_index = projectile.sprite_index,
        .world_position = projectile.world_position,
        .vx = projectile.vx,
        .vy = projectile.vy,
        .vz = projectile.vz,
    });
}

fn optionalU8ToI16(value: ?u8) ?i16 {
    return if (value) |actual| @as(i16, actual) else null;
}
