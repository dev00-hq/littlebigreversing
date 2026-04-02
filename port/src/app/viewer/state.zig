const room_state = @import("../../runtime/room_state.zig");

pub fn gridCellWorldBounds(x: usize, z: usize) room_state.WorldBounds {
    return room_state.gridCellWorldBounds(x, z);
}
