const std = @import("std");
const platform = @import("platform.zig");
usingnamespace @import("constants.zig");
const Vec2f = platform.Vec2f;
const pi = std.math.pi;

var camera_pos = Vec2f{ .x = 0, .y = 0 };
var target_head_dir: f32 = 0;
var head_segment = Segment{
    .pos = Vec2f{ .x = 100, .y = 100 },
    .dir = 0,
};
var segments = [_]?Segment{null} ** MAX_SEGMENTS;
var next_segment_idx: usize = 0;
var tail_segment = Segment{
    .pos = Vec2f{ .x = 100, .y = 100 },
    .dir = 0,
};
var frames: usize = 0;
var shader_program: platform.GLuint = undefined;
var vbo: platform.GLuint = undefined;
var ebo: platform.GLuint = undefined;
var projectionMatrixUniformLocation: platform.GLint = undefined;

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

    /// In radians
    dir: f32,
};

pub fn onInit() void {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        addSegment();
    }

    random = std.rand.DefaultPrng.init(1337);

    vbo = platform.glCreateBuffer();
    ebo = platform.glCreateBuffer();
    //vao = platform.glCreateVertexArrays();

    const vShaderSrc =
        \\ #version 300 es
        \\ layout(location = 0) in vec2 a_position;
        \\ layout(location = 1) in vec3 a_color;
        \\ uniform mat4 projectionMatrix;
        \\ out vec3 v_color;
        \\ void main() {
        \\   v_color = a_color;
        \\   gl_Position = vec4(a_position.x, a_position.y, 0.0, 1.0);
        \\   gl_Position *= projectionMatrix;
        \\ }
    ;
    const fShaderSrc =
        \\ #version 300 es
        \\ precision mediump float;
        \\ in vec3 v_color;
        \\ out vec4 o_fragColor;
        \\ void main() {
        \\   o_fragColor = vec4(v_color, 1.0);
        \\ }
    ;

    const vShader = platform.glCreateShader(platform.GL_VERTEX_SHADER);
    platform.setShaderSource(vShader, vShaderSrc);
    platform.glCompileShader(vShader);
    defer platform.glDeleteShader(vShader);

    if (!platform.getShaderCompileStatus(vShader)) {
        var infoLog: [512]u8 = [_]u8{0} ** 512;
        var infoLen: platform.GLsizei = 0;
        platform.glGetShaderInfoLog(vShader, infoLog.len, &infoLen, &infoLog);
        platform.warn("Error compiling vertex shader: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
    }

    const fShader = platform.glCreateShader(platform.GL_FRAGMENT_SHADER);
    platform.setShaderSource(fShader, fShaderSrc);
    platform.glCompileShader(fShader);
    defer platform.glDeleteShader(fShader);

    if (!platform.getShaderCompileStatus(vShader)) {
        var infoLog: [512]u8 = [_]u8{0} ** 512;
        var infoLen: platform.GLsizei = 0;
        platform.glGetShaderInfoLog(fShader, infoLog.len, &infoLen, &infoLog);
        platform.warn("Error compiling fragment shader: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
    }

    shader_program = platform.glCreateProgram();
    platform.glAttachShader(shader_program, vShader);
    platform.glAttachShader(shader_program, fShader);
    platform.glLinkProgram(shader_program);

    if (!platform.getProgramLinkStatus(shader_program)) {
        var infoLog: [512]u8 = [_]u8{0} ** 512;
        var infoLen: platform.GLsizei = 0;
        platform.glGetProgramInfoLog(shader_program, infoLog.len, &infoLen, &infoLog);
        platform.warn("Error linking shader program: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
    }

    platform.glUseProgram(shader_program);
    projectionMatrixUniformLocation = platform.glGetUniformLocation(shader_program, "projectionMatrix");
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
        if (pos.sub(&head_segment.pos).magnitude() < SNAKE_SEGMENT_LENGTH + 20) {
            // Eat it
            food_pos = null;
            addSegment();
        }
    } else {
        food_pos = .{
            .x = random.random.float(f32) * LEVEL_WIDTH - LEVEL_WIDTH / 2,
            .y = random.random.float(f32) * LEVEL_HEIGHT - LEVEL_HEIGHT / 2,
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

    // Make camera follow snake head
    const screen_size = Vec2f.fromVeci(&platform.getScreenSize());
    camera_pos = head_segment.pos.sub(&screen_size.scalMul(0.5));

    // Make segments trail head
    var segment_idx: usize = 0;
    var prev_segment = &head_segment;
    while (prev_segment != &tail_segment) : (segment_idx += 1) {
        var cur_segment = if (segments[segment_idx] != null) &segments[segment_idx].? else &tail_segment;

        var dist_from_prev: f32 = undefined;
        if (cur_segment != &tail_segment) {
            dist_from_prev = SNAKE_SEGMENT_LENGTH;
        } else {
            dist_from_prev = SNAKE_TAIL_LENGTH / 2 + SNAKE_SEGMENT_LENGTH / 2;
        }

        var vec_from_prev = cur_segment.pos.sub(&prev_segment.pos);
        if (vec_from_prev.magnitude() > dist_from_prev) {
            const dir_from_prev = vec_from_prev.normalize();
            const new_offset_from_prev = dir_from_prev.scalMul(dist_from_prev);

            cur_segment.dir = std.math.atan2(f32, dir_from_prev.y, dir_from_prev.x);
            cur_segment.pos = prev_segment.pos.add(&new_offset_from_prev);
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

const RenderBuffer = struct {
    const NUM_ATTR = 5;
    verts: [NUM_ATTR * 512]f32 = undefined,
    vertIdx: usize,
    indices: [2 * 3 * 512]platform.GLushort = undefined,
    indIdx: usize,
    translation: Vec2f = Vec2f{ .x = 0, .y = 0 },

    fn init() RenderBuffer {
        return .{
            .vertIdx = 0,
            .indIdx = 0,
        };
    }

    fn setTranslation(self: *RenderBuffer, vec: Vec2f) void {
        self.translation = vec;
    }

    fn pushVert(self: *RenderBuffer, pos: Vec2f, color: platform.Color) usize {
        const idx = self.vertIdx;
        defer self.vertIdx += 1;

        self.verts[idx * NUM_ATTR + 0] = pos.x;
        self.verts[idx * NUM_ATTR + 1] = pos.y;
        self.verts[idx * NUM_ATTR + 2] = @intToFloat(f32, color.r) / 255.0;
        self.verts[idx * NUM_ATTR + 3] = @intToFloat(f32, color.g) / 255.0;
        self.verts[idx * NUM_ATTR + 4] = @intToFloat(f32, color.b) / 255.0;
        return idx;
    }

    fn pushElem(self: *RenderBuffer, vertIdx: usize) void {
        self.indices[self.indIdx] = @intCast(platform.GLushort, vertIdx);
        defer self.indIdx += 1;
    }

    fn pushRect(self: *RenderBuffer, pos: Vec2f, size: Vec2f, color: platform.Color, rot: f32) void {
        const top_left = (Vec2f{ .x = -size.x / 2, .y = -size.y / 2 }).rotate(rot).add(&pos);
        const top_right = (Vec2f{ .x = size.x / 2, .y = -size.y / 2 }).rotate(rot).add(&pos);
        const bot_left = (Vec2f{ .x = -size.x / 2, .y = size.y / 2 }).rotate(rot).add(&pos);
        const bot_right = (Vec2f{ .x = size.x / 2, .y = size.y / 2 }).rotate(rot).add(&pos);

        const top_left_vert = self.pushVert(top_left, color);
        const top_right_vert = self.pushVert(top_right, color);
        const bot_left_vert = self.pushVert(bot_left, color);
        const bot_right_vert = self.pushVert(bot_right, color);

        self.pushElem(top_left_vert);
        self.pushElem(top_right_vert);
        self.pushElem(bot_right_vert);

        self.pushElem(top_left_vert);
        self.pushElem(bot_right_vert);
        self.pushElem(bot_left_vert);
    }

    fn flush(self: *RenderBuffer) void {
        const screen_size = platform.getScreenSize();
        const translationMatrix = [_]f32{
            1, 0, 0, -self.translation.x,
            0, 1, 0, -self.translation.y,
            0, 0, 1, 0,
            0, 0, 0, 1,
        };
        const scalingMatrix = [_]f32{
            2 / @intToFloat(f32, screen_size.x), 0,                                    0, -1,
            0,                                   -2 / @intToFloat(f32, screen_size.y), 0, 1,
            0,                                   0,                                    1, 0,
            0,                                   0,                                    0, 1,
        };
        const projectionMatrix = mulMat4(&scalingMatrix, &translationMatrix);
        platform.glUseProgram(shader_program);

        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, vbo);
        platform.glBufferData(platform.GL_ARRAY_BUFFER, @intCast(c_long, self.vertIdx * NUM_ATTR * @sizeOf(f32)), &self.verts, platform.GL_STATIC_DRAW);
        platform.glBindBuffer(platform.GL_ELEMENT_ARRAY_BUFFER, ebo);
        platform.glBufferData(platform.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, self.indIdx * @sizeOf(platform.GLushort)), &self.indices, platform.GL_STATIC_DRAW);

        platform.glUniformMatrix4fv(projectionMatrixUniformLocation, 1, platform.GL_FALSE, &projectionMatrix);

        platform.glEnableVertexAttribArray(0);
        platform.glEnableVertexAttribArray(1);

        platform.glVertexAttribPointer(0, 2, platform.GL_FLOAT, platform.GL_FALSE, 5 * @sizeOf(f32), null);
        platform.glVertexAttribPointer(1, 3, platform.GL_FLOAT, platform.GL_FALSE, 5 * @sizeOf(f32), @intToPtr(*c_void, 2 * @sizeOf(f32)));

        platform.glDrawElements(platform.GL_TRIANGLES, @intCast(u16, self.indIdx), platform.GL_UNSIGNED_SHORT, null);
    }
};

pub fn render(alpha: f64) void {
    platform.glClearColor(1, 1, 1, 1);
    platform.glClear(platform.GL_COLOR_BUFFER_BIT);

    var render_buffer = RenderBuffer.init();
    render_buffer.setTranslation(camera_pos);

    render_buffer.pushRect(.{ .x = 0, .y = 0 }, .{ .x = LEVEL_WIDTH, .y = LEVEL_HEIGHT }, LEVEL_COLOR, 0);

    render_buffer.pushRect(head_segment.pos, .{ .x = 50, .y = 50 }, SEGMENT_COLORS[0], head_segment.dir);

    var idx: usize = 0;
    while (segments[idx]) |segment| {
        const color = SEGMENT_COLORS[(idx + 1) % SEGMENT_COLORS.len];

        render_buffer.pushRect(segment.pos, .{ .x = SNAKE_SEGMENT_LENGTH, .y = 30 }, color, segment.dir);
        idx += 1;
    }
    const color = SEGMENT_COLORS[(idx + 1) % SEGMENT_COLORS.len];
    render_buffer.pushRect(tail_segment.pos, .{ .x = SNAKE_TAIL_LENGTH, .y = 20 }, color, tail_segment.dir);

    if (food_pos) |pos| {
        render_buffer.pushRect(pos, .{ .x = 20, .y = 20 }, FOOD_COLOR, 0);
    }

    render_buffer.flush();
    platform.renderPresent();
}

fn addSegment() void {
    if (next_segment_idx == segments.len) {
        platform.warn("Ran out of space for snake segments\n", .{});
        return;
    }
    segments[next_segment_idx] = tail_segment;
    next_segment_idx += 1;
}
