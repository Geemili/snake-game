const std = @import("std");
const screen = @import("../screen.zig");
const Screen = screen.Screen;
const platform = @import("../platform.zig");
const Renderer = @import("../renderer.zig").Renderer;
const Component = platform.components.Component;

pub const MainMenu = struct {
    alloc: *std.mem.Allocator,
    screen: Screen,

    dirty: bool = true,
    play_pressed: bool = false,

    pub fn init(alloc: *std.mem.Allocator) !*@This() {
        const self = try alloc.create(@This());
        self.* = .{
            .alloc = alloc,
            .screen = .{
                .onEventFn = onEvent,
                .updateFn = update,
                .renderFn = render,
            },
        };
        return self;
    }

    pub fn onEvent(screenPtr: *Screen, event: platform.Event) void {
        const self = @fieldParentPtr(@This(), "screen", screenPtr);
        switch (event) {
            .Quit => platform.quit(),
            .ScreenResized => |screen_size| platform.glViewport(0, 0, screen_size.x, screen_size.y),
            .KeyDown => |ev| switch (ev.scancode) {
                .ESCAPE => platform.quit(),
                .Z => self.play_pressed = true,
                else => {},
            },
            else => {},
        }
    }

    pub fn update(screenPtr: *Screen, time: f64, delta: f64) ?screen.Transition {
        const self = @fieldParentPtr(@This(), "screen", screenPtr);

        if (self.play_pressed) {
            const game = screen.Game.init(self.alloc) catch unreachable;
            return screen.Transition{ .Replace = &game.screen };
        }

        return null;
    }

    pub fn render(screenPtr: *Screen, renderer: *Renderer, alpha: f64) void {
        const self = @fieldParentPtr(@This(), "screen", screenPtr);

        const text = platform.components.text;
        const box = platform.components.box;
        const vbox = platform.components.vbox;
        const button = platform.components.button;

        if (!self.dirty) return;

        platform.renderComponents(&vbox(
            &[_]Component{
                text("Snake Game"),
                box(.{ .grow = 1 }, &[_]Component{
                    vbox(&[_]Component{
                        button("Normal Play"),
                        button("Casual Play"),
                        button("Highscores"),
                    }),
                    text("Description"),
                }),
            },
        ));

        self.dirty = false;
    }
};
