const fragment_compare = @import("fragment_compare.zig");
const render = @import("render.zig");
const sdl = @import("../../platform/sdl.zig");
const runtime_locomotion = @import("../../runtime/locomotion.zig");

pub const InteractionState = struct {
    control_mode: render.ControlMode,
    sidebar_tab: render.SidebarTab,
    zoom_level: render.ZoomLevel,
    view_mode: render.ViewMode,
    fragment_selection: fragment_compare.FragmentComparisonSelection,
};

pub const PostKeyAction = enum {
    none,
    advance_world,
    apply_validation_zone_effects,
};

pub const KeyDownResult = struct {
    interaction: InteractionState,
    locomotion_status: runtime_locomotion.LocomotionStatus,
    should_print_locomotion_diagnostic: bool = false,
    post_key_action: PostKeyAction = .none,
};

pub fn initialInteractionState(catalog: fragment_compare.FragmentComparisonCatalog) InteractionState {
    const fragment_selection = fragment_compare.initialFragmentComparisonSelection(catalog);
    return .{
        .control_mode = if (fragment_selection.focus == null) .locomotion else .fragment_navigation,
        .sidebar_tab = .info,
        .zoom_level = .fit,
        .view_mode = .isometric,
        .fragment_selection = fragment_selection,
    };
}

pub fn zoomIn(zoom_level: render.ZoomLevel) render.ZoomLevel {
    return switch (zoom_level) {
        .fit => .room,
        .room => .detail,
        .detail => .detail,
    };
}

pub fn zoomOut(zoom_level: render.ZoomLevel) render.ZoomLevel {
    return switch (zoom_level) {
        .fit => .fit,
        .room => .fit,
        .detail => .room,
    };
}

pub fn stepRankedFragmentComparisonSelection(
    catalog: fragment_compare.FragmentComparisonCatalog,
    selection: fragment_compare.FragmentComparisonSelection,
    delta: i32,
) fragment_compare.FragmentComparisonSelection {
    return fragment_compare.stepRankedSelection(catalog, selection, delta);
}

pub fn stepCellFragmentComparisonSelection(
    catalog: fragment_compare.FragmentComparisonCatalog,
    selection: fragment_compare.FragmentComparisonSelection,
    delta: i32,
) fragment_compare.FragmentComparisonSelection {
    return fragment_compare.stepCellSelection(catalog, selection, delta);
}

pub fn handleInteractionKeyDown(
    catalog: fragment_compare.FragmentComparisonCatalog,
    interaction: InteractionState,
    locomotion_status: runtime_locomotion.LocomotionStatus,
    key: sdl.Key,
) ?KeyDownResult {
    switch (key) {
        .tab => {
            if (interaction.fragment_selection.focus == null) {
                return .{
                    .interaction = interaction,
                    .locomotion_status = locomotion_status,
                };
            }

            return .{
                .interaction = .{
                    .control_mode = switch (interaction.control_mode) {
                        .locomotion => .fragment_navigation,
                        .fragment_navigation => .locomotion,
                    },
                    .sidebar_tab = interaction.sidebar_tab,
                    .zoom_level = interaction.zoom_level,
                    .view_mode = interaction.view_mode,
                    .fragment_selection = interaction.fragment_selection,
                },
                .locomotion_status = locomotion_status,
            };
        },
        .left, .right, .up, .down => {
            if (interaction.control_mode != .fragment_navigation or interaction.fragment_selection.focus == null) {
                return null;
            }

            const next_fragment_selection = switch (key) {
                .left => stepRankedFragmentComparisonSelection(catalog, interaction.fragment_selection, -1),
                .right => stepRankedFragmentComparisonSelection(catalog, interaction.fragment_selection, 1),
                .up => stepCellFragmentComparisonSelection(catalog, interaction.fragment_selection, -1),
                .down => stepCellFragmentComparisonSelection(catalog, interaction.fragment_selection, 1),
                else => unreachable,
            };

            return .{
                .interaction = .{
                    .control_mode = interaction.control_mode,
                    .sidebar_tab = interaction.sidebar_tab,
                    .zoom_level = interaction.zoom_level,
                    .view_mode = interaction.view_mode,
                    .fragment_selection = next_fragment_selection,
                },
                .locomotion_status = locomotion_status,
            };
        },
        .c => {
            return .{
                .interaction = .{
                    .control_mode = interaction.control_mode,
                    .sidebar_tab = switch (interaction.sidebar_tab) {
                        .info => .controls,
                        .controls => .info,
                    },
                    .zoom_level = interaction.zoom_level,
                    .view_mode = interaction.view_mode,
                    .fragment_selection = interaction.fragment_selection,
                },
                .locomotion_status = locomotion_status,
            };
        },
        .v => {
            return .{
                .interaction = .{
                    .control_mode = interaction.control_mode,
                    .sidebar_tab = interaction.sidebar_tab,
                    .zoom_level = interaction.zoom_level,
                    .view_mode = switch (interaction.view_mode) {
                        .isometric => .grid,
                        .grid => .isometric,
                    },
                    .fragment_selection = interaction.fragment_selection,
                },
                .locomotion_status = locomotion_status,
            };
        },
        .zoom_in, .zoom_out, .zoom_reset => {
            return .{
                .interaction = .{
                    .control_mode = interaction.control_mode,
                    .sidebar_tab = interaction.sidebar_tab,
                    .zoom_level = switch (key) {
                        .zoom_in => zoomIn(interaction.zoom_level),
                        .zoom_out => zoomOut(interaction.zoom_level),
                        .zoom_reset => .fit,
                        else => unreachable,
                    },
                    .view_mode = interaction.view_mode,
                    .fragment_selection = interaction.fragment_selection,
                },
                .locomotion_status = locomotion_status,
            };
        },
        else => return null,
    }
}
