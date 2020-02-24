const app = @import("app.zig");
const constants = @import("constants.zig");
const platform = @import("platform.zig");

export const SCANCODE_ESCAPE = @enumToInt(platform.Scancode.ESCAPE);
export const SCANCODE_W = @enumToInt(platform.Scancode.W);
export const SCANCODE_A = @enumToInt(platform.Scancode.A);
export const SCANCODE_S = @enumToInt(platform.Scancode.S);
export const SCANCODE_D = @enumToInt(platform.Scancode.D);

export const MAX_DELTA_SECONDS = constants.MAX_DELTA_SECONDS;
export const TICK_DELTA_SECONDS = constants.TICK_DELTA_SECONDS;

export fn onInit() void {
    app.onInit();
}

export fn onMouseMove(x: i32, y: i32) void {
    app.onEvent(.{
        .MouseMotion = .{
            .x = x,
            .y = y,
        },
    });
}

export fn onKeyDown(scancode: u16) void {
    app.onEvent(.{
        .KeyDown = .{
            .scancode = @intToEnum(platform.Scancode, scancode),
        },
    });
}

export fn onResize() void {
    app.onEvent(.{
        .ScreenResized = platform.getScreenSize(),
    });
}

export fn update(current_time: f64, delta: f64) void {
    app.update(current_time, delta);
}

export fn render(alpha: f64) void {
    app.render(alpha);
}
