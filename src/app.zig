const std = @import("std");
const platform = @import("platform.zig");

var x: i32 = 10;

pub fn onInit() void {
    platform.log("Hello, world!");
}

pub fn onEvent(event: platform.Event) void {
    switch (event) {
        .Quit => platform.quit = true,
        .KeyDown => |ev| if (ev.scancode == .ESCAPE) {
            platform.quit = true;
        },
        else => {},
    }
}

pub fn update(current_time: f64, delta: f64) void {
    x += @floatToInt(i32, 640 * delta);
}

pub fn render(alpha: f64) void {
    const screen_size = platform.getScreenSize();
    platform.clearRect(0, 0, screen_size.x, screen_size.y);

    platform.setFillStyle(100, 0, 0);
    platform.fillRect(x, 50, 50, 50);
}
