pub const foundation = struct {
    pub const diagnostics = @import("foundation/diagnostics.zig");
    pub const paths = @import("foundation/paths.zig");
};

pub const platform = struct {
    pub const sdl = @import("platform/sdl.zig");
};

pub const assets = struct {
    pub const catalog = @import("assets/catalog.zig");
    pub const fixtures = @import("assets/fixtures.zig");
    pub const hqr = @import("assets/hqr.zig");
};

pub const tools = struct {
    pub const cli = @import("tools/cli.zig");
};

pub const ResolvedPaths = foundation.paths.ResolvedPaths;
pub const AssetCatalogEntry = assets.catalog.AssetCatalogEntry;
pub const HqrArchive = assets.hqr.HqrArchive;
pub const HqrEntry = assets.hqr.HqrEntry;
pub const FixtureManifestEntry = assets.fixtures.FixtureManifestEntry;

test {
    _ = @import("foundation/paths.zig");
    _ = @import("assets/catalog.zig");
    _ = @import("assets/hqr.zig");
    _ = @import("assets/fixtures.zig");
    _ = @import("tools/cli.zig");
}
