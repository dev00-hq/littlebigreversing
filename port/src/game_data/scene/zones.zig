const std = @import("std");

const zone_init_on_mask = 1;
const zone_obligatory_mask = 8;

pub const ZoneType = enum(i16) {
    change_cube = 0,
    camera = 1,
    scenario = 2,
    grm = 3,
    giver = 4,
    message = 5,
    ladder = 6,
    escalator = 7,
    hit = 8,
    rail = 9,

    pub fn name(self: ZoneType) []const u8 {
        return @tagName(self);
    }
};

pub const MessageDirection = enum(i32) {
    north = 1,
    south = 2,
    east = 4,
    west = 8,

    pub fn name(self: MessageDirection) []const u8 {
        return @tagName(self);
    }
};

pub const EscalatorDirection = enum(i32) {
    north = 1,
    south = 2,
    east = 4,
    west = 8,

    pub fn name(self: EscalatorDirection) []const u8 {
        return @tagName(self);
    }
};

pub const GiverBonusKinds = struct {
    money: bool,
    life: bool,
    magic: bool,
    key: bool,
    clover: bool,

    pub fn fromFlags(flags: i32) GiverBonusKinds {
        return .{
            .money = (flags & (1 << 4)) != 0,
            .life = (flags & (1 << 5)) != 0,
            .magic = (flags & (1 << 6)) != 0,
            .key = (flags & (1 << 7)) != 0,
            .clover = (flags & (1 << 8)) != 0,
        };
    }
};

pub const ChangeCubeSemantics = struct {
    destination_cube: i16,
    destination_x: i32,
    destination_y: i32,
    destination_z: i32,
    yaw: i32,
    test_brick: bool,
    dont_readjust_twinsen: bool,
    initially_on: bool,
};

pub const CameraSemantics = struct {
    anchor_x: i32,
    anchor_y: i32,
    anchor_z: i32,
    alpha: ?i32,
    beta: ?i32,
    gamma: ?i32,
    distance: ?i32,
    initially_on: bool,
    obligatory: bool,
};

pub const GrmSemantics = struct {
    grm_index: i32,
    initially_on: bool,
};

pub const GiverSemantics = struct {
    bonus_kinds: GiverBonusKinds,
    quantity: i32,
    already_taken: bool,
};

pub const MessageSemantics = struct {
    dialog_id: i16,
    linked_camera_zone_id: ?i32,
    facing_direction: MessageDirection,
};

pub const LadderSemantics = struct {
    enabled_on_load: bool,
};

pub const EscalatorSemantics = struct {
    enabled: bool,
    direction: EscalatorDirection,
};

pub const HitSemantics = struct {
    damage: i32,
    cooldown_raw_value: i32,
    initial_timer: i32,
};

pub const RailSemantics = struct {
    switch_state_on_load: bool,
};

pub const ZoneSemantics = union(ZoneType) {
    change_cube: ChangeCubeSemantics,
    camera: CameraSemantics,
    scenario: void,
    grm: GrmSemantics,
    giver: GiverSemantics,
    message: MessageSemantics,
    ladder: LadderSemantics,
    escalator: EscalatorSemantics,
    hit: HitSemantics,
    rail: RailSemantics,

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("kind");
        try jws.write(@tagName(std.meta.activeTag(self)));

        switch (self) {
            .change_cube => |semantics| {
                try jws.objectField("destination_cube");
                try jws.write(semantics.destination_cube);
                try jws.objectField("destination_x");
                try jws.write(semantics.destination_x);
                try jws.objectField("destination_y");
                try jws.write(semantics.destination_y);
                try jws.objectField("destination_z");
                try jws.write(semantics.destination_z);
                try jws.objectField("yaw");
                try jws.write(semantics.yaw);
                try jws.objectField("test_brick");
                try jws.write(semantics.test_brick);
                try jws.objectField("dont_readjust_twinsen");
                try jws.write(semantics.dont_readjust_twinsen);
                try jws.objectField("initially_on");
                try jws.write(semantics.initially_on);
            },
            .camera => |semantics| {
                try jws.objectField("anchor_x");
                try jws.write(semantics.anchor_x);
                try jws.objectField("anchor_y");
                try jws.write(semantics.anchor_y);
                try jws.objectField("anchor_z");
                try jws.write(semantics.anchor_z);
                try jws.objectField("alpha");
                try jws.write(semantics.alpha);
                try jws.objectField("beta");
                try jws.write(semantics.beta);
                try jws.objectField("gamma");
                try jws.write(semantics.gamma);
                try jws.objectField("distance");
                try jws.write(semantics.distance);
                try jws.objectField("initially_on");
                try jws.write(semantics.initially_on);
                try jws.objectField("obligatory");
                try jws.write(semantics.obligatory);
            },
            .scenario => {},
            .grm => |semantics| {
                try jws.objectField("grm_index");
                try jws.write(semantics.grm_index);
                try jws.objectField("initially_on");
                try jws.write(semantics.initially_on);
            },
            .giver => |semantics| {
                try jws.objectField("bonus_kinds");
                try jws.write(semantics.bonus_kinds);
                try jws.objectField("quantity");
                try jws.write(semantics.quantity);
                try jws.objectField("already_taken");
                try jws.write(semantics.already_taken);
            },
            .message => |semantics| {
                try jws.objectField("dialog_id");
                try jws.write(semantics.dialog_id);
                try jws.objectField("linked_camera_zone_id");
                try jws.write(semantics.linked_camera_zone_id);
                try jws.objectField("facing_direction");
                try jws.write(semantics.facing_direction.name());
            },
            .ladder => |semantics| {
                try jws.objectField("enabled_on_load");
                try jws.write(semantics.enabled_on_load);
            },
            .escalator => |semantics| {
                try jws.objectField("enabled");
                try jws.write(semantics.enabled);
                try jws.objectField("direction");
                try jws.write(semantics.direction.name());
            },
            .hit => |semantics| {
                try jws.objectField("damage");
                try jws.write(semantics.damage);
                try jws.objectField("cooldown_raw_value");
                try jws.write(semantics.cooldown_raw_value);
                try jws.objectField("initial_timer");
                try jws.write(semantics.initial_timer);
            },
            .rail => |semantics| {
                try jws.objectField("switch_state_on_load");
                try jws.write(semantics.switch_state_on_load);
            },
        }

        try jws.endObject();
    }
};

pub const SceneZone = struct {
    x0: i32,
    y0: i32,
    z0: i32,
    x1: i32,
    y1: i32,
    z1: i32,
    raw_info: [8]i32,
    zone_type: ZoneType,
    num: i16,
    semantics: ZoneSemantics,

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("x0");
        try jws.write(self.x0);
        try jws.objectField("y0");
        try jws.write(self.y0);
        try jws.objectField("z0");
        try jws.write(self.z0);
        try jws.objectField("x1");
        try jws.write(self.x1);
        try jws.objectField("y1");
        try jws.write(self.y1);
        try jws.objectField("z1");
        try jws.write(self.z1);
        try jws.objectField("raw_info");
        try jws.write(self.raw_info);
        try jws.objectField("zone_type");
        try jws.write(self.zone_type.name());
        try jws.objectField("num");
        try jws.write(self.num);
        try jws.objectField("semantics");
        try jws.write(self.semantics);
        try jws.endObject();
    }
};

pub const RawSceneZone = struct {
    x0: i32,
    y0: i32,
    z0: i32,
    x1: i32,
    y1: i32,
    z1: i32,
    raw_info: [8]i32,
    type_id: i16,
    num: i16,
};

pub fn decodeZone(raw_zone: RawSceneZone, cube_mode: u8) !SceneZone {
    const zone_type = try decodeZoneType(raw_zone.type_id);
    return .{
        .x0 = raw_zone.x0,
        .y0 = raw_zone.y0,
        .z0 = raw_zone.z0,
        .x1 = raw_zone.x1,
        .y1 = raw_zone.y1,
        .z1 = raw_zone.z1,
        .raw_info = raw_zone.raw_info,
        .zone_type = zone_type,
        .num = raw_zone.num,
        .semantics = switch (zone_type) {
            .change_cube => .{ .change_cube = .{
                .destination_cube = raw_zone.num,
                .destination_x = raw_zone.raw_info[0],
                .destination_y = raw_zone.raw_info[1],
                .destination_z = raw_zone.raw_info[2],
                .yaw = raw_zone.raw_info[3],
                .test_brick = (raw_zone.raw_info[5] & zone_init_on_mask) != 0,
                .dont_readjust_twinsen = (raw_zone.raw_info[6] & zone_init_on_mask) != 0,
                .initially_on = (raw_zone.raw_info[7] & zone_init_on_mask) != 0,
            } },
            .camera => .{ .camera = .{
                .anchor_x = raw_zone.raw_info[0],
                .anchor_y = raw_zone.raw_info[1],
                .anchor_z = raw_zone.raw_info[2],
                .alpha = if (cube_mode == 1) raw_zone.raw_info[3] else null,
                .beta = if (cube_mode == 1) raw_zone.raw_info[4] else null,
                .gamma = if (cube_mode == 1) raw_zone.raw_info[5] else null,
                .distance = if (cube_mode == 1) raw_zone.raw_info[6] else null,
                .initially_on = (raw_zone.raw_info[7] & zone_init_on_mask) != 0,
                .obligatory = (raw_zone.raw_info[7] & zone_obligatory_mask) != 0,
            } },
            .scenario => .scenario,
            .grm => .{ .grm = .{
                .grm_index = raw_zone.raw_info[0],
                .initially_on = raw_zone.raw_info[2] != 0,
            } },
            .giver => .{ .giver = .{
                .bonus_kinds = GiverBonusKinds.fromFlags(raw_zone.raw_info[0]),
                .quantity = raw_zone.raw_info[1],
                .already_taken = false,
            } },
            .message => .{ .message = .{
                .dialog_id = raw_zone.num,
                .linked_camera_zone_id = if (raw_zone.raw_info[1] == 0) null else raw_zone.raw_info[1],
                .facing_direction = try decodeMessageDirection(raw_zone.raw_info[2]),
            } },
            .ladder => .{ .ladder = .{
                .enabled_on_load = raw_zone.raw_info[0] != 0,
            } },
            .escalator => .{ .escalator = .{
                .enabled = raw_zone.raw_info[1] != 0,
                .direction = try decodeEscalatorDirection(raw_zone.raw_info[2]),
            } },
            .hit => .{ .hit = .{
                .damage = raw_zone.raw_info[1],
                .cooldown_raw_value = raw_zone.raw_info[2],
                .initial_timer = 0,
            } },
            .rail => .{ .rail = .{
                .switch_state_on_load = raw_zone.raw_info[0] != 0,
            } },
        },
    };
}

fn decodeZoneType(type_id: i16) !ZoneType {
    return switch (type_id) {
        0 => .change_cube,
        1 => .camera,
        2 => .scenario,
        3 => .grm,
        4 => .giver,
        5 => .message,
        6 => .ladder,
        7 => .escalator,
        8 => .hit,
        9 => .rail,
        else => error.UnsupportedSceneZoneType,
    };
}

fn decodeMessageDirection(raw_value: i32) !MessageDirection {
    return switch (raw_value) {
        1 => .north,
        2 => .south,
        4 => .east,
        8 => .west,
        else => error.UnsupportedSceneZoneMessageDirection,
    };
}

fn decodeEscalatorDirection(raw_value: i32) !EscalatorDirection {
    return switch (raw_value) {
        1 => .north,
        2 => .south,
        4 => .east,
        8 => .west,
        else => error.UnsupportedSceneZoneEscalatorDirection,
    };
}
