const room_state = @import("../../runtime/room_state.zig");
const world_query = @import("../../runtime/world_query.zig");

pub fn gridCellWorldBounds(x: usize, z: usize) room_state.WorldBounds {
    return world_query.gridCellWorldBounds(x, z);
}
