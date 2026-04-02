pub const foundation = struct {
    pub const diagnostics = @import("foundation/diagnostics.zig");
    pub const paths = @import("foundation/paths.zig");
};

pub const platform = struct {
    pub const sdl = @import("platform/sdl.zig");
};

pub const app = struct {
    pub const viewer_shell = @import("app/viewer_shell.zig");
};

pub const runtime = struct {
    pub const room_state = @import("runtime/room_state.zig");
    pub const session = @import("runtime/session.zig");
    pub const world_query = @import("runtime/world_query.zig");
};

pub const assets = struct {
    pub const catalog = @import("assets/catalog.zig");
    pub const fixtures = @import("assets/fixtures.zig");
    pub const hqr = @import("assets/hqr.zig");
};

pub const game_data = struct {
    pub const background = @import("game_data/background.zig");
    pub const scene = @import("game_data/scene.zig");
};

pub const tools = struct {
    pub const cli = @import("tools/cli.zig");
};

pub const ResolvedPaths = foundation.paths.ResolvedPaths;
pub const AssetCatalogEntry = assets.catalog.AssetCatalogEntry;
pub const HqrArchive = assets.hqr.HqrArchive;
pub const HqrEntry = assets.hqr.HqrEntry;
pub const FixtureManifestEntry = assets.fixtures.FixtureManifestEntry;
pub const BackgroundMetadata = game_data.background.BackgroundMetadata;
pub const SceneMetadata = game_data.scene.SceneMetadata;
pub const SceneZone = game_data.scene.SceneZone;
pub const ZoneType = game_data.scene.ZoneType;
pub const ZoneSemantics = game_data.scene.ZoneSemantics;
pub const MessageDirection = game_data.scene.MessageDirection;
pub const EscalatorDirection = game_data.scene.EscalatorDirection;
pub const GiverBonusKinds = game_data.scene.GiverBonusKinds;

test {
    _ = @import("foundation/paths.zig");
    _ = @import("app/viewer_shell.zig");
    _ = @import("app/viewer_shell_test.zig");
    _ = @import("runtime/room_state.zig");
    _ = @import("runtime/session.zig");
    _ = @import("runtime/world_query.zig");
    _ = @import("app/viewer/state_test.zig");
    _ = @import("app/viewer/layout_test.zig");
    _ = @import("app/viewer/draw_test.zig");
    _ = @import("app/viewer/fragment_compare_test.zig");
    _ = @import("app/viewer/render_test.zig");
    _ = @import("assets/catalog.zig");
    _ = @import("assets/hqr.zig");
    _ = @import("assets/fixtures.zig");
    _ = @import("game_data/background.zig");
    _ = @import("game_data/scene.zig");
    _ = @import("tools/cli.zig");
}
