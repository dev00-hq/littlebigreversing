const std = @import("std");
const paths_mod = @import("foundation/paths.zig");
const scene_data = @import("game_data/scene.zig");
const life_program = @import("game_data/scene/life_program.zig");
const track_program = @import("game_data/scene/track_program.zig");
const room_state = @import("runtime/room_state.zig");
const runtime_session = @import("runtime/session.zig");
const runtime_update = @import("runtime/update.zig");

const LifeCompatibilityIssue = struct {
    kind: []const u8,
    offset: usize,
    opcode: []const u8,
    detail: []const u8,
};

const TrackCompatibilityIssue = struct {
    offset: usize,
    opcode: []const u8,
    detail: []const u8,
};

const ProbeReport = struct {
    scene_entry_index: usize,
    background_entry_index: usize,
    object_index: usize,
    admitted_seed_count: usize,
    admitted_seed_life_instruction_count: usize,
    admitted_seed_track_instruction_count: usize,
    runtime_tick_succeeded: bool,
    runtime_tick_error: ?[]const u8,
    runtime_updated_object_count: ?usize,
    first_incompatible_life_issue: ?LifeCompatibilityIssue,
    first_incompatible_track_issue: ?TrackCompatibilityIssue,
};

fn parseArgUsize(value: []const u8) !usize {
    return std.fmt.parseInt(usize, value, 10) catch return error.InvalidIntegerArgument;
}

fn writeReport(allocator: std.mem.Allocator, value: ProbeReport) !void {
    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(value);
    try std.fs.File.stdout().writeAll(out.written());
    try std.fs.File.stdout().writeAll("\n");
}

fn findSceneObjectByIndex(
    objects: []const scene_data.SceneObject,
    object_index: usize,
) ?scene_data.SceneObject {
    for (objects) |object| {
        if (object.index == object_index) return object;
    }
    return null;
}

fn syntheticSeedFromObject(
    allocator: std.mem.Allocator,
    object: scene_data.SceneObject,
) !room_state.ObjectBehaviorSeedSnapshot {
    const track_bytes = try allocator.dupe(u8, object.track.bytes);
    errdefer allocator.free(track_bytes);
    const track_instructions = try track_program.decodeTrackProgram(allocator, track_bytes);
    errdefer allocator.free(track_instructions);
    const life_bytes = try allocator.dupe(u8, object.life.bytes);
    errdefer allocator.free(life_bytes);
    const life_instructions = try life_program.decodeLifeProgram(allocator, life_bytes);
    errdefer allocator.free(life_instructions);

    return .{
        .index = object.index,
        .sprite = object.sprite,
        .option_flags = object.option_flags,
        .bonus_quantity = std.math.cast(u8, object.bonus_count) orelse 0,
        .track_bytes = track_bytes,
        .track_instructions = track_instructions,
        .life_bytes = life_bytes,
        .life_instructions = life_instructions,
    };
}

fn supportedLifeOpcode(opcode: life_program.LifeOpcode) bool {
    return switch (opcode) {
        .LM_IF,
        .LM_AND_IF,
        .LM_ELSE,
        .LM_SET_TRACK,
        .LM_SET_VAR_CUBE,
        .LM_ADD_VAR_CUBE,
        .LM_SWIF,
        .LM_SNIF,
        .LM_GIVE_BONUS,
        .LM_END_COMPORTEMENT,
        .LM_END,
        => true,
        else => false,
    };
}

fn supportedLifeFunction(function: life_program.LifeFunction) bool {
    return switch (function) {
        .LF_HIT_BY,
        .LF_VAR_CUBE,
        .LF_L_TRACK,
        .LF_ZONE_OBJ,
        => true,
        else => false,
    };
}

fn firstLifeCompatibilityIssue(
    instructions: []const life_program.LifeInstruction,
) ?LifeCompatibilityIssue {
    for (instructions) |instruction| {
        if (!supportedLifeOpcode(instruction.opcode)) {
            return .{
                .kind = "unsupported_life_opcode",
                .offset = instruction.offset,
                .opcode = instruction.opcode.mnemonic(),
                .detail = "opcode is outside the current 19/19 runtime life interpreter allowlist",
            };
        }

        switch (instruction.opcode) {
            .LM_IF,
            .LM_AND_IF,
            .LM_SWIF,
            .LM_SNIF,
            => {
                const condition = switch (instruction.operands) {
                    .condition => |value| value,
                    else => return .{
                        .kind = "unsupported_life_operands",
                        .offset = instruction.offset,
                        .opcode = instruction.opcode.mnemonic(),
                        .detail = "instruction uses non-condition operands under the current interpreter assumptions",
                    },
                };
                if (!supportedLifeFunction(condition.function.function)) {
                    return .{
                        .kind = "unsupported_life_function",
                        .offset = instruction.offset,
                        .opcode = instruction.opcode.mnemonic(),
                        .detail = @tagName(condition.function.function),
                    };
                }
                if (condition.function.function == .LF_ZONE_OBJ) {
                    const object_operand = switch (condition.function.operands) {
                        .u8_value => |value| value,
                        else => return .{
                            .kind = "unsupported_life_function_operands",
                            .offset = instruction.offset,
                            .opcode = instruction.opcode.mnemonic(),
                            .detail = "LF_ZONE_OBJ uses non-u8 operands",
                        },
                    };
                    if (object_operand != 0) {
                        return .{
                            .kind = "unsupported_life_function_object_index",
                            .offset = instruction.offset,
                            .opcode = instruction.opcode.mnemonic(),
                            .detail = "LF_ZONE_OBJ is only implemented for object index 0 under the current interpreter",
                        };
                    }
                }
            },
            else => {},
        }
    }
    return null;
}

fn supportedTrackOpcode(opcode: track_program.TrackOpcode) bool {
    return switch (opcode) {
        .rem,
        .label,
        .sample,
        .sprite,
        .wait_nb_dizieme,
        .stop,
        .end,
        => true,
        else => false,
    };
}

fn firstTrackCompatibilityIssue(
    instructions: []const track_program.TrackInstruction,
) ?TrackCompatibilityIssue {
    for (instructions) |instruction| {
        if (!supportedTrackOpcode(instruction.opcode)) {
            return .{
                .offset = instruction.offset,
                .opcode = instruction.opcode.mnemonic(),
                .detail = "opcode is outside the current 19/19 runtime track interpreter allowlist",
            };
        }
    }
    return null;
}

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 4) {
        std.debug.print(
            "usage: zig run src\\sidequest_room_actor_seed_admission_probe.zig -- <scene-entry> <background-entry> <object-index>\n",
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

    const scene_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);
    var scene = try scene_data.loadSceneMetadata(allocator, scene_path, scene_entry_index);
    defer scene.deinit(allocator);

    const object = findSceneObjectByIndex(scene.objects, object_index) orelse return error.UnknownSceneObjectIndex;
    var seed = try syntheticSeedFromObject(allocator, object);
    defer seed.deinit(allocator);

    const synthetic_seeds = try allocator.alloc(room_state.ObjectBehaviorSeedSnapshot, 1);
    defer allocator.free(synthetic_seeds);
    synthetic_seeds[0] = seed;

    var session = try runtime_session.Session.initWithObjects(
        allocator,
        room_state.heroStartWorldPoint(&room),
        room.scene.objects,
        synthetic_seeds,
    );
    defer session.deinit(allocator);

    var seeded_room = room;
    seeded_room.scene.object_behavior_seeds = synthetic_seeds;

    var report = ProbeReport{
        .scene_entry_index = scene_entry_index,
        .background_entry_index = background_entry_index,
        .object_index = object_index,
        .admitted_seed_count = synthetic_seeds.len,
        .admitted_seed_life_instruction_count = seed.life_instructions.len,
        .admitted_seed_track_instruction_count = seed.track_instructions.len,
        .runtime_tick_succeeded = false,
        .runtime_tick_error = null,
        .runtime_updated_object_count = null,
        .first_incompatible_life_issue = firstLifeCompatibilityIssue(seed.life_instructions),
        .first_incompatible_track_issue = firstTrackCompatibilityIssue(seed.track_instructions),
    };

    const tick_result = runtime_update.tick(&seeded_room, &session) catch |err| {
        report.runtime_tick_error = @errorName(err);
        try writeReport(allocator, report);
        return;
    };

    report.runtime_tick_succeeded = true;
    report.runtime_updated_object_count = tick_result.updated_object_count;
    try writeReport(allocator, report);
}
