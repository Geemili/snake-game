const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
usingnamespace @import("constants.zig");
const Vec2f = platform.Vec2f;
const pi = std.math.pi;
const Renderer = @import("renderer.zig").Renderer;
const ring_buffer = @import("ring_buffer.zig");
const RingBuffer = ring_buffer.RingBuffer;

var renderer: Renderer = undefined;

var camera_pos = Vec2f{ .x = 0, .y = 0 };
var target_head_dir: f32 = 0;
var head_segment = Segment{
    .pos = Vec2f{ .x = 100, .y = 100 },
    .size = Vec2f{ .x = SNAKE_SEGMENT_LENGTH, .y = SNAKE_HEAD_WIDTH },
    .dir = 0,
};
var segments = [_]?Segment{null} ** MAX_SEGMENTS;
var next_segment_idx: usize = 0;
var tail_segment = Segment{
    .pos = Vec2f{ .x = 100, .y = 100 },
    .size = Vec2f{ .x = SNAKE_TAIL_LENGTH, .y = SNAKE_TAIL_WIDTH },
    .dir = 0,
};
var frames: usize = 0;

const PastPosition = struct { time: f64, pos: Vec2f, dir: f32 };
var position_history_buffer = [_]PastPosition{.{ .time = 0, .pos = .{ .x = 100, .y = 100 }, .dir = 0 }} ** HISTORY_BUFFER_SIZE;
var position_history = RingBuffer(PastPosition).init(position_history_buffer[0..]);

var random: std.rand.DefaultPrng = undefined;
var food_pos: ?Vec2f = null;

var inputs = Inputs{};

/// Keep track of D-Pad status
const Inputs = struct {
    north: bool = false,
    east: bool = false,
    south: bool = false,
    west: bool = false,
};

const Segment = struct {
    pos: Vec2f,
    size: Vec2f,

    /// In radians
    dir: f32,

    pub fn render(self: *const @This(), render_buffer: *Renderer, color: platform.Color) void {
        render_buffer.pushRect(self.pos, self.size, color, self.dir);
    }
};

pub fn onInit() void {
    renderer = Renderer.init();

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        addSegment();
    }

    random = std.rand.DefaultPrng.init(1337);
}

pub fn onEvent(event: platform.Event) void {
    switch (event) {
        .Quit => platform.quit(),
        .ScreenResized => |screen_size| platform.glViewport(0, 0, screen_size.x, screen_size.y),
        .KeyDown => |ev| switch (ev.scancode) {
            .ESCAPE => platform.quit(),
            .UP => inputs.north = true,
            .RIGHT => inputs.east = true,
            .DOWN => inputs.south = true,
            .LEFT => inputs.west = true,
            else => {},
        },
        .KeyUp => |ev| switch (ev.scancode) {
            .UP => inputs.north = false,
            .RIGHT => inputs.east = false,
            .DOWN => inputs.south = false,
            .LEFT => inputs.west = false,
            else => {},
        },
        else => {},
    }
}

pub fn update(current_time: f64, delta: f64) void {
    // Update food
    if (food_pos) |pos| {
        // If the head is close to the fruit
        if (pos.sub(&head_segment.pos).magnitude() < (SNAKE_SEGMENT_LENGTH + 20) / 2) {
            // Eat it
            food_pos = null;
            addSegment();
        }
    } else {
        food_pos = .{
            .x = LEVEL_OFFSET_X + random.random.float(f32) * LEVEL_WIDTH - LEVEL_WIDTH / 2,
            .y = LEVEL_OFFSET_Y + random.random.float(f32) * LEVEL_HEIGHT - LEVEL_HEIGHT / 2,
        };
    }

    // Update target angle from key inputs
    var target_head_dir_vec: Vec2f = .{ .x = 0, .y = 0 };
    if (inputs.north) target_head_dir_vec.y -= 1;
    if (inputs.south) target_head_dir_vec.y += 1;
    if (inputs.east) target_head_dir_vec.x += 1;
    if (inputs.west) target_head_dir_vec.x -= 1;
    if (target_head_dir_vec.x != 0 or target_head_dir_vec.y != 0) {
        target_head_dir = std.math.atan2(f32, target_head_dir_vec.y, target_head_dir_vec.x);
    }

    // Turn head
    const angle_difference = @mod(((target_head_dir - head_segment.dir) + pi), 2 * pi) - pi;
    const angle_change = std.math.clamp(angle_difference, @floatCast(f32, -SNAKE_TURN_SPEED * delta), @floatCast(f32, SNAKE_TURN_SPEED * delta));
    head_segment.dir += angle_change;
    if (head_segment.dir >= 2 * pi) {
        head_segment.dir -= 2 * pi;
    } else if (head_segment.dir < 0) {
        head_segment.dir += 2 * pi;
    }

    // Move head
    const head_speed = @floatCast(f32, SNAKE_SPEED * delta);
    const head_movement = Vec2f.unitFromRad(head_segment.dir).scalMul(head_speed);
    head_segment.pos = head_segment.pos.add(&head_movement);

    // Track where the head has been
    position_history.push(.{ .time = @floatCast(f32, current_time), .pos = head_segment.pos, .dir = head_segment.dir }) catch builtin.panic("failed to push to position history buffer", null);

    // Make camera follow snake head
    const screen_size = Vec2f{ .x = VIEWPORT_WIDTH, .y = VIEWPORT_HEIGHT };
    camera_pos = head_segment.pos.sub(&screen_size.scalMul(0.5));

    // Make segments trail head
    var segment_idx: usize = 0;
    var position_history_idx: usize = position_history.len() - 1;
    var prev_segment = &head_segment;
    while (prev_segment != &tail_segment) : (segment_idx += 1) {
        var cur_segment = if (segments[segment_idx] != null) &segments[segment_idx].? else &tail_segment;

        var dist_from_prev: f32 = undefined;
        if (cur_segment != &tail_segment) {
            dist_from_prev = SNAKE_SEGMENT_LENGTH;
        } else {
            dist_from_prev = SNAKE_TAIL_LENGTH / 2 + SNAKE_SEGMENT_LENGTH / 2;
        }

        const time_offset = @intToFloat(f64, segment_idx + 1) * SEGMENT_TIME_OFFSET;
        const segment_time = current_time - time_offset;
        var hist_pos_opt: ?PastPosition = null;
        while (position_history_idx > 0) : (position_history_idx -= 1) {
            if (position_history.idx(position_history_idx - 1)) |hist_pos| {
                if (hist_pos.time < segment_time) {
                    hist_pos_opt = position_history.idx(position_history_idx);
                    break;
                }
            }
        }

        if (hist_pos_opt) |hist_pos| {
            cur_segment.pos = hist_pos.pos;
            cur_segment.dir = hist_pos.dir;
        }

        prev_segment = cur_segment;
    }

    frames += 1;
}

fn mulMat4(a: []const f32, b: []const f32) [16]f32 {
    std.debug.assert(a.len == 16);
    std.debug.assert(b.len == 16);

    var c: [16]f32 = undefined;
    comptime var i: usize = 0;
    inline while (i < 4) : (i += 1) {
        comptime var j: usize = 0;
        inline while (j < 4) : (j += 1) {
            c[i * 4 + j] = 0;
            comptime var k: usize = 0;
            inline while (k < 4) : (k += 1) {
                c[i * 4 + j] += a[i * 4 + k] * b[k * 4 + j];
            }
        }
    }
    return c;
}

pub fn render(alpha: f64) void {
    renderer.setTranslation(camera_pos);
    renderer.begin();

    renderer.pushRect(.{ .x = LEVEL_OFFSET_X, .y = LEVEL_OFFSET_Y }, .{ .x = LEVEL_WIDTH, .y = LEVEL_HEIGHT }, LEVEL_COLOR, 0);

    head_segment.render(&renderer, SEGMENT_COLORS[0]);

    var idx: usize = 0;
    while (segments[idx]) |segment| {
        segment.render(&renderer, SEGMENT_COLORS[(idx + 1) % SEGMENT_COLORS.len]);
        idx += 1;
    }
    tail_segment.render(&renderer, SEGMENT_COLORS[(idx + 1) % SEGMENT_COLORS.len]);

    if (food_pos) |pos| {
        renderer.pushRect(pos, .{ .x = FOOD_WIDTH, .y = FOOD_HEIGHT }, FOOD_COLOR, 0);
    }

    renderer.flush();
    platform.renderPresent();
}

fn addSegment() void {
    if (next_segment_idx == segments.len) {
        platform.warn("Ran out of space for snake segments\n", .{});
        return;
    }
    segments[next_segment_idx] = .{
        .pos = tail_segment.pos,
        .dir = tail_segment.dir,
        .size = .{ .x = SNAKE_SEGMENT_LENGTH, .y = SNAKE_SEGMENT_WIDTH },
    };
    next_segment_idx += 1;
}

test "" {
    std.meta.refAllDecls(ring_buffer);
}
