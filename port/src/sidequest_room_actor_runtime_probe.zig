const std = @import("std");
const paths_mod = @import("foundation/paths.zig");
const room_state = @import("runtime/room_state.zig");
const runtime_session = @import("runtime/session.zig");
const runtime_update = @import("runtime/update.zig");

// Sidequest-only runtime falsification probe. This stays outside the CLI command
// set and exists only because standalone Zig files under top-level sidequest/
// cannot import the runtime modules directly under the current module-path rules.
const ProbeReport = struct {
    scene_entry_index: usize,
    background_entry_index: usize,
    object_index: usize,
    viewer_loadable: bool,
    object_behavior_seed_count: usize,
    target_has_behavior_seed: bool,
    target_seed_life_instruction_count: ?usize,
    target_seed_track_instruction_count: ?usize,
    session_has_behavior_state: bool,
    tick_succeeded: bool,
    tick_error: ?[]const u8,
    updated_object_count: ?usize,
    target_track_offset_before: ?i16,
    target_track_offset_after: ?i16,
    target_sprite_before: ?i16,
    target_sprite_after: ?i16,
    target_bonus_count_after: ?u8,
    emitted_bonus_event_count_after: ?usize,
};

fn parseArgUsize(value: []const u8) !usize {
    return std.fmt.parseInt(usize, value, 10) catch return error.InvalidIntegerArgument;
}

fn findSeed(
    seeds: []const room_state.ObjectBehaviorSeedSnapshot,
    object_index: usize,
) ?room_state.ObjectBehaviorSeedSnapshot {
    for (seeds) |seed| {
        if (seed.index == object_index) return seed;
    }
    return null;
}

fn writeReport(allocator: std.mem.Allocator, io: std.Io, value: ProbeReport) !void {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(value);
    try std.Io.File.stdout().writeStreamingAll(io, out.written());
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) {
        std.debug.print(
            "usage: zig run src\\sidequest_room_actor_runtime_probe.zig -- <scene-entry> <background-entry> <object-index>\n",
            .{},
        );
        return error.InvalidArguments;
    }

    const scene_entry_index = try parseArgUsize(args[1]);
    const background_entry_index = try parseArgUsize(args[2]);
    const object_index = try parseArgUsize(args[3]);

    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try room_state.loadRoomSnapshot(
        allocator,
        resolved,
        scene_entry_index,
        background_entry_index,
    );
    defer room.deinit(allocator);

    var session = try runtime_session.Session.initWithObjects(
        allocator,
        room_state.heroStartWorldPoint(&room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
    defer session.deinit(allocator);

    const seed = findSeed(room.scene.object_behavior_seeds, object_index);
    const before_behavior = session.objectBehaviorStateByIndex(object_index);

    var report = ProbeReport{
        .scene_entry_index = scene_entry_index,
        .background_entry_index = background_entry_index,
        .object_index = object_index,
        .viewer_loadable = true,
        .object_behavior_seed_count = room.scene.object_behavior_seeds.len,
        .target_has_behavior_seed = seed != null,
        .target_seed_life_instruction_count = if (seed) |value| value.life_instructions.len else null,
        .target_seed_track_instruction_count = if (seed) |value| value.track_instructions.len else null,
        .session_has_behavior_state = before_behavior != null,
        .tick_succeeded = false,
        .tick_error = null,
        .updated_object_count = null,
        .target_track_offset_before = if (before_behavior) |value| value.current_track_offset else null,
        .target_track_offset_after = null,
        .target_sprite_before = if (before_behavior) |value| value.current_sprite else null,
        .target_sprite_after = null,
        .target_bonus_count_after = null,
        .emitted_bonus_event_count_after = null,
    };

    const tick_result = runtime_update.tick(&room, &session) catch |err| {
        report.tick_error = @errorName(err);
        const after_behavior = session.objectBehaviorStateByIndex(object_index);
        report.target_track_offset_after = if (after_behavior) |value| value.current_track_offset else null;
        report.target_sprite_after = if (after_behavior) |value| value.current_sprite else null;
        report.target_bonus_count_after = if (after_behavior) |value| value.emitted_bonus_count else null;
        report.emitted_bonus_event_count_after = session.bonusSpawnEvents().len;
        try writeReport(allocator, init.io, report);
        return;
    };

    report.tick_succeeded = true;
    report.updated_object_count = tick_result.updated_object_count;
    const after_behavior = session.objectBehaviorStateByIndex(object_index);
    report.target_track_offset_after = if (after_behavior) |value| value.current_track_offset else null;
    report.target_sprite_after = if (after_behavior) |value| value.current_sprite else null;
    report.target_bonus_count_after = if (after_behavior) |value| value.emitted_bonus_count else null;
    report.emitted_bonus_event_count_after = session.bonusSpawnEvents().len;

    try writeReport(allocator, init.io, report);
}
