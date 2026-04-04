const world_geometry = @import("../../runtime/world_geometry.zig");
const world_query = @import("../../runtime/world_query.zig");

pub fn gridCellWorldBounds(x: usize, z: usize) world_geometry.WorldBounds {
    return world_query.gridCellWorldBounds(x, z);
}
