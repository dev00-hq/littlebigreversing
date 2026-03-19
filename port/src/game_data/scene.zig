const std = @import("std");
const model = @import("scene/model.zig");
const parser = @import("scene/parser.zig");
const zones = @import("scene/zones.zig");

pub const AmbientSample = model.AmbientSample;
pub const SceneProgramBlob = model.SceneProgramBlob;
pub const HeroStart = model.HeroStart;
pub const SceneObject = model.SceneObject;
pub const TrackPoint = model.TrackPoint;
pub const Patch = model.Patch;
pub const SceneMetadata = model.SceneMetadata;
pub const entryIndexToClassicLoaderSceneNumber = model.entryIndexToClassicLoaderSceneNumber;

pub const ZoneType = zones.ZoneType;
pub const MessageDirection = zones.MessageDirection;
pub const EscalatorDirection = zones.EscalatorDirection;
pub const GiverBonusKinds = zones.GiverBonusKinds;
pub const ChangeCubeSemantics = zones.ChangeCubeSemantics;
pub const CameraSemantics = zones.CameraSemantics;
pub const GrmSemantics = zones.GrmSemantics;
pub const GiverSemantics = zones.GiverSemantics;
pub const MessageSemantics = zones.MessageSemantics;
pub const LadderSemantics = zones.LadderSemantics;
pub const EscalatorSemantics = zones.EscalatorSemantics;
pub const HitSemantics = zones.HitSemantics;
pub const RailSemantics = zones.RailSemantics;
pub const ZoneSemantics = zones.ZoneSemantics;
pub const SceneZone = zones.SceneZone;

pub const loadSceneMetadata = parser.loadSceneMetadata;
pub const parseScenePayload = parser.parseScenePayload;

test "scene facade reexports the stable public API" {
    comptime {
        if (AmbientSample != model.AmbientSample) @compileError("AmbientSample facade drifted");
        if (SceneProgramBlob != model.SceneProgramBlob) @compileError("SceneProgramBlob facade drifted");
        if (HeroStart != model.HeroStart) @compileError("HeroStart facade drifted");
        if (SceneObject != model.SceneObject) @compileError("SceneObject facade drifted");
        if (TrackPoint != model.TrackPoint) @compileError("TrackPoint facade drifted");
        if (Patch != model.Patch) @compileError("Patch facade drifted");
        if (SceneMetadata != model.SceneMetadata) @compileError("SceneMetadata facade drifted");
        if (ZoneType != zones.ZoneType) @compileError("ZoneType facade drifted");
        if (MessageDirection != zones.MessageDirection) @compileError("MessageDirection facade drifted");
        if (EscalatorDirection != zones.EscalatorDirection) @compileError("EscalatorDirection facade drifted");
        if (GiverBonusKinds != zones.GiverBonusKinds) @compileError("GiverBonusKinds facade drifted");
        if (SceneZone != zones.SceneZone) @compileError("SceneZone facade drifted");
        if (ZoneSemantics != zones.ZoneSemantics) @compileError("ZoneSemantics facade drifted");
    }

    try std.testing.expectEqual(@as(?usize, 42), entryIndexToClassicLoaderSceneNumber(44));
}

test {
    _ = @import("scene/tests.zig");
}
