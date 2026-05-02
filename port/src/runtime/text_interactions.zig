const std = @import("std");

pub const TextInteractionOwner = enum {
    actor_conversation,
    actor_service_menu,
    ambient_bark,
    object_inspection,
    scripted_event_text,
    room_message_zone,
};

pub const TextCursorState = enum {
    hidden,
    visible,
};

pub const TextUiState = struct {
    owner: ?TextInteractionOwner = null,
    record_id: ?i16 = null,
    cursor_offset: ?usize = null,
    page_index: u8 = 0,

    pub fn hidden() TextUiState {
        return .{};
    }

    pub fn open(
        owner: TextInteractionOwner,
        record_id: ?i16,
        cursor_offset: ?usize,
    ) TextUiState {
        return .{
            .owner = owner,
            .record_id = record_id,
            .cursor_offset = cursor_offset,
            .page_index = 1,
        };
    }

    pub fn isVisible(self: TextUiState) bool {
        return self.owner != null;
    }

    pub fn cursorState(self: TextUiState) TextCursorState {
        return if (self.isVisible()) .visible else .hidden;
    }

    pub fn advancePage(self: *TextUiState, cursor_offset: ?usize) void {
        if (!self.isVisible()) return;
        self.cursor_offset = cursor_offset;
        self.page_index +|= 1;
    }

    pub fn close(self: *TextUiState) void {
        self.* = TextUiState.hidden();
    }
};

pub const ProvenFamily = struct {
    owner: TextInteractionOwner,
    requires_action_input: bool,
    requires_actor_target: bool,
    uses_choice_menu: bool,
    proximity_triggered: bool,
    has_durable_story_state_delta: bool,
};

const promoted_families = [_]ProvenFamily{
    .{
        .owner = .actor_conversation,
        .requires_action_input = true,
        .requires_actor_target = true,
        .uses_choice_menu = false,
        .proximity_triggered = false,
        .has_durable_story_state_delta = false,
    },
    .{
        .owner = .actor_service_menu,
        .requires_action_input = true,
        .requires_actor_target = true,
        .uses_choice_menu = true,
        .proximity_triggered = false,
        .has_durable_story_state_delta = false,
    },
    .{
        .owner = .ambient_bark,
        .requires_action_input = false,
        .requires_actor_target = false,
        .uses_choice_menu = false,
        .proximity_triggered = true,
        .has_durable_story_state_delta = false,
    },
    .{
        .owner = .object_inspection,
        .requires_action_input = true,
        .requires_actor_target = false,
        .uses_choice_menu = false,
        .proximity_triggered = false,
        .has_durable_story_state_delta = false,
    },
    .{
        .owner = .scripted_event_text,
        .requires_action_input = false,
        .requires_actor_target = false,
        .uses_choice_menu = false,
        .proximity_triggered = false,
        .has_durable_story_state_delta = true,
    },
};

pub fn promotedFamily(owner: TextInteractionOwner) ?ProvenFamily {
    for (promoted_families) |family| {
        if (family.owner == owner) return family;
    }
    return null;
}

test "text UI state separates visibility from dialog record identity" {
    var state = TextUiState.hidden();
    try std.testing.expect(!state.isVisible());
    try std.testing.expectEqual(TextCursorState.hidden, state.cursorState());
    try std.testing.expectEqual(@as(?i16, null), state.record_id);

    state = TextUiState.open(.object_inspection, 29, 34);
    try std.testing.expect(state.isVisible());
    try std.testing.expectEqual(TextCursorState.visible, state.cursorState());
    try std.testing.expectEqual(TextInteractionOwner.object_inspection, state.owner.?);
    try std.testing.expectEqual(@as(?i16, 29), state.record_id);
    try std.testing.expectEqual(@as(?usize, 34), state.cursor_offset);
    try std.testing.expectEqual(@as(u8, 1), state.page_index);

    state.advancePage(71);
    try std.testing.expectEqual(@as(?usize, 71), state.cursor_offset);
    try std.testing.expectEqual(@as(u8, 2), state.page_index);

    state.close();
    try std.testing.expect(!state.isVisible());
    try std.testing.expectEqual(@as(?TextInteractionOwner, null), state.owner);
    try std.testing.expectEqual(@as(?i16, null), state.record_id);
}

test "promoted text interaction families keep owner semantics distinct" {
    const actor = promotedFamily(.actor_conversation).?;
    try std.testing.expect(actor.requires_action_input);
    try std.testing.expect(actor.requires_actor_target);
    try std.testing.expect(!actor.uses_choice_menu);

    const service = promotedFamily(.actor_service_menu).?;
    try std.testing.expect(service.requires_actor_target);
    try std.testing.expect(service.uses_choice_menu);

    const bark = promotedFamily(.ambient_bark).?;
    try std.testing.expect(!bark.requires_action_input);
    try std.testing.expect(bark.proximity_triggered);

    const inspection = promotedFamily(.object_inspection).?;
    try std.testing.expect(inspection.requires_action_input);
    try std.testing.expect(!inspection.requires_actor_target);

    const event_text = promotedFamily(.scripted_event_text).?;
    try std.testing.expect(event_text.has_durable_story_state_delta);

    try std.testing.expectEqual(@as(?ProvenFamily, null), promotedFamily(.room_message_zone));
}
