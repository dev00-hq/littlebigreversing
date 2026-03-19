const model = @import("scene/model.zig");
const parser = @import("scene/parser.zig");
const zones = @import("scene/zones.zig");

pub const AmbientSample = model.AmbientSample;
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

test {
    _ = @import("scene/tests.zig");
}
