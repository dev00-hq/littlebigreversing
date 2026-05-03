const std = @import("std");
const builtin = @import("builtin");

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
    pub const Keysym = extern struct {
        scancode: i32,
        sym: i32,
        mod: u16,
        unused: u32,
    };
    pub const KeyboardEvent = extern struct {
        type: u32,
        timestamp: u32,
        window_id: u32,
        state: u8,
        repeat: u8,
        padding2: u8,
        padding3: u8,
        keysym: Keysym,
    };
    pub const SdlEvent = extern union {
        type: u32,
        window: WindowEvent,
        key: KeyboardEvent,
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
    pub const SDL_KEYDOWN: u32 = 0x00000300;
    pub const SDL_WINDOWEVENT_EXPOSED: u8 = 3;
    pub const SDL_WINDOWEVENT_SIZE_CHANGED: u8 = 6;
    pub const SDLK_LEFT: i32 = 1073741904;
    pub const SDLK_RIGHT: i32 = 1073741903;
    pub const SDLK_UP: i32 = 1073741906;
    pub const SDLK_DOWN: i32 = 1073741905;
    pub const SDLK_RETURN: i32 = '\r';
    pub const SDLK_TAB: i32 = '\t';
    pub const SDLK_w: i32 = 'w';
    pub const SDLK_f: i32 = 'f';
    pub const SDLK_c: i32 = 'c';
    pub const SDLK_v: i32 = 'v';
    pub const SDLK_SPACE: i32 = ' ';
    pub const SDLK_PLUS: i32 = '+';
    pub const SDLK_EQUALS: i32 = '=';
    pub const SDLK_MINUS: i32 = '-';
    pub const SDLK_0: i32 = '0';
    pub const SDLK_1: i32 = '1';
    pub const SDLK_2: i32 = '2';
    pub const SDLK_3: i32 = '3';
    pub const SDLK_4: i32 = '4';
    pub const SDLK_PERIOD: i32 = '.';
    pub const SDLK_F5: i32 = 1073741886;
    pub const SDLK_F6: i32 = 1073741887;
    pub const SDLK_F7: i32 = 1073741888;
    pub const SDLK_F8: i32 = 1073741889;
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

pub const Key = enum {
    left,
    right,
    up,
    down,
    enter,
    tab,
    w,
    f,
    behavior_normal,
    behavior_sporty,
    behavior_aggressive,
    behavior_discreet,
    magic_ball_select,
    magic_ball_throw,
    c,
    v,
    space,
    proof_key_source,
    proof_key_pickup,
    proof_house_door,
    proof_cellar_return,
    zoom_in,
    zoom_out,
    zoom_reset,
};

pub const Event = union(enum) {
    quit,
    redraw,
    key_down: Key,
    other,
};

pub const TraceRectOp = struct {
    rect: Rect,
    color: Color,
};

pub const TraceLineOp = struct {
    x1: i32,
    y1: i32,
    x2: i32,
    y2: i32,
    color: Color,
};

pub const max_trace_text_len = 128;

pub const TraceTextOp = struct {
    rect: Rect,
    color: Color,
    scale: i32,
    text_len: usize,
    text: [max_trace_text_len]u8,
};

pub const TraceOp = union(enum) {
    clear: Color,
    draw_line: TraceLineOp,
    draw_rect: TraceRectOp,
    fill_rect: TraceRectOp,
    text: TraceTextOp,
    present: void,
};

pub const CanvasTrace = struct {
    ops: std.ArrayListUnmanaged(TraceOp) = .empty,

    pub fn deinit(self: *CanvasTrace, allocator: std.mem.Allocator) void {
        self.ops.deinit(allocator);
        self.* = .{};
    }

    fn append(self: *CanvasTrace, allocator: std.mem.Allocator, op: TraceOp) !void {
        try self.ops.append(allocator, op);
    }
};

pub const Canvas = struct {
    window: ?*sdl.Window,
    renderer: ?*sdl.Renderer,
    width: i32,
    height: i32,
    trace: ?*CanvasTrace = null,
    trace_allocator: ?std.mem.Allocator = null,

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

    pub fn initForTesting(
        allocator: std.mem.Allocator,
        width: i32,
        height: i32,
        trace: *CanvasTrace,
    ) Canvas {
        return .{
            .window = null,
            .renderer = null,
            .width = width,
            .height = height,
            .trace = trace,
            .trace_allocator = allocator,
        };
    }

    pub fn deinit(self: *Canvas) void {
        if (builtin.is_test) return;
        if (self.renderer) |renderer| sdl.SDL_DestroyRenderer(renderer);
        if (self.window) |window| sdl.SDL_DestroyWindow(window);
        sdl.SDL_Quit();
    }

    pub fn clear(self: *Canvas, color: Color) !void {
        if (builtin.is_test) {
            if (try self.traceOnly(.{ .clear = color })) return;
            unreachable;
        }
        try self.setColor(color);
        if (sdl.SDL_RenderClear(self.renderer.?) != 0) return error.SdlRenderClearFailed;
    }

    pub fn drawLine(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) !void {
        if (builtin.is_test) {
            if (try self.traceOnly(.{ .draw_line = .{
                .x1 = x1,
                .y1 = y1,
                .x2 = x2,
                .y2 = y2,
                .color = color,
            } })) return;
            unreachable;
        }
        try self.setColor(color);
        if (sdl.SDL_RenderDrawLine(self.renderer.?, x1, y1, x2, y2) != 0) return error.SdlRenderDrawLineFailed;
    }

    pub fn drawRect(self: *Canvas, rect: Rect, color: Color) !void {
        if (builtin.is_test) {
            if (try self.traceOnly(.{ .draw_rect = .{ .rect = rect, .color = color } })) return;
            unreachable;
        }
        try self.setColor(color);
        var sdl_rect = toSdlRect(rect);
        if (sdl.SDL_RenderDrawRect(self.renderer.?, &sdl_rect) != 0) return error.SdlRenderDrawRectFailed;
    }

    pub fn fillRect(self: *Canvas, rect: Rect, color: Color) !void {
        if (builtin.is_test) {
            if (try self.traceOnly(.{ .fill_rect = .{ .rect = rect, .color = color } })) return;
            unreachable;
        }
        try self.setColor(color);
        var sdl_rect = toSdlRect(rect);
        if (sdl.SDL_RenderFillRect(self.renderer.?, &sdl_rect) != 0) return error.SdlRenderFillRectFailed;
    }

    pub fn present(self: *Canvas) void {
        if (builtin.is_test) {
            _ = self.traceOnly(.{ .present = {} }) catch {};
            return;
        }
        sdl.SDL_RenderPresent(self.renderer.?);
    }

    pub fn traceText(self: *Canvas, rect: Rect, color: Color, scale: i32, text: []const u8) !void {
        if (!builtin.is_test) return;
        if (self.trace) |trace| {
            const clipped_len = @min(text.len, max_trace_text_len);
            var entry = TraceTextOp{
                .rect = rect,
                .color = color,
                .scale = scale,
                .text_len = clipped_len,
                .text = [_]u8{0} ** max_trace_text_len,
            };
            std.mem.copyForwards(u8, entry.text[0..clipped_len], text[0..clipped_len]);
            try trace.append(self.trace_allocator.?, .{ .text = entry });
        }
    }

    pub fn waitEvent(self: *Canvas) !Event {
        if (builtin.is_test) {
            _ = self;
            unreachable;
        }
        _ = self;

        var event: sdl.SdlEvent = undefined;
        if (sdl.SDL_WaitEvent(&event) == 0) return error.SdlWaitEventFailed;
        if (event.type == sdl.SDL_QUIT) return .quit;
        if (event.type == sdl.SDL_KEYDOWN) {
            return switch (event.key.keysym.sym) {
                sdl.SDLK_LEFT => .{ .key_down = .left },
                sdl.SDLK_RIGHT => .{ .key_down = .right },
                sdl.SDLK_UP => .{ .key_down = .up },
                sdl.SDLK_DOWN => .{ .key_down = .down },
                sdl.SDLK_RETURN => .{ .key_down = .enter },
                sdl.SDLK_TAB => .{ .key_down = .tab },
                sdl.SDLK_w => .{ .key_down = .w },
                sdl.SDLK_f => .{ .key_down = .f },
                sdl.SDLK_F5 => .{ .key_down = .behavior_normal },
                sdl.SDLK_F6 => .{ .key_down = .behavior_sporty },
                sdl.SDLK_F7 => .{ .key_down = .behavior_aggressive },
                sdl.SDLK_F8 => .{ .key_down = .behavior_discreet },
                sdl.SDLK_c => .{ .key_down = .c },
                sdl.SDLK_v => .{ .key_down = .v },
                sdl.SDLK_SPACE => .{ .key_down = .space },
                sdl.SDLK_1 => .{ .key_down = .magic_ball_select },
                sdl.SDLK_2 => .{ .key_down = .proof_key_pickup },
                sdl.SDLK_3 => .{ .key_down = .proof_house_door },
                sdl.SDLK_4 => .{ .key_down = .proof_cellar_return },
                sdl.SDLK_PERIOD => .{ .key_down = .magic_ball_throw },
                sdl.SDLK_PLUS, sdl.SDLK_EQUALS => .{ .key_down = .zoom_in },
                sdl.SDLK_MINUS => .{ .key_down = .zoom_out },
                sdl.SDLK_0 => .{ .key_down = .zoom_reset },
                else => .other,
            };
        }
        if (event.type == sdl.SDL_WINDOWEVENT) {
            if (event.window.event == sdl.SDL_WINDOWEVENT_EXPOSED or event.window.event == sdl.SDL_WINDOWEVENT_SIZE_CHANGED) {
                return .redraw;
            }
        }
        return .other;
    }

    fn setColor(self: *Canvas, color: Color) !void {
        if (builtin.is_test) return;
        if (sdl.SDL_SetRenderDrawColor(self.renderer.?, color.r, color.g, color.b, color.a) != 0) {
            return error.SdlSetRenderDrawColorFailed;
        }
    }

    fn traceOnly(self: *Canvas, op: TraceOp) !bool {
        if (self.trace) |trace| {
            try trace.append(self.trace_allocator.?, op);
            return true;
        }
        return false;
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
