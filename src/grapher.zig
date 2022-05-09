const std = @import("std");
const builtin = @import("builtin");
const liu = @import("liu");

const wasm = liu.wasm;
pub const WasmCommand = void;
pub usingnamespace wasm;

const ArrayList = std.ArrayList;
const Vec2 = @Vector(2, f32);

const ext = struct {
    extern fn setTriangles(obj: wasm.Obj) void;

    fn onClickExt(posX: f32, posY: f32, width: f32, height: f32) callconv(.C) void {
        const pos = translatePos(posX, posY, .{ width, height });
        onClick(pos) catch @panic("onClick failed");
    }

    fn printExt(msg: wasm.Obj) callconv(.C) void {
        print(msg) catch @panic("print failed");
    }

    fn initExt() callconv(.C) void {
        init() catch @panic("init failed");
    }
};

comptime {
    @export(ext.onClickExt, .{ .name = "onClick", .linkage = .Strong });
    @export(ext.printExt, .{ .name = "print", .linkage = .Strong });
    @export(ext.initExt, .{ .name = "init", .linkage = .Strong });
}

// First 36 triangles are reserved for the lines created during triangle drawing
var triangles: ArrayList(f32) = undefined;
var temp_type: enum { triangle, line } = .triangle;
var temp_points: std.BoundedArray(f32, 6) = undefined;
var temp_begin: usize = 0;

fn translatePos(posX: f32, posY: f32, dims: Vec2) Vec2 {
    return .{ posX * 2 / dims[0] - 1, -(posY * 2 / dims[1] - 1) };
}

fn drawLineInto(buffer: *[12]f32, from: Vec2, to: Vec2, dims: Vec2) void {
    const vector = to - from;
    const rot90: Vec2 = .{ -vector[1], vector[0] };

    const tangent_len = @sqrt(rot90[0] * rot90[0] + rot90[1] * rot90[1]);
    const tangent = rot90 * @splat(2, 2 / tangent_len) / dims;

    // first triangle, drawn clockwise
    buffer[0..2].* = from + tangent;
    buffer[2..4].* = to + tangent;
    buffer[4..6].* = from - tangent;

    // second triangle, drawn clockwise
    buffer[6..8].* = from - tangent;
    buffer[8..10].* = to + tangent;
    buffer[10..12].* = to - tangent;
}

export fn onRightClick() void {
    if (temp_points.len > 2) {
        triangles.items.len = temp_begin;
        temp_points.len = 2;

        const obj = wasm.out.slice(triangles.items);
        ext.setTriangles(obj);

        return;
    }

    switch (temp_type) {
        .triangle => {
            temp_type = .line;
            wasm.out.post(.info, "using line now", .{});
        },
        .line => {
            temp_type = .triangle;
            wasm.out.post(.info, "using triangle now", .{});
        },
    }
}

export fn onMove(posX: f32, posY: f32, width: f32, height: f32) void {
    const dims: Vec2 = .{ width, height };
    const pos = translatePos(posX, posY, dims);

    const len = temp_points.len;

    std.debug.assert(len >= 2);

    temp_points.slice()[(len - 2)..][0..2].* = pos;

    if (temp_points.len < 4) return;

    const prev: Vec2 = temp_points.slice()[(len - 4)..][0..2].*;

    const data_begin = temp_begin + ((len - 4) / 2 * 12);
    const data = triangles.items[data_begin..];
    drawLineInto(data[0..12], prev, pos, dims);

    temp_type: {
        if (temp_type == .triangle) {
            if (temp_points.len < 6) break :temp_type;

            const first = temp_points.slice()[0..2].*;
            const data2 = triangles.items[(data_begin + 12)..];
            drawLineInto(data2[0..12], first, pos, dims);
        }
    }

    const obj = wasm.out.slice(triangles.items);
    ext.setTriangles(obj);
}

pub fn onClick(pos: Vec2) !void {
    std.debug.assert(temp_points.len >= 2);
    temp_points.slice()[(temp_points.len - 2)..][0..2].* = pos;

    switch (temp_type) {
        .triangle => {
            if (temp_points.len >= 6) {
                triangles.items.len = temp_begin;
                try triangles.appendSlice(temp_points.slice());
                temp_begin = triangles.items.len;
                temp_points.len = 2;

                const obj = wasm.out.slice(triangles.items);
                ext.setTriangles(obj);

                wasm.out.post(.success, "new triangle!", .{});

                return;
            }

            if (temp_points.len == 4) {
                try triangles.appendSlice(&.{
                    0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0,
                });
            }
        },

        .line => if (temp_points.len >= 4) {
            temp_begin = triangles.items.len;
            temp_points.len = 2;
            return;
        },

        // else => return,
    }

    const len = temp_points.len;
    temp_points.buffer[len..][0..2].* = pos;
    temp_points.len += 2;

    try triangles.appendSlice(&.{
        0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0,
    });
}

pub fn print(msg: wasm.Obj) !void {
    var _temp = liu.Temp.init();
    const temp = _temp.allocator();
    defer _temp.deinit();

    const message = try wasm.in.string(msg, temp);
    wasm.out.post(.info, "{s}!", .{message});

    const obj = wasm.out.slice(triangles.items);
    ext.setTriangles(obj);
}

pub fn init() !void {
    wasm.initIfNecessary();
    temp_points = try std.BoundedArray(f32, 6).init(2);
    triangles = ArrayList(f32).init(liu.Pages);

    temp_points.buffer[0..2].* = .{ 0, 0 };

    std.log.info("WASM initialized!", .{});
}
