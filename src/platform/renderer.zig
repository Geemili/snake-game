const platform = @import("../platform.zig");
const Vec2f = platform.Vec2f;
const Rect2f = platform.Rect2f;

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

const vFontShaderSrc =
    \\ #version 300 es
    \\ layout(location = 0) in vec2 a_position;
    \\ layout(location = 1) in vec2 a_uv;
    \\ layout(location = 2) in vec3 a_color;
    \\ uniform mat4 projectionMatrix;
    \\ out vec3 v_color;
    \\ out vec2 v_uv;
    \\ void main() {
    \\   v_color = a_color;
    \\   gl_Position = vec4(a_position.x, a_position.y, 0.0, 1.0);
    \\   gl_Position *= projectionMatrix;
    \\   v_uv = a_uv;
    \\ }
;
const fFontShaderSrc =
    \\ #version 300 es
    \\ precision mediump float;
    \\ in vec3 v_color;
    \\ in vec2 v_uv;
    \\ out vec4 o_fragColor;
    \\
    \\ uniform sampler2D text;
    \\
    \\ void main() {
    \\   vec4 sampled = vec4(1.0, 1.0, 1.0, texture(text, v_uv).r);
    \\   o_fragColor = vec4(v_color, 1.0) * sampled;
    \\ }
;

const Mode = enum {
    Normal,
    Font,
};

pub const Renderer = struct {
    mode: Mode,

    const NUM_ATTR = 5;
    verts: [NUM_ATTR * 512]f32 = undefined,
    vertIdx: usize,
    indices: [2 * 3 * 512]platform.GLushort = undefined,
    indIdx: usize,
    translation: Vec2f = Vec2f{ .x = 0, .y = 0 },

    shader_program: platform.GLuint,
    vbo: platform.GLuint,
    ebo: platform.GLuint,
    projectionMatrixUniformLocation: platform.GLint,

    const FONT_ATTR = 7;
    font_verts: [FONT_ATTR * 512]f32 = undefined,
    font_vertIdx: usize,
    font_indices: [2 * 3 * 512]platform.GLushort = undefined,
    font_indIdx: usize,
    font_shader_program: platform.GLuint,
    font_vbo: platform.GLuint,
    font_ebo: platform.GLuint,
    font_texture: platform.GLuint,
    font_projectionMatrixUniformLocation: platform.GLint,

    pub fn init() Renderer {
        platform.glEnable(platform.GL_BLEND);
        platform.glBlendFunc(platform.GL_SRC_ALPHA, platform.GL_ONE_MINUS_SRC_ALPHA);

        const vbo = platform.glCreateBuffer();
        const ebo = platform.glCreateBuffer();

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

        const shader_program = platform.glCreateProgram();
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
        const projectionMatrixUniformLocation = platform.glGetUniformLocation(shader_program, "projectionMatrix");

        // Set up font rendering stuff
        const font_vbo = platform.glCreateBuffer();
        const font_ebo = platform.glCreateBuffer();

        const vFontShader = platform.glCreateShader(platform.GL_VERTEX_SHADER);
        platform.setShaderSource(vFontShader, vFontShaderSrc);
        platform.glCompileShader(vFontShader);
        defer platform.glDeleteShader(vFontShader);

        if (!platform.getShaderCompileStatus(vFontShader)) {
            var infoLog: [512]u8 = [_]u8{0} ** 512;
            var infoLen: platform.GLsizei = 0;
            platform.glGetShaderInfoLog(vFontShader, infoLog.len, &infoLen, &infoLog);
            platform.warn("Error compiling vertex shader: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
        }

        const fFontShader = platform.glCreateShader(platform.GL_FRAGMENT_SHADER);
        platform.setShaderSource(fFontShader, fFontShaderSrc);
        platform.glCompileShader(fFontShader);
        defer platform.glDeleteShader(fFontShader);

        if (!platform.getShaderCompileStatus(vFontShader)) {
            var infoLog: [512]u8 = [_]u8{0} ** 512;
            var infoLen: platform.GLsizei = 0;
            platform.glGetShaderInfoLog(fFontShader, infoLog.len, &infoLen, &infoLog);
            platform.warn("Error compiling fragment shader: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
        }

        const font_shader_program = platform.glCreateProgram();
        platform.glAttachShader(font_shader_program, vFontShader);
        platform.glAttachShader(font_shader_program, fFontShader);
        platform.glLinkProgram(font_shader_program);

        if (!platform.getProgramLinkStatus(font_shader_program)) {
            var infoLog: [512]u8 = [_]u8{0} ** 512;
            var infoLen: platform.GLsizei = 0;
            platform.glGetProgramInfoLog(font_shader_program, infoLog.len, &infoLen, &infoLog);
            platform.warn("Error linking shader program: {}\n", .{infoLog[0..@intCast(usize, infoLen)]});
        }

        platform.glUseProgram(font_shader_program);
        const font_projectionMatrixUniformLocation = platform.glGetUniformLocation(font_shader_program, "projectionMatrix");

        return .{
            .mode = .Normal,

            .vertIdx = 0,
            .indIdx = 0,
            .shader_program = shader_program,
            .vbo = vbo,
            .ebo = ebo,
            .projectionMatrixUniformLocation = projectionMatrixUniformLocation,

            .font_vertIdx = 0,
            .font_indIdx = 0,
            .font_shader_program = font_shader_program,
            .font_vbo = font_vbo,
            .font_ebo = font_ebo,
            .font_texture = 0xFFFFFFF,
            .font_projectionMatrixUniformLocation = font_projectionMatrixUniformLocation,
        };
    }

    fn setTranslation(self: *Renderer, vec: Vec2f) void {
        self.translation = vec;
    }

    fn pushVert(self: *Renderer, pos: Vec2f, color: platform.Color) usize {
        const idx = self.vertIdx;
        defer self.vertIdx += 1;

        self.verts[idx * NUM_ATTR + 0] = pos.x;
        self.verts[idx * NUM_ATTR + 1] = pos.y;
        self.verts[idx * NUM_ATTR + 2] = @intToFloat(f32, color.r) / 255.0;
        self.verts[idx * NUM_ATTR + 3] = @intToFloat(f32, color.g) / 255.0;
        self.verts[idx * NUM_ATTR + 4] = @intToFloat(f32, color.b) / 255.0;
        return idx;
    }

    fn pushFontVert(self: *Renderer, pos: Vec2f, uv: Vec2f, color: platform.Color) usize {
        const idx = self.font_vertIdx;
        defer self.font_vertIdx += 1;

        self.font_verts[idx * FONT_ATTR + 0] = pos.x;
        self.font_verts[idx * FONT_ATTR + 1] = pos.y;
        self.font_verts[idx * FONT_ATTR + 2] = uv.x;
        self.font_verts[idx * FONT_ATTR + 3] = uv.y;
        self.font_verts[idx * FONT_ATTR + 4] = @intToFloat(f32, color.r) / 255.0;
        self.font_verts[idx * FONT_ATTR + 5] = @intToFloat(f32, color.g) / 255.0;
        self.font_verts[idx * FONT_ATTR + 6] = @intToFloat(f32, color.b) / 255.0;
        return idx;
    }

    fn pushElem(self: *Renderer, vertIdx: usize) void {
        self.indices[self.indIdx] = @intCast(platform.GLushort, vertIdx);
        defer self.indIdx += 1;
    }

    fn pushFontElem(self: *Renderer, vertIdx: usize) void {
        self.font_indices[self.font_indIdx] = @intCast(platform.GLushort, vertIdx);
        defer self.font_indIdx += 1;
    }

    fn wouldOverflow(self: *Renderer, numVerts: usize, numInd: usize) bool {
        return (self.vertIdx + numVerts) * NUM_ATTR >= self.verts.len or self.indIdx + numInd >= self.indices.len;
    }

    fn pushRect(self: *Renderer, pos: Vec2f, size: Vec2f, color: platform.Color, rot: f32) void {
        if (self.mode != .Normal or self.wouldOverflow(4, 6)) {
            self.flush();
        }
        self.mode = .Normal;

        const top_left = (Vec2f{ .x = -size.x / 2, .y = -size.y / 2 }).rotate(rot).add(pos);
        const top_right = (Vec2f{ .x = size.x / 2, .y = -size.y / 2 }).rotate(rot).add(pos);
        const bot_left = (Vec2f{ .x = -size.x / 2, .y = size.y / 2 }).rotate(rot).add(pos);
        const bot_right = (Vec2f{ .x = size.x / 2, .y = size.y / 2 }).rotate(rot).add(pos);

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

    fn fontWouldOverflow(self: *Renderer, numVerts: usize, numInd: usize) bool {
        return (self.font_vertIdx + numVerts) * FONT_ATTR >= self.font_verts.len or self.font_indIdx + numInd >= self.font_indices.len;
    }

    fn pushFontRect(self: *Renderer, dst: Rect2f, uv: Rect2f, texture: platform.GLuint, color: platform.Color) void {
        if (self.mode != .Font or self.font_texture != texture or self.fontWouldOverflow(4, 6)) {
            self.flush();
        }
        self.mode = .Font;
        self.font_texture = texture;

        const top_left_vert = self.pushFontVert(dst.top_left(), uv.top_left(), color);
        const top_right_vert = self.pushFontVert(dst.top_right(), uv.top_right(), color);
        const bot_left_vert = self.pushFontVert(dst.bottom_left(), uv.bottom_left(), color);
        const bot_right_vert = self.pushFontVert(dst.bottom_right(), uv.bottom_right(), color);

        self.pushFontElem(top_left_vert);
        self.pushFontElem(top_right_vert);
        self.pushFontElem(bot_right_vert);

        self.pushFontElem(top_left_vert);
        self.pushFontElem(bot_right_vert);
        self.pushFontElem(bot_left_vert);
    }

    pub fn begin(self: *Renderer) void {
        self.reset();

        platform.glClearColor(0, 0, 0, 1);
        platform.glClear(platform.GL_COLOR_BUFFER_BIT);
    }

    pub fn reset(self: *Renderer) void {
        self.vertIdx = 0;
        self.indIdx = 0;
        self.font_vertIdx = 0;
        self.font_indIdx = 0;
    }

    fn flush(self: *Renderer) void {
        switch (self.mode) {
            .Normal => self.flushNormal(),
            .Font => self.flushFont(),
        }
        self.reset();
    }

    fn flushNormal(self: *Renderer) void {
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
        const projectionMatrix = scalingMatrix; //mulMat4(&scalingMatrix, &translationMatrix);
        platform.glUseProgram(self.shader_program);

        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, self.vbo);
        platform.glBufferData(platform.GL_ARRAY_BUFFER, @intCast(c_long, self.vertIdx * NUM_ATTR * @sizeOf(f32)), &self.verts, platform.GL_STATIC_DRAW);
        platform.glBindBuffer(platform.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        platform.glBufferData(platform.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, self.indIdx * @sizeOf(platform.GLushort)), &self.indices, platform.GL_STATIC_DRAW);

        platform.glUniformMatrix4fv(self.projectionMatrixUniformLocation, 1, platform.GL_FALSE, &projectionMatrix);

        platform.glEnableVertexAttribArray(0);
        platform.glEnableVertexAttribArray(1);

        platform.glVertexAttribPointer(0, 2, platform.GL_FLOAT, platform.GL_FALSE, 5 * @sizeOf(f32), null);
        platform.glVertexAttribPointer(1, 3, platform.GL_FLOAT, platform.GL_FALSE, 5 * @sizeOf(f32), @intToPtr(*c_void, 2 * @sizeOf(f32)));

        platform.glDrawElements(platform.GL_TRIANGLES, @intCast(u16, self.indIdx), platform.GL_UNSIGNED_SHORT, null);
    }

    fn flushFont(self: *Renderer) void {
        const screen_size = platform.getScreenSize();
        const scalingMatrix = [_]f32{
            2 / @intToFloat(f32, screen_size.x), 0,                                    0, -1,
            0,                                   -2 / @intToFloat(f32, screen_size.y), 0, 1,
            0,                                   0,                                    1, 0,
            0,                                   0,                                    0, 1,
        };

        platform.glUseProgram(self.font_shader_program);

        platform.glActiveTexture(platform.GL_TEXTURE0);
        platform.glBindTexture(platform.GL_TEXTURE_2D, self.font_texture);

        platform.glBindBuffer(platform.GL_ARRAY_BUFFER, self.font_vbo);
        platform.glBufferData(platform.GL_ARRAY_BUFFER, @intCast(c_long, self.font_vertIdx * FONT_ATTR * @sizeOf(f32)), &self.font_verts, platform.GL_DYNAMIC_DRAW);
        platform.glBindBuffer(platform.GL_ELEMENT_ARRAY_BUFFER, self.font_ebo);
        platform.glBufferData(platform.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, self.font_indIdx * @sizeOf(platform.GLushort)), &self.font_indices, platform.GL_DYNAMIC_DRAW);

        platform.glUniformMatrix4fv(self.font_projectionMatrixUniformLocation, 1, platform.GL_FALSE, &scalingMatrix);

        platform.glEnableVertexAttribArray(0);
        platform.glEnableVertexAttribArray(1);
        platform.glEnableVertexAttribArray(2);

        platform.glVertexAttribPointer(0, 2, platform.GL_FLOAT, platform.GL_FALSE, FONT_ATTR * @sizeOf(f32), null);
        platform.glVertexAttribPointer(1, 2, platform.GL_FLOAT, platform.GL_FALSE, FONT_ATTR * @sizeOf(f32), @intToPtr(*c_void, 2 * @sizeOf(f32)));
        platform.glVertexAttribPointer(2, 3, platform.GL_FLOAT, platform.GL_FALSE, FONT_ATTR * @sizeOf(f32), @intToPtr(*c_void, 4 * @sizeOf(f32)));

        platform.glDrawElements(platform.GL_TRIANGLES, @intCast(u16, self.font_indIdx), platform.GL_UNSIGNED_SHORT, null);
    }
};
