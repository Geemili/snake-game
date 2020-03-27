const builtin = @import("builtin");
const std = @import("std");
usingnamespace @import("c.zig");

pub const Renderer = @import("../renderer.zig").Renderer;
const common = @import("../common.zig");
const Rect = common.Rect;
const Vec2f = common.Vec2f;
pub const sdl = @import("../sdl.zig");
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

pub const ComponentRenderer = struct {
    alloc: *std.mem.Allocator,
    current_component: ?RenderedComponent = null,

    pub fn init(alloc: *std.mem.Allocator) !@This() {
        return @This(){
            .alloc = alloc,
        };
    }

    pub fn update(self: *@This(), new_component: *const Component) RenderingError!void {
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
            component.render(renderer, space) catch unreachable;
        }
    }

    pub fn clear(self: *@This()) void {
        self.current_component = null;
    }

    pub fn deinit(self: *@This()) void {
        SDL_FreeSurface(self.SDL_Surface);
    }
};

const RenderedComponent = struct {
    alloc: *std.mem.Allocator,
    component: union(ComponentTag) {
        Text: Text,
        Button: Button,
        Container: Container,

        pub fn deinit(self: *@This(), component: *RenderedComponent) void {
            switch (self.*) {
                .Text => |text| component.alloc.free(text.text),
                .Button => |button| component.alloc.free(button.text),
                .Container => |*container| container.deinit(component),
            }
        }
    },

    pub fn remove(self: *@This()) void {
        self.component.deinit(self);
    }

    pub fn deinit(self: *@This()) void {
        self.component.deinit(self);
    }

    pub fn render(self: *@This(), renderer: *Renderer, space: Rect) RenderingError!void {
        switch (self.component) {
            .Text => |*self_text| self_text.render(renderer, space),
            .Button => |*self_button| self_button.render(renderer, space),
            .Container => |*self_container| try self_container.render(self, renderer, space),
        }
    }
};

const Text = struct {
    text: []const u8,

    pub fn render(self: *@This(), renderer: *Renderer, space: Rect) void {
        const size = Vec2f{
            .x = @intToFloat(f32, space.w),
            .y = @intToFloat(f32, space.h),
        };
        const center = (Vec2f{
            .x = @intToFloat(f32, space.x),
            .y = @intToFloat(f32, space.y),
        }).add(&size.scalMul(0.5));
        renderer.pushRect(center, size.scalMul(0.8), .{ .r = 200, .g = 230, .b = 200 }, 0);
    }
};

const Button = struct {
    text: []const u8,
    events: Events,

    pub fn render(self: *@This(), renderer: *Renderer, space: Rect) void {
        const size = Vec2f{
            .x = @intToFloat(f32, space.w) / 2,
            .y = @intToFloat(f32, space.h) / 2,
        };
        const center = (Vec2f{
            .x = @intToFloat(f32, space.x),
            .y = @intToFloat(f32, space.y),
        }).add(&size);
        renderer.pushRect(center, size, .{ .r = 255, .g = 255, .b = 255 }, 0);
    }
};

pub const Container = struct {
    layout: Layout,
    children: std.ArrayList(RenderedComponent),

    pub fn removeChildren(self: *@This()) void {
        for (self.children.span()) |*child| {
            child.remove();
        }
        self.children.resize(0) catch unreachable;
    }

    pub fn deinit(self: *@This(), component: *RenderedComponent) void {
        for (self.children.span()) |*child| {
            child.deinit();
        }
        self.children.deinit();
    }

    pub fn render(self: *@This(), component: *RenderedComponent, renderer: *Renderer, space: Rect) RenderingError!void {
        switch (self.layout) {
            .Flex => |orientation| {
                const axisSize = switch (orientation) {
                    .Horizontal => space.w,
                    .Vertical => space.h,
                };
                const space_per_component = @divTrunc(axisSize, @intCast(i32, self.children.span().len));
                for (self.children.span()) |*child, idx| {
                    const childSpace = switch (orientation) {
                        .Horizontal => Rect{
                            .x = space.x + space_per_component * @intCast(i32, idx),
                            .y = space.y,
                            .w = space_per_component,
                            .h = space.h,
                        },
                        .Vertical => Rect{
                            .x = space.x,
                            .y = space.y + space_per_component * @intCast(i32, idx),
                            .w = space.w,
                            .h = space_per_component,
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
                    var spots = std.ArrayList(Cell).init(component.alloc);
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
                } else if (template.rows) |rows| {
                    // Render
                    const denom = denom_calc: {
                        var denom: u32 = 0;
                        for (rows) |row_fraction| {
                            denom += row_fraction;
                        }
                        break :denom_calc denom;
                    };
                    const height_per_component = @divTrunc(space.h, @intCast(i32, denom));
                    const num_cols = @divFloor(self.children.len, rows.len) + 1;
                    const width_per_component = @divTrunc(space.w, @intCast(i32, num_cols));
                    var yFracUsed: u32 = 0; // Amount of y fractions used
                    for (self.children.span()) |*child, idx| {
                        const y = idx % rows.len;
                        if (y == 0) {
                            yFracUsed = 0;
                        }
                        const x = @divFloor(idx, rows.len);
                        const yFrac = rows[y];
                        try child.render(renderer, Rect{
                            .x = space.x + @intCast(i32, x) * width_per_component,
                            .y = space.y + @intCast(i32, yFracUsed) * height_per_component,
                            .w = width_per_component,
                            .h = height_per_component * @intCast(i32, yFrac),
                        });
                        yFracUsed += yFrac;
                    }
                } else if (template.columns) |columns| {} else {
                    std.debug.assert(false); // Invalid grid layout; at least one of rows, columns, or areas must be defined
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
                .alloc = alloc,
                .component = .{
                    .Text = .{ .text = try std.mem.dupe(alloc, u8, text) },
                },
            };
        },
        .Button => |button| {
            return RenderedComponent{
                .alloc = alloc,
                .component = .{
                    .Button = .{
                        .text = try std.mem.dupe(alloc, u8, button.text),
                        .events = button.events,
                    },
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
                .alloc = alloc,
                .component = .{
                    .Container = .{
                        .layout = container.layout,
                        .children = rendered_children,
                    },
                },
            };
        },
    }
}
