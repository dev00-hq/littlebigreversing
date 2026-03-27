const std = @import("std");

const sdl = struct {
    pub const Window = opaque {};
    pub const Renderer = opaque {};
    pub const SdlRect = extern struct {
        x: c_int,
        y: c_int,
        w: c_int,
        h: c_int,
    };
    pub const WindowEvent = extern struct {
        type: u32,
        timestamp: u32,
        window_id: u32,
        event: u8,
        padding1: u8,
        padding2: u8,
        padding3: u8,
        data1: i32,
        data2: i32,
    };
    pub const SdlEvent = extern union {
        type: u32,
        window: WindowEvent,
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
    pub extern fn SDL_CreateRenderer(window: *Window, index: c_int, flags: u32) ?*Renderer;
    pub extern fn SDL_DestroyRenderer(renderer: *Renderer) void;
    pub extern fn SDL_SetRenderDrawBlendMode(renderer: *Renderer, blend_mode: c_int) c_int;
    pub extern fn SDL_SetRenderDrawColor(renderer: *Renderer, r: u8, g: u8, b: u8, a: u8) c_int;
    pub extern fn SDL_RenderClear(renderer: *Renderer) c_int;
    pub extern fn SDL_RenderPresent(renderer: *Renderer) void;
    pub extern fn SDL_RenderDrawLine(renderer: *Renderer, x1: c_int, y1: c_int, x2: c_int, y2: c_int) c_int;
    pub extern fn SDL_RenderDrawRect(renderer: *Renderer, rect: *const SdlRect) c_int;
    pub extern fn SDL_RenderFillRect(renderer: *Renderer, rect: *const SdlRect) c_int;
    pub extern fn SDL_WaitEvent(event: *SdlEvent) c_int;

    pub const SDL_INIT_VIDEO: u32 = 0x00000020;
    pub const SDL_QUIT: u32 = 0x00000100;
    pub const SDL_WINDOWEVENT: u32 = 0x00000200;
    pub const SDL_WINDOWEVENT_EXPOSED: u8 = 3;
    pub const SDL_WINDOWEVENT_SIZE_CHANGED: u8 = 6;
    pub const SDL_WINDOW_SHOWN: u32 = 0x00000004;
    pub const SDL_WINDOWPOS_CENTERED: c_int = 0x2FFF0000;
    pub const SDL_RENDERER_ACCELERATED: u32 = 0x00000002;
    pub const SDL_RENDERER_PRESENTVSYNC: u32 = 0x00000004;
    pub const SDL_BLENDMODE_BLEND: c_int = 1;
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn inset(self: Rect, amount: i32) Rect {
        return .{
            .x = self.x + amount,
            .y = self.y + amount,
            .w = @max(1, self.w - (amount * 2)),
            .h = @max(1, self.h - (amount * 2)),
        };
    }

    pub fn right(self: Rect) i32 {
        return self.x + self.w - 1;
    }

    pub fn bottom(self: Rect) i32 {
        return self.y + self.h - 1;
    }
};

pub const Event = enum {
    quit,
    redraw,
    other,
};

pub const Canvas = struct {
    window: *sdl.Window,
    renderer: *sdl.Renderer,
    width: i32,
    height: i32,

    pub fn init(title: [*:0]const u8, width: i32, height: i32) !Canvas {
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) return error.SdlInitFailed;
        errdefer sdl.SDL_Quit();

        const window = sdl.SDL_CreateWindow(
            title,
            sdl.SDL_WINDOWPOS_CENTERED,
            sdl.SDL_WINDOWPOS_CENTERED,
            width,
            height,
            sdl.SDL_WINDOW_SHOWN,
        ) orelse return error.SdlCreateWindowFailed;
        errdefer sdl.SDL_DestroyWindow(window);

        const renderer = sdl.SDL_CreateRenderer(
            window,
            -1,
            sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC,
        ) orelse return error.SdlCreateRendererFailed;
        errdefer sdl.SDL_DestroyRenderer(renderer);

        if (sdl.SDL_SetRenderDrawBlendMode(renderer, sdl.SDL_BLENDMODE_BLEND) != 0) {
            return error.SdlSetRenderBlendModeFailed;
        }

        return .{
            .window = window,
            .renderer = renderer,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Canvas) void {
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }

    pub fn clear(self: *Canvas, color: Color) !void {
        try self.setColor(color);
        if (sdl.SDL_RenderClear(self.renderer) != 0) return error.SdlRenderClearFailed;
    }

    pub fn drawLine(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) !void {
        try self.setColor(color);
        if (sdl.SDL_RenderDrawLine(self.renderer, x1, y1, x2, y2) != 0) return error.SdlRenderDrawLineFailed;
    }

    pub fn drawRect(self: *Canvas, rect: Rect, color: Color) !void {
        try self.setColor(color);
        var sdl_rect = toSdlRect(rect);
        if (sdl.SDL_RenderDrawRect(self.renderer, &sdl_rect) != 0) return error.SdlRenderDrawRectFailed;
    }

    pub fn fillRect(self: *Canvas, rect: Rect, color: Color) !void {
        try self.setColor(color);
        var sdl_rect = toSdlRect(rect);
        if (sdl.SDL_RenderFillRect(self.renderer, &sdl_rect) != 0) return error.SdlRenderFillRectFailed;
    }

    pub fn present(self: *Canvas) void {
        sdl.SDL_RenderPresent(self.renderer);
    }

    pub fn waitEvent(self: *Canvas) !Event {
        _ = self;

        var event: sdl.SdlEvent = undefined;
        if (sdl.SDL_WaitEvent(&event) == 0) return error.SdlWaitEventFailed;
        if (event.type == sdl.SDL_QUIT) return .quit;
        if (event.type == sdl.SDL_WINDOWEVENT) {
            if (event.window.event == sdl.SDL_WINDOWEVENT_EXPOSED or event.window.event == sdl.SDL_WINDOWEVENT_SIZE_CHANGED) {
                return .redraw;
            }
        }
        return .other;
    }

    fn setColor(self: *Canvas, color: Color) !void {
        if (sdl.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a) != 0) {
            return error.SdlSetRenderDrawColorFailed;
        }
    }
};

fn toSdlRect(rect: Rect) sdl.SdlRect {
    return .{
        .x = rect.x,
        .y = rect.y,
        .w = rect.w,
        .h = rect.h,
    };
}

pub fn lastError() []const u8 {
    return std.mem.span(sdl.SDL_GetError());
}
