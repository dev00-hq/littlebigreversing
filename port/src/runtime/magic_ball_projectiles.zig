const magic_ball_impacts = @import("magic_ball_impacts.zig");
const runtime_session = @import("session.zig");

pub fn advanceMagicBallProjectiles(current_session: *runtime_session.Session) !void {
    const projectile = current_session.magicBallProjectilePtrAt(0) orelse return;
    if (projectile.script == .none) return;

    switch (projectile.script) {
        .none => unreachable,
        .level1_wall_normal => try advanceLevel1WallNormal(current_session, projectile),
        .fire_wall_normal => try advanceFireWallNormal(current_session, projectile),
        .tralu_level1_damage,
        .emerald_moon_switch_object3,
        .emerald_moon_switch_object4,
        .radar_room_lever_primary,
        .wizard_tent_lever_primary,
        .warehouse_blocked_lever,
        => try applyPromotedImpact(current_session, projectile),
    }
}

fn advanceLevel1WallNormal(
    current_session: *runtime_session.Session,
    projectile: *runtime_session.MagicBallProjectile,
) !void {
    switch (projectile.step_index) {
        0 => try applyBounce(current_session, projectile, .x),
        1 => try applyBounce(current_session, projectile, .y),
        2 => try applyBounce(current_session, projectile, .y),
        3 => try applyBounce(current_session, projectile, .x),
        4 => try applyReturnStarted(current_session, projectile),
        5 => try applyCleared(current_session, projectile.*),
        else => {},
    }
}

fn advanceFireWallNormal(
    current_session: *runtime_session.Session,
    projectile: *runtime_session.MagicBallProjectile,
) !void {
    switch (projectile.step_index) {
        0 => try applyBounce(current_session, projectile, .y),
        1 => try applyBounce(current_session, projectile, .y),
        2 => try applyBounce(current_session, projectile, .z),
        3 => try applyBounce(current_session, projectile, .x),
        4 => try applyCleared(current_session, projectile.*),
        else => {},
    }
}

fn applyBounce(
    current_session: *runtime_session.Session,
    projectile: *runtime_session.MagicBallProjectile,
    axis: runtime_session.MagicBallAxis,
) !void {
    switch (axis) {
        .x => projectile.vx = -projectile.vx,
        .y => projectile.vy = -projectile.vy,
        .z => projectile.vz = -projectile.vz,
    }
    projectile.origin_world_position = projectile.world_position;
    projectile.step_index += 1;
    try current_session.appendMagicBallProjectileEvent(.{
        .frame_index = current_session.frame_index,
        .kind = .bounce,
        .script = projectile.script,
        .sign_flip_axis = axis,
        .sprite_index = projectile.sprite_index,
        .world_position = projectile.world_position,
        .vx = projectile.vx,
        .vy = projectile.vy,
        .vz = projectile.vz,
    });
}

fn applyReturnStarted(
    current_session: *runtime_session.Session,
    projectile: *runtime_session.MagicBallProjectile,
) !void {
    projectile.phase = .returning;
    projectile.sprite_index = 12;
    projectile.flags = 32896;
    projectile.step_index += 1;
    try current_session.appendMagicBallProjectileEvent(.{
        .frame_index = current_session.frame_index,
        .kind = .return_started,
        .script = projectile.script,
        .sprite_index = projectile.sprite_index,
        .world_position = projectile.world_position,
        .vx = projectile.vx,
        .vy = projectile.vy,
        .vz = projectile.vz,
    });
}

fn applyCleared(
    current_session: *runtime_session.Session,
    projectile: runtime_session.MagicBallProjectile,
) !void {
    try current_session.appendMagicBallProjectileEvent(.{
        .frame_index = current_session.frame_index,
        .kind = .cleared,
        .script = projectile.script,
        .sprite_index = projectile.sprite_index,
        .world_position = projectile.world_position,
        .vx = projectile.vx,
        .vy = projectile.vy,
        .vz = projectile.vz,
    });
    current_session.clearMagicBallProjectiles();
}

fn applyPromotedImpact(
    current_session: *runtime_session.Session,
    projectile: *runtime_session.MagicBallProjectile,
) !void {
    try magic_ball_impacts.applyPromotedMagicBallImpact(current_session, projectile.*);
    try applyCleared(current_session, projectile.*);
}
