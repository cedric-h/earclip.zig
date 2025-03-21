// for this output to make sense, see http://filmicworlds.com/blog/linear-space-lighting-i-e-gamma/
// This file is just a small experiment I made to see how SRGB works in sokol.
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const std = @import("std");
const shd = @import("shaders/srgb.glsl.zig");

// This works on mac but not windows, so we do it in software at the end of our shader.
// So if you supply a color in this app, it's in Linear! Plan accordingly.
const SRGB = false;

const Clr = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    fn premultiplied(r: u8, g: u8, b: u8, a: u8) Clr {
        var af: f32 = @floatFromInt(a);
        af /= 255.0;
        return .{ .r = @intFromFloat(af * @as(f32, @floatFromInt(r))),
                  .g = @intFromFloat(af * @as(f32, @floatFromInt(g))),
                  .b = @intFromFloat(af * @as(f32, @floatFromInt(b))),
                  .a = a                                              };
    }
};

const Vtx = struct {
    pos: struct {
        x: f32,
        y: f32,
        z: f32
    },
    clr: Clr,
};

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var pass_action: sg.PassAction = .{};

    var vrts: std.ArrayList(Vtx) = undefined;
    var idxs: std.ArrayList(u16) = undefined;
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();
    state.vrts = std.ArrayList(Vtx).initCapacity(gpa, 1 << 13) catch unreachable;
    state.idxs = std.ArrayList(u16).initCapacity(gpa, 1 << 14) catch unreachable;
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{ .usage = .STREAM, .size = state.vrts.capacity * @sizeOf(Vtx) });
    state.bind.index_buffer = sg.makeBuffer(.{ .usage = .STREAM, .size = state.idxs.capacity * @sizeOf(u16), .type = .INDEXBUFFER });

    // create a shader and pipeline object
    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.triangleShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_triangle_position].format = .FLOAT3;
            l.attrs[shd.ATTR_triangle_color0].format = .UBYTE4N;
            break :init l;
        },
        .colors = @splat(.{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .ONE,
                .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA
            },
            .pixel_format = if (SRGB) .SRGB8A8 else .DEFAULT
        })
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1 }
    };
}

fn drawBox(min_x: f32, min_y: f32, max_x: f32, max_y: f32, clr: Clr) void {
    const vbuf_i: u16 = @truncate(state.vrts.items.len);
    state.vrts.appendSliceAssumeCapacity(&[_]Vtx{
        .{ .pos = .{ .x = max_x, .y = max_y, .z = 0.5 }, .clr = clr },
        .{ .pos = .{ .x = max_x, .y = min_y, .z = 0.5 }, .clr = clr },
        .{ .pos = .{ .x = min_x, .y = min_y, .z = 0.5 }, .clr = clr },
        .{ .pos = .{ .x = min_x, .y = max_y, .z = 0.5 }, .clr = clr },
    });
    state.idxs.appendSliceAssumeCapacity(&[_]u16{
        vbuf_i + 0, vbuf_i + 1, vbuf_i + 2,
        vbuf_i + 0, vbuf_i + 2, vbuf_i + 3
    });
}

export fn frame() void {
    // @import("std").debug.print("{}\n\n", .{ sg.queryPixelformat(.SRGB8A8) });

    state.vrts.clearRetainingCapacity();
    state.idxs.clearRetainingCapacity();

    const third: f32 = 1.0 / 3.0;
    const bar_count = 480;
    const bar_countf = @as(comptime_float, bar_count);
    for (0..bar_count) |i| {
        const y = (@as(f32, @floatFromInt(i)) - bar_countf*0.5) / (bar_countf*0.5);
        drawBox(-1.0, y, 1.0, y + 1.0 / (bar_countf*0.5), Clr.premultiplied(255, 255, 255, if (i % 2 == 0) 0 else 255));
    }
    drawBox(-third,  1.0, third, 0.0, Clr.premultiplied(255, 255, 255, 128));
    drawBox(-third, -1.0, third, 0.0, Clr.premultiplied(255, 255, 255, 187));

    sg.updateBuffer(state.bind.vertex_buffers[0], sg.asRange(state.vrts.items));
    sg.updateBuffer(state.bind.index_buffer, sg.asRange(state.idxs.items));

    // default pass-action clears to grey
    var chain = sglue.swapchain();
    if (SRGB) chain.color_format = .SRGB8A8;
    sg.beginPass(.{ .action = state.pass_action, .swapchain = chain });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.draw(0, @truncate(state.idxs.items.len), 1);
    sg.endPass();
    sg.commit();
}

// see https://floooh.github.io/sokol-html5/events-sapp.html
export fn input(event: ?*const sapp.Event) void {
    const ev = event.?;

    if (ev.type == .KEY_DOWN and ev.key_code == .ESCAPE)
        sapp.requestQuit();

    if (ev.type == .KEY_DOWN and ev.key_code == .Q and (ev.modifiers & sapp.modifier_super) > 0)
        sapp.requestQuit();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = 640,
        .height = 480,
        .icon = .{ .sokol_default = true },
        .window_title = "triangle.zig",
        .logger = .{ .func = slog.func },
    });
}
