const render = @import("render.zig");

test "viewer render module exposes the debug renderer" {
    _ = render.renderDebugView;
}
