const builtin = @import("builtin");
const std = @import("std");
usingnamespace @import("c.zig");

const platform = @import("../../platform.zig");
const Renderer = @import("../renderer.zig").Renderer;
const common = @import("../common.zig");
const Rect = common.Rect;
const Rect2f = common.Rect2f;
const Vec2f = common.Vec2f;
const sdl = @import("../sdl.zig");
const components = @import("../components.zig");
const Component = components.Component;
const ComponentTag = components.ComponentTag;
const Layout = components.Layout;
const Events = components.Events;

const MASK = if (builtin.endian == .Big)
    .{
        .r = 0xFF000000,
        .g = 0x00FF0000,
        .b = 0x0000FF00,
        .a = 0x000000FF,
    }
else
    .{
        .r = 0x000000FF,
        .g = 0x0000FF00,
        .b = 0x00FF0000,
        .a = 0xFF000000,
    };

fn rgba(r: u8, g: u8, b: u8, a: u8) u32 {
    if (builtin.endian == .Big) {
        return @shlExact(@as(u32, r), 24) | @shlExact(@as(u32, g), 16) | @shlExact(@as(u32, b), 8) | a;
    } else {
        return @shlExact(@as(u32, a), 24) | @shlExact(@as(u32, b), 16) | @shlExact(@as(u32, g), 8) | r;
    }
}

const ROBOTO_REGULAR_FONT = @embedFile("../../../assets/roboto-regular.ttf");
const FONT_SIZE = 20;

const Character = struct {
    texture: GLuint,
    size: platform.Vec2f,
    bearing: platform.Vec2f,
    advance: i64,
};

const Context = struct {
    alloc: *std.mem.Allocator,
    renderer: *platform.Renderer,
    characters: *std.AutoHashMap(u32, Character),
    face_line_height: i64,
    face_ascender: i64,
    face_descender: i64,
};

pub const ComponentRenderer = struct {
    alloc: *std.mem.Allocator,
    current_component: ?RenderedComponent = null,
    freetype: *FT_Library,
    face: *FT_Face,
    characters: std.AutoHashMap(u32, Character),
    face_line_height: i64,
    face_ascender: i64,
    face_descender: i64,

    pub fn init(alloc: *std.mem.Allocator) !@This() {
        var ft = try alloc.create(FT_Library);
        errdefer alloc.destroy(ft);

        var ret = FT_Init_FreeType(ft);
        if (ret != 0) {
            return error.FreetypeInitFailed;
        }

        var face = try alloc.create(FT_Face);
        errdefer alloc.destroy(face);

        const font = ROBOTO_REGULAR_FONT;
        ret = FT_New_Memory_Face(ft.*, font, font.len, 0, face);
        if (ret != 0) {
            return error.FaceInitFailed;
        }

        ret = FT_Set_Pixel_Sizes(face.*, 0, FONT_SIZE);
        if (ret != 0) {
            return error.SetFaceSizeFailed;
        }

        // Add all 128 ascii glyphs to map
        var characters = std.AutoHashMap(u32, Character).init(alloc);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        var char: u32 = 32;
        while (char <= 126) : (char += 1) {
            if (FT_Load_Char(face.*, char, FT_LOAD_RENDER) > 1) {
                std.debug.warn("Failed to load freetype glyph: {x}\n", .{char});
                continue;
            }
            var texture: GLuint = 0;
            glGenTextures(1, &texture);
            glBindTexture(GL_TEXTURE_2D, texture);
            glTexImage2D(
                GL_TEXTURE_2D,
                0,
                GL_RED,
                @intCast(c_int, face.*.*.glyph.*.bitmap.width),
                @intCast(c_int, face.*.*.glyph.*.bitmap.rows),
                0,
                GL_RED,
                GL_UNSIGNED_BYTE,
                face.*.*.glyph.*.bitmap.buffer,
            );
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            _ = try characters.put(char, .{
                .texture = texture,
                .size = .{ .x = @intToFloat(f32, face.*.*.glyph.*.bitmap.width), .y = @intToFloat(f32, face.*.*.glyph.*.bitmap.rows) },
                .bearing = .{ .x = @intToFloat(f32, face.*.*.glyph.*.bitmap_left), .y = @intToFloat(f32, face.*.*.glyph.*.bitmap_top) },
                .advance = face.*.*.glyph.*.advance.x,
            });
        }

        return @This(){
            .alloc = alloc,
            .freetype = ft,
            .face = face,
            .characters = characters,
            .face_line_height = face.*.*.size.*.metrics.height,
            .face_ascender = face.*.*.size.*.metrics.ascender,
            .face_descender = face.*.*.size.*.metrics.descender,
        };
    }

    pub fn onEvent(self: *@This(), event: platform.Event) ?platform.Event {
        if (self.current_component) |*component| {
            return component.onEvent(event);
        }
        return null;
    }

    pub fn update(self: *@This(), new_component: *const Component) RenderingError!void {
        if (self.current_component) |*component| {
            component.deinit();
        }
        self.current_component = try componentToRendered(self.alloc, new_component);
    }

    pub fn render(self: *@This(), renderer: *Renderer) void {
        if (self.current_component) |*component| {
            const screen_size = sdl.getScreenSize();
            const space = Rect{
                .x = 0,
                .y = 0,
                .w = screen_size.x,
                .h = screen_size.y,
            };
            component.render(.{
                .alloc = self.alloc,
                .renderer = renderer,
                .characters = &self.characters,
                .face_line_height = self.face_line_height,
                .face_ascender = self.face_ascender,
                .face_descender = self.face_descender,
            }, space) catch unreachable;
        }
    }

    pub fn clear(self: *@This()) void {
        self.current_component = null;
    }

    pub fn deinit(self: *@This()) void {
        _ = FT_Done_Face(self.face.*);
        _ = FT_Done_FreeType(self.freetype.*);
        self.alloc.destroy(self.face);
        self.alloc.destroy(self.freetype);
    }
};

const RenderedComponent = union(ComponentTag) {
    Text: Text,
    Button: Button,
    Container: Container,

    pub fn remove(self: *@This()) void {
        self.deinit(self);
    }

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .Text => |*text| text.deinit(),
            .Button => |*button| button.deinit(),
            .Container => |*container| container.deinit(),
        }
    }

    pub fn onEvent(self: *@This(), event: platform.Event) ?platform.Event {
        return switch (self.*) {
            .Text => null,
            .Button => |*self_button| self_button.onEvent(event),
            .Container => |*self_container| self_container.onEvent(event),
        };
    }

    pub fn size_hint(self: *@This(), ctx: Context, space: Rect) SizeHint {
        return switch (self.*) {
            .Text => |*text| text.size_hint(ctx, space),
            .Button => .{ .min = .{ .x = 0, .y = 0 }, .max = .{ .x = space.w, .y = space.h } },
            .Container => .{ .min = .{ .x = 0, .y = 0 }, .max = .{ .x = space.w, .y = space.h } },
        };
    }

    pub fn render(self: *@This(), renderer: Context, space: Rect) RenderingError!void {
        return switch (self.*) {
            .Text => |*self_text| self_text.render(renderer, space),
            .Button => |*self_button| self_button.render(renderer, space),
            .Container => |*self_container| try self_container.render(renderer, space),
        };
    }
};

const Text = struct {
    alloc: *std.mem.Allocator,
    text: []const u8,
    glyphs: std.ArrayList(Glyph),
    prev_size: platform.Vec2,

    pub fn init(alloc: *std.mem.Allocator, text: []const u8) !@This() {
        return @This(){
            .alloc = alloc,
            .text = try std.mem.dupe(alloc, u8, text),
            .glyphs = std.ArrayList(Glyph).init(alloc),
            .prev_size = .{ .x = 0, .y = 0 },
        };
    }

    pub fn deinit(self: *@This()) void {
        self.alloc.free(self.text);
        self.glyphs.deinit();
    }

    pub fn size_hint(self: *@This(), ctx: Context, space: Rect) SizeHint {
        return getTextSizeHint(ctx, self.text, .{ .wrapWidth = space.w });
    }

    pub fn update_glyphs(self: *@This(), ctx: Context, space: Rect) !void {
        self.glyphs.deinit();
        self.glyphs = try renderText(ctx, self.text, .{ .wrapWidth = @intToFloat(f32, space.w) });
        self.prev_size = .{ .x = space.w, .y = space.h };
    }

    pub fn render(self: *@This(), ctx: Context, space: Rect) RenderingError!void {
        if (self.prev_size.x != space.w or self.prev_size.y != space.h) {
            try self.update_glyphs(ctx, space);
        }

        const size = Vec2f{
            .x = @intToFloat(f32, space.w),
            .y = @intToFloat(f32, space.h),
        };
        const center = (Vec2f{
            .x = @intToFloat(f32, space.x),
            .y = @intToFloat(f32, space.y),
        }).add(size.scalMul(0.5));

        for (self.glyphs.span()) |g| {
            ctx.renderer.pushFontRect(g.dst.translate(center), g.uv, g.texture, g.color);
        }
    }
};

const Button = struct {
    alloc: *std.mem.Allocator,
    text: []const u8,
    events: Events,

    rect: Rect2f = Rect2f{ .x = 0, .y = 0, .w = 0, .h = 0 },
    leftMouseBtnDown: bool = false,
    hover: bool = false,

    pub fn deinit(self: *@This()) void {
        self.alloc.free(self.text);
    }

    pub fn onEvent(self: *@This(), event: platform.Event) ?platform.Event {
        switch (event) {
            .MouseMotion => |pos| {
                const prev = self.hover;
                self.hover = self.rect.contains(Vec2f.fromVeci(pos));
                if (!prev and self.hover) {
                    if (self.events.hover) |hover| {
                        return platform.Event{ .Custom = hover };
                    }
                }
            },
            .MouseButtonDown => |ev| if (self.rect.contains(Vec2f.fromVeci(ev.pos))) {
                if (ev.button == .Left) {
                    self.leftMouseBtnDown = true;
                }
            },
            .MouseButtonUp => |ev| if (self.leftMouseBtnDown) {
                if (ev.button == .Left) {
                    self.leftMouseBtnDown = false;
                    if (self.rect.contains(Vec2f.fromVeci(ev.pos))) {
                        if (self.events.click) |click| {
                            return platform.Event{ .Custom = click };
                        }
                    }
                }
            },
            else => {},
        }
        return null;
    }

    pub fn render(self: *@This(), ctx: Context, space: Rect) void {
        const size = Vec2f{
            .x = @intToFloat(f32, space.w) / 2,
            .y = @intToFloat(f32, space.h) / 2,
        };
        const center = (Vec2f{
            .x = @intToFloat(f32, space.x),
            .y = @intToFloat(f32, space.y),
        }).add(size);
        self.rect = .{ .x = center.x, .y = center.y, .w = size.x, .h = size.y };
        const color = if (self.leftMouseBtnDown and self.hover) platform.Color{ .r = 255, .g = 255, .b = 255 } else platform.Color{ .r = 230, .g = 230, .b = 230 };
        ctx.renderer.pushRect(center, size, color, 0);

        // Render label
        const glyphs = renderText(ctx, self.text, .{}) catch unreachable;
        defer glyphs.deinit();
        for (glyphs.span()) |g| {
            ctx.renderer.pushFontRect(g.dst.translate(center), g.uv, g.texture, g.color);
        }
    }
};

pub const Container = struct {
    alloc: *std.mem.Allocator,
    layout: Layout,
    children: std.ArrayList(RenderedComponent),

    pub fn removeChildren(self: *@This()) void {
        for (self.children.span()) |*child| {
            child.remove();
        }
        self.children.resize(0) catch unreachable;
    }

    pub fn deinit(self: *@This()) void {
        for (self.children.span()) |*child| {
            child.deinit();
        }
        self.children.deinit();
    }

    pub fn onEvent(self: *@This(), event: platform.Event) ?platform.Event {
        for (self.children.span()) |*child| {
            if (child.onEvent(event)) |ev| {
                return ev;
            }
        }
        return null;
    }

    pub fn render(self: *@This(), renderer: Context, space: Rect) RenderingError!void {
        switch (self.layout) {
            .Flex => |flex| {
                var size_hints = try std.ArrayList(SizeHint).initCapacity(self.alloc, self.children.span().len);
                defer size_hints.deinit();

                // The total amount requested from SizeHint.max
                var total_requested: i32 = 0;
                var total_min_requested: i32 = 0;

                for (self.children.span()) |*child| {
                    const size_hint = child.size_hint(renderer, space);
                    total_requested += switch (flex.orientation) {
                        .Horizontal => size_hint.max.x,
                        .Vertical => size_hint.max.y,
                    };
                    total_min_requested += switch (flex.orientation) {
                        .Horizontal => size_hint.min.x,
                        .Vertical => size_hint.min.y,
                    };
                    try size_hints.append(size_hint);
                }

                const axisSize = switch (flex.orientation) {
                    .Horizontal => space.w,
                    .Vertical => space.h,
                };
                const crossAxisSize = switch (flex.orientation) {
                    .Horizontal => space.h,
                    .Vertical => space.w,
                };

                var main_sizes = try std.ArrayList(i32).initCapacity(self.alloc, self.children.span().len);
                defer main_sizes.deinit();

                if (total_requested > axisSize) {
                    unreachable; // TODO: shrink each component until it fits
                } else {
                    for (size_hints.span()) |hint| {
                        const size = switch (flex.orientation) {
                            .Horizontal => hint.max.x,
                            .Vertical => hint.max.y,
                        };
                        try main_sizes.append(size);
                    }
                }

                const num_children = @intCast(i32, self.children.span().len);
                var pos: i32 = switch (flex.main_axis_alignment) {
                    .Start, .SpaceBetween => 0,
                    .Center => if (total_requested < axisSize) @divFloor((axisSize - total_requested), 2) else 0,
                    .End => if (total_requested < axisSize) axisSize - total_requested else 0,
                    .SpaceAround => if (total_requested < axisSize) @divFloor(axisSize - total_requested, num_children * 2) else 0,
                };
                const blank_space_after: i32 = switch (flex.main_axis_alignment) {
                    .Start, .Center, .End => 0,
                    .SpaceAround => if (total_requested < axisSize) @divFloor(axisSize - total_requested, num_children) else 0,
                    .SpaceBetween => if (total_requested < axisSize) @divFloor(axisSize - total_requested, num_children - 1) else 0,
                };
                for (self.children.span()) |*child, idx| {
                    const size = main_sizes.span()[idx];
                    defer pos += size + blank_space_after;
                    const hint = child.size_hint(renderer, .{
                        .x = 0,
                        .y = 0,
                        .w = if (flex.orientation == .Horizontal) size else space.w,
                        .h = if (flex.orientation == .Vertical) size else space.h,
                    });
                    const crossSize = switch (flex.orientation) {
                        .Horizontal => hint.min.y,
                        .Vertical => hint.min.x,
                    };
                    const crossPos = switch (flex.cross_axis_alignment) {
                        .Start => 0,
                        .Center => @divFloor((crossAxisSize - crossSize), 2),
                        .End => crossAxisSize - crossSize,
                    };
                    const childSpace = switch (flex.orientation) {
                        .Horizontal => Rect{
                            .x = space.x + pos,
                            .y = space.y + crossPos,
                            .w = size,
                            .h = crossSize,
                        },
                        .Vertical => Rect{
                            .x = space.x + crossPos,
                            .y = space.y + pos,
                            .w = crossSize,
                            .h = size,
                        },
                    };
                    try child.render(renderer, childSpace);
                }
            },
            .Grid => |template| {
                if (template.areas) |areas| {
                    const Cell = struct {
                        area_id: usize,
                        // space cell takes up in the areas array
                        rect: Rect,
                    };
                    var spots = std.ArrayList(Cell).init(self.alloc);
                    defer spots.deinit();
                    var x: usize = 0;
                    var y: usize = 0;
                    while (y < areas.len) {
                        defer {
                            x += 1;
                            if (x >= areas[y].len) {
                                y += 1;
                                x = 0;
                            }
                        }
                        var cell = try spots.addOne();
                        cell.area_id = areas[y][x];
                        cell.rect.x = @intCast(i32, x);
                        while (x + 1 < areas[y].len and areas[y][x + 1] == cell.area_id) {
                            x += 1;
                        }
                        cell.rect.w = @intCast(i32, x) - cell.rect.x;

                        cell.rect.y = @intCast(i32, y);
                        var j = y;
                        expand_down: while (j + 1 < areas.len) {
                            var i = @intCast(usize, cell.rect.x);
                            while (i <= cell.rect.x + cell.rect.w) : (i += 1) {
                                if (areas[j + 1][i] != cell.area_id) {
                                    break :expand_down;
                                }
                            }
                            j += 1;
                        }
                        cell.rect.h = @intCast(i32, j) - cell.rect.y;
                    }

                    const height_per_component = @divTrunc(space.h, @intCast(i32, areas.len));
                    const width_per_component = @divTrunc(space.w, @intCast(i32, areas[0].len));
                    for (spots.span()) |spot| {
                        try self.children.span()[spot.area_id].render(renderer, Rect{
                            .x = space.x + @intCast(i32, spot.rect.x) * width_per_component,
                            .y = space.y + @intCast(i32, spot.rect.y) * height_per_component,
                            .w = @intCast(i32, spot.rect.w + 1) * width_per_component,
                            .h = @intCast(i32, spot.rect.h + 1) * height_per_component,
                        });
                    }
                } else if (template.column) |column| {
                    // Render
                    const denom = denom_calc: {
                        var denom: u32 = 0;
                        for (column) |row_fraction| {
                            denom += row_fraction;
                        }
                        break :denom_calc denom;
                    };
                    const height_per_component = @divTrunc(space.h, @intCast(i32, denom));
                    const num_cols = @divFloor(self.children.items.len, column.len) + if (self.children.items.len % column.len > 0) @as(u32, 1) else @as(u32, 0);
                    const width_per_component = @divTrunc(space.w, @intCast(i32, num_cols));
                    var yFracUsed: u32 = 0; // Amount of y fractions used
                    for (self.children.span()) |*child, idx| {
                        const y = idx % column.len;
                        if (y == 0) {
                            yFracUsed = 0;
                        }
                        const x = @divFloor(idx, column.len);
                        const yFrac = column[y];
                        try child.render(renderer, Rect{
                            .x = space.x + @intCast(i32, x) * width_per_component,
                            .y = space.y + @intCast(i32, yFracUsed) * height_per_component,
                            .w = width_per_component,
                            .h = height_per_component * @intCast(i32, yFrac),
                        });
                        yFracUsed += yFrac;
                    }
                } else if (template.row) |row| {
                    const denom = denom_calc: {
                        var denom: u32 = 0;
                        for (row) |fraction| {
                            denom += fraction;
                        }
                        break :denom_calc denom;
                    };
                    const width_per_component = @divTrunc(space.w, @intCast(i32, denom));
                    const num_rows = @divFloor(self.children.items.len, row.len) + if (self.children.items.len % row.len > 0) @as(u32, 1) else @as(u32, 0);
                    const height_per_component = @divTrunc(space.h, @intCast(i32, num_rows));
                    var xFracUsed: u32 = 0; // Amount of y fractions used
                    for (self.children.span()) |*child, idx| {
                        const x = idx % row.len;
                        if (x == 0) {
                            xFracUsed = 0;
                        }
                        const y = @divFloor(idx, row.len);
                        const xFrac = row[x];
                        try child.render(renderer, Rect{
                            .x = space.x + @intCast(i32, xFracUsed) * width_per_component,
                            .y = space.y + @intCast(i32, y) * height_per_component,
                            .w = width_per_component * @intCast(i32, xFrac),
                            .h = height_per_component,
                        });
                        xFracUsed += xFrac;
                    }
                } else {
                    std.debug.assert(false); // Invalid grid layout; at least one of column, row, or areas must be defined
                }
            },
        }
    }
};

pub const RenderingError = std.mem.Allocator.Error;

pub fn componentToRendered(alloc: *std.mem.Allocator, component: *const Component) RenderingError!RenderedComponent {
    switch (component.*) {
        .Text => |text| {
            return RenderedComponent{
                .Text = try Text.init(alloc, text),
            };
        },
        .Button => |button| {
            return RenderedComponent{
                .Button = .{
                    .alloc = alloc,
                    .text = try std.mem.dupe(alloc, u8, button.text),
                    .events = button.events,
                },
            };
        },
        .Container => |container| {
            var rendered_children = std.ArrayList(RenderedComponent).init(alloc);
            for (container.children) |*child, idx| {
                const childElem = try componentToRendered(alloc, child);
                try rendered_children.append(childElem);
            }

            return RenderedComponent{
                .Container = .{
                    .alloc = alloc,
                    .layout = container.layout,
                    .children = rendered_children,
                },
            };
        },
    }
}

const TextSizeHintOptions = struct {
    wrapWidth: ?i32 = null,
    lineHeight: f32 = 1,
};

const SizeHint = struct {
    min: platform.Vec2,
    max: platform.Vec2,
};

pub fn getTextSizeHint(ctx: Context, text: []const u8, opts: TextSizeHintOptions) SizeHint {
    const space_width = get_space_width: {
        const ch = ctx.characters.get(' ').?;
        break :get_space_width @intCast(i32, ch.advance >> 6);
    };

    const line_height = @floatToInt(i32, @intToFloat(f32, ctx.face_line_height >> 6) * opts.lineHeight);

    var pos = platform.Vec2{ .x = 0, .y = 0 };
    var word_width: i32 = 0;
    var max_word_width = word_width;
    var num_words: i32 = 0;
    var max_x: i32 = 0;
    var in_word: bool = false;
    var wrapped_for_word: bool = false;
    for (text) |c, idx| {
        if (in_word) {
            switch (c) {
                ' ', '\n', '\t' => {
                    if (pos.x > 0) {
                        pos.x += space_width;
                    }
                    in_word = false;
                    if (word_width > max_word_width) {
                        max_word_width = word_width;
                    }
                    num_words += 1;
                    word_width = 0;
                },
                else => {
                    const ch = ctx.characters.get(c).?;
                    pos.x += @intCast(i32, ch.advance >> 6);
                    word_width += @intCast(i32, ch.advance >> 6);

                    if (opts.wrapWidth) |wrapWidth| {
                        if (pos.x > wrapWidth and !wrapped_for_word) {
                            pos.y += line_height;
                            pos.x = word_width;
                            wrapped_for_word = true;
                        }
                    }
                    if (pos.x > max_x) {
                        max_x = pos.x;
                    }
                },
            }
        } else {
            switch (c) {
                ' ', '\n', '\t' => {},
                else => {
                    in_word = true;
                    wrapped_for_word = false;
                    const ch = ctx.characters.get(c).?;
                    pos.x += @intCast(i32, ch.advance >> 6);
                    word_width += @intCast(i32, ch.advance >> 6);

                    if (opts.wrapWidth) |wrapWidth| {
                        if (pos.x > wrapWidth and !wrapped_for_word) {
                            pos.y += line_height;
                            pos.x = word_width;
                            wrapped_for_word = true;
                        }
                    }
                    if (pos.x > max_x) {
                        max_x = pos.x;
                    }
                },
            }
        }
    }

    const vpadding = @intCast(i32, (ctx.face_ascender + ctx.face_descender) >> 6);

    return .{
        .min = .{ .x = max_word_width, .y = pos.y + line_height + vpadding },
        .max = .{ .x = max_x, .y = num_words * line_height },
    };
}

const RenderTextOptions = struct {
    color: platform.Color = platform.Color{ .r = 0, .g = 0, .b = 0 },
    wrapWidth: ?f32 = null,
    lineHeight: f32 = 1,
};

const Glyph = struct {
    dst: Rect2f,
    uv: Rect2f,
    texture: GLuint,
    color: platform.Color,
};

pub fn renderText(ctx: Context, text: []const u8, opts: RenderTextOptions) !std.ArrayList(Glyph) {
    const Word = struct {
        text: []const u8,
        width: f32,
    };
    var words = std.ArrayList(Word).init(ctx.alloc);
    defer words.deinit();

    const line_height = @intToFloat(f32, ctx.face_line_height >> 6) * opts.lineHeight;

    const space_width = get_space_width: {
        const ch = ctx.characters.get(' ').?;
        break :get_space_width @intToFloat(f32, ch.advance >> 6);
    };

    var word_width: f32 = 0;
    var total_width: f32 = 0;
    var startOpt: ?usize = null;
    for (text) |c, idx| {
        if (startOpt) |start| {
            switch (c) {
                ' ', '\n', '\t' => {
                    if (words.span().len > 0) {
                        total_width += space_width;
                    }
                    try words.append(.{ .text = text[start..idx], .width = word_width });
                    startOpt = null;
                    word_width = 0;
                },
                else => {
                    const ch = ctx.characters.get(c).?;
                    word_width += @intToFloat(f32, ch.advance >> 6);
                    total_width += @intToFloat(f32, ch.advance >> 6);
                },
            }
        } else {
            switch (c) {
                ' ', '\n', '\t' => {},
                else => {
                    startOpt = idx;
                    const ch = ctx.characters.get(c).?;
                    word_width += @intToFloat(f32, ch.advance >> 6);
                    total_width += @intToFloat(f32, ch.advance >> 6);
                },
            }
        }
    }
    if (startOpt) |start| {
        try words.append(.{ .text = text[start..], .width = word_width });
    }

    var glyphs = std.ArrayList(Glyph).init(ctx.alloc);
    errdefer glyphs.deinit();

    var width = if (opts.wrapWidth) |wwidth| std.math.min(total_width, wwidth) else total_width;
    var offsetx = -width / 2;

    var isFirst = true;
    var x: f32 = 0;
    var y: f32 = @intToFloat(f32, (ctx.face_line_height + ctx.face_ascender) >> 6); // TODO: make first line height of face bbox
    for (words.span()) |word| {
        // Add a space between each word
        if (!isFirst) {
            x += space_width;
        }
        defer isFirst = false;

        if (opts.wrapWidth) |wrapWidth| {
            // Make a new line if the word would make it too long
            if (x + word.width > wrapWidth) {
                x = 0;
                y += line_height;
            }
        }

        // Add each character in the text to the list of glyphs
        for (word.text) |c| {
            const ch = ctx.characters.get(c) orelse {
                std.debug.warn("Unknown character: {c}\n", .{c});
                unreachable;
            };
            const advance = @intToFloat(f32, ch.advance >> 6);
            defer x += advance;

            const extents = ch.size.scalMul(0.5);

            const dst = Rect2f{
                .x = offsetx + x + ch.bearing.x + extents.x,
                .y = y - ch.bearing.y + extents.y,
                .w = ch.size.x,
                .h = ch.size.y,
            };

            const textureSrc = Rect2f{
                .x = 0.5,
                .y = 0.5,
                .w = 1.0,
                .h = 1.0,
            };

            try glyphs.append(.{
                .dst = dst,
                .uv = textureSrc,
                .texture = ch.texture,
                .color = opts.color,
            });
        }
    }

    const total_height = y + @intToFloat(f32, ctx.face_line_height >> 6);
    for (glyphs.span()) |*g| {
        g.dst.y -= total_height / 2;
    }

    return glyphs;
}
