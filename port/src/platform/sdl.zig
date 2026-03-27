const std = @import("std");

const sdl = struct {
    pub const Window = opaque {};
    pub const Event = extern union {
        type: u32,
        padding: [56]u8,
    };

    pub extern fn SDL_Init(flags: u32) c_int;
    pub extern fn SDL_Quit() void;
    pub extern fn SDL_GetError() [*:0]const u8;
    pub extern fn SDL_CreateWindow(
        title: [*:0]const u8,
        x: c_int,
        y: c_int,
        w: c_int,
        h: c_int,
        flags: u32,
    ) ?*Window;
    pub extern fn SDL_DestroyWindow(window: *Window) void;
    pub extern fn SDL_WaitEvent(event: *Event) c_int;

    pub const SDL_INIT_VIDEO: u32 = 0x00000020;
    pub const SDL_QUIT: u32 = 0x00000100;
    pub const SDL_WINDOW_SHOWN: u32 = 0x00000004;
    pub const SDL_WINDOWPOS_CENTERED: c_int = 0x2FFF0000;
};

pub fn runWindow(title: [*:0]const u8) !void {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) return error.SdlInitFailed;
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow(
        title,
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        960,
        540,
        sdl.SDL_WINDOW_SHOWN,
    ) orelse return error.SdlCreateWindowFailed;
    defer sdl.SDL_DestroyWindow(window);

    var event: sdl.Event = undefined;
    while (true) {
        if (sdl.SDL_WaitEvent(&event) == 0) return error.SdlWaitEventFailed;
        if (event.type == sdl.SDL_QUIT) break;
    }
}

pub fn lastError() []const u8 {
    return std.mem.span(sdl.SDL_GetError());
}
