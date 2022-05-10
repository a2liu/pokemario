const std = @import("std");
const builtin = @import("builtin");
const liu = @import("liu");

const wasm = liu.wasm;
pub const WasmCommand = void;
pub usingnamespace wasm;

const ArrayList = std.ArrayList;
const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

const ext = struct {
    extern fn setTriangles(obj: wasm.Obj) void;
    extern fn setColors(obj: wasm.Obj) void;

    fn onClickExt(posX: f32, posY: f32, width: f32, height: f32) callconv(.C) void {
        const pos = translatePos(posX, posY, .{ width, height });
        onClick(pos) catch @panic("onClick failed");
    }

    fn initExt() callconv(.C) void {
        init() catch @panic("init failed");
    }
};

comptime {
    @export(ext.onClickExt, .{ .name = "onClick", .linkage = .Strong });
    @export(ext.initExt, .{ .name = "init", .linkage = .Strong });
}

const Render = struct {
    const List = std.ArrayListUnmanaged;
    const Self = @This();

    dims: Vec2 = Vec2{ 0, 0 },
    triangles: List(f32) = .{},
    colors: List(f32) = .{},
    temp_begin: ?usize = null,

    fn render(self: *Self) void {
        const mark = wasm.watermark();
        defer wasm.setWatermark(mark);

        const obj = wasm.out.slice(self.triangles.items);
        ext.setTriangles(obj);
        const obj2 = wasm.out.slice(self.colors.items);
        ext.setColors(obj2);
    }

    pub fn dropTempData(self: *Self) void {
        const temp_begin = if (self.temp_begin) |t| t else return;

        self.triangles.items.len = temp_begin * 2;
        self.colors.items.len = temp_begin * 3;
        self.temp_begin = null;

        self.render();
    }

    pub fn useTempData(self: *Self) void {
        std.debug.assert(self.temp_begin != null);

        self.temp_begin = null;
    }

    pub fn startTempStorage(self: *Self) void {
        std.debug.assert(self.temp_begin == null);

        self.temp_begin = self.triangles.items.len / 2;
    }

    pub fn addTriangle(self: *Self, pts: [3]Point) !void {
        const pos = .{
            pts[0].pos[0], pts[0].pos[1],
            pts[1].pos[0], pts[1].pos[1],
            pts[2].pos[0], pts[2].pos[1],
        };

        const color = .{
            pts[0].color[0], pts[0].color[1], pts[0].color[2],
            pts[1].color[0], pts[1].color[1], pts[1].color[2],
            pts[2].color[0], pts[2].color[1], pts[2].color[2],
        };

        try self.triangles.appendSlice(liu.Pages, &pos);
        try self.colors.appendSlice(liu.Pages, &color);

        self.render();
    }

    pub fn temp(self: *Self) usize {
        if (self.temp_begin) |t| {
            return t;
        }

        unreachable;
    }

    pub fn pushVert(self: *Self, count: usize) !void {
        try self.triangles.appendNTimes(liu.Pages, 0, count * 2);
        try self.colors.appendNTimes(liu.Pages, 0.5, count * 3);
    }

    pub fn drawLine(self: *Self, vertex: usize, from: Point, to: Point) void {
        const pos = self.triangles.items[(vertex * 2)..];
        const color = self.colors.items[(vertex * 3)..];

        const vector = to.pos - from.pos;
        const rot90: Vec2 = .{ -vector[1], vector[0] };

        const halfLineWidthPx: f32 = 1.5;
        const tangent_len = @sqrt(rot90[0] * rot90[0] + rot90[1] * rot90[1]);
        const tangent = rot90 * @splat(2, halfLineWidthPx * 2 / tangent_len) / self.dims;

        // first triangle, drawn clockwise
        pos[0..2].* = from.pos + tangent;
        color[0..3].* = from.color;
        pos[2..4].* = to.pos + tangent;
        color[3..6].* = to.color;
        pos[4..6].* = from.pos - tangent;
        color[6..9].* = from.color;

        // second triangle, drawn clockwise
        pos[6..8].* = from.pos - tangent;
        color[9..12].* = from.color;
        pos[8..10].* = to.pos + tangent;
        color[12..15].* = to.color;
        pos[10..12].* = to.pos - tangent;
        color[15..18].* = to.color;

        self.render();
    }
};

const Tool = enum {
    none,
    line,
    triangle,
};

var render: Render = .{};

// Need to do it this way until pointer aliasing works properly with tagged
// unions at global scope
var tool_line: LineTool = .{};
var tool_triangle: TriangleTool = .{};
var tool: Tool = .triangle;

var current_color: Vec3 = Vec3{ 0.5, 0.5, 0.5 };

var obj_line: wasm.Obj = undefined;
var obj_triangle: wasm.Obj = undefined;
var obj_none: wasm.Obj = undefined;

fn translatePos(posX: f32, posY: f32, dims: Vec2) Vec2 {
    return .{ posX * 2 / dims[0] - 1, -(posY * 2 / dims[1] - 1) };
}

const Point = struct {
    pos: Vec2,
    color: Vec3,
};

const LineTool = struct {
    prev: ?Point = null,

    const Self = @This();

    fn reset(self: *Self) void {
        self.prev = null;

        render.dropTempData();
    }

    fn move(self: *Self, pos: Vec2) void {
        const prev = if (self.prev) |prev| prev else return;
        const temp = render.temp();
        render.drawLine(temp, prev, .{ .pos = pos, .color = current_color });

        return;
    }

    fn click(self: *Self, pos: Vec2) !void {
        if (self.prev) |_| {
            render.useTempData();
            self.prev = null;
            return;
        }

        render.startTempStorage();
        self.prev = .{ .pos = pos, .color = current_color };

        try render.pushVert(6);
    }
};

const TriangleTool = struct {
    first: ?Point = null,
    second: ?Point = null,

    const Self = @This();

    fn reset(self: *Self) void {
        self.first = null;
        self.second = null;

        render.dropTempData();
    }

    fn move(self: *Self, pos: Vec2) void {
        const pt = Point{ .pos = pos, .color = current_color };

        const first = if (self.first) |first| first else return;

        const temp = render.temp();

        const second = if (self.second) |second| second else {
            render.drawLine(temp, first, pt);
            return;
        };

        render.drawLine(temp + 6, first, pt);
        render.drawLine(temp + 12, second, pt);

        return;
    }

    fn click(self: *Self, pos: Vec2) !void {
        const first = if (self.first) |first| first else {
            render.startTempStorage();

            self.first = .{ .pos = pos, .color = current_color };
            try render.pushVert(6);

            return;
        };

        const second = if (self.second) |second| second else {
            self.second = .{ .pos = pos, .color = current_color };

            try render.pushVert(12);
            return;
        };

        _ = self.reset();

        render.dropTempData();
        const pt = Point{ .pos = pos, .color = current_color };
        try render.addTriangle(.{ first, second, pt });
    }
};

export fn setColor(r: f32, g: f32, b: f32) void {
    current_color = Vec3{ r, g, b };
}

export fn currentTool() wasm.Obj {
    switch (tool) {
        .none => return obj_none,
        .triangle => return obj_triangle,
        .line => return obj_line,
    }
}

export fn toggleTool() void {
    switch (tool) {
        .none => {
            tool = .triangle;
        },
        .triangle => {
            const draw = &tool_triangle;
            draw.reset();

            tool = .line;
        },
        .line => {
            const draw = &tool_line;
            draw.reset();

            tool = .none;
        },
    }
}

export fn onRightClick() void {
    switch (tool) {
        .none => return,
        .triangle => {
            const draw = &tool_triangle;
            draw.reset();
        },
        .line => {
            const draw = &tool_line;
            draw.reset();
        },
    }
}

export fn onMove(posX: f32, posY: f32, width: f32, height: f32) void {
    const dims: Vec2 = .{ width, height };
    const pos = translatePos(posX, posY, dims);

    render.dims = dims;

    switch (tool) {
        .none => return,
        .triangle => {
            const draw = &tool_triangle;
            draw.move(pos);
        },
        .line => {
            const draw = &tool_line;
            draw.move(pos);
        },
    }
}

pub fn onClick(pos: Vec2) !void {
    switch (tool) {
        .none => return,
        .triangle => {
            const draw = &tool_triangle;
            try draw.click(pos);
        },
        .line => {
            const draw = &tool_line;
            try draw.click(pos);
        },
    }
}

pub fn init() !void {
    wasm.initIfNecessary();

    obj_line = wasm.out.string("line");
    obj_triangle = wasm.out.string("triangle");
    obj_none = wasm.out.string("none");

    wasm.out.post(.info, "WASM initialized!", .{});
}