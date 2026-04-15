pub const foundation = struct {
    pub const diagnostics = @import("foundation/diagnostics.zig");
    pub const paths = @import("foundation/paths.zig");
    pub const process = @import("foundation/process.zig");
};

pub const platform = struct {
    pub const sdl = @import("platform/sdl.zig");
};

pub const app = struct {
    pub const viewer_shell = @import("app/viewer_shell.zig");
};

pub const runtime = struct {
    pub const locomotion = @import("runtime/locomotion.zig");
    pub const object_behavior = @import("runtime/object_behavior.zig");
    pub const update = @import("runtime/update.zig");
    pub const world_geometry = @import("runtime/world_geometry.zig");
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
