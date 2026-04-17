const reference_metadata = @import("../generated/reference_metadata.zig");
const room_state = @import("room_state.zig");
const runtime_session = @import("session.zig");

const sendell_scene_entry: usize = 36;
const sendell_background_entry: usize = 36;
const sendell_ball_flag_index: u8 = reference_metadata.sendell_ball_flag.index;
const lightning_spell_flag_index: u8 = reference_metadata.lightning_spell_flag.index;
const sendell_seed_magic_level: u8 = 2;

pub fn applyRoomEntryState(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) void {
    if (room.scene.entry_index != sendell_scene_entry or room.background.entry_index != sendell_background_entry) {
        return;
    }

    current_session.setMagicLevelAndRefill(sendell_seed_magic_level);
    current_session.setGameVar(sendell_ball_flag_index, 0);
    current_session.setGameVar(lightning_spell_flag_index, 1);
}
