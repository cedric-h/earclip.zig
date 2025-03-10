// vim: sw=4 ts=4 expandtab smartindent
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const std = @import("std");
const shd = @import("shaders/triangle.glsl.zig");
const earclip = @import("earclip").earclip;

// This works on mac but not windows, so we do it in software at the end of our shader.
// So if you supply a color in this app, it's in Linear! Plan accordingly.
const SRGB = false;

const Clr = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    fn premultiplied(r: u8, g: u8, b: u8, a: u8) @This() {
        var af: f32 = @floatFromInt(a);
        af /= 255.0;
        return .{ .r = @intFromFloat(af * @as(f32, @floatFromInt(r))),
                  .g = @intFromFloat(af * @as(f32, @floatFromInt(g))),
                  .b = @intFromFloat(af * @as(f32, @floatFromInt(b))),
                  .a = a                                              };
    }

    fn scaleRgb(self: @This(), f: f32) @This() {
        // TODO: HSL
        return .{ .r = @intFromFloat(f * @as(f32, @floatFromInt(self.r))),
                  .g = @intFromFloat(f * @as(f32, @floatFromInt(self.g))),
                  .b = @intFromFloat(f * @as(f32, @floatFromInt(self.b))),
                  .a = self.a      };
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

const PointKind = enum { none, vertex, midpt };

const state = struct {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = state.general_purpose_allocator.allocator();

    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var pass_action: sg.PassAction = .{};

    var mouse_x: f32 = 0;
    var mouse_y: f32 = 0;
    var mouse_down_x: f32 = 0;
    var mouse_down_y: f32 = 0;
    var mouse_down_pt_idx: usize = 0;
    var mouse_down_pt_kind: PointKind = .none;
    var mouse_down_pt_x: f32 = 0;
    var mouse_down_pt_y: f32 = 0;
    var mouse_down: bool = false;

    var shape: std.ArrayList([2]f32) = .init(gpa);
    var earclip_out: std.ArrayList(u16) = .init(gpa);

    var hovered_pt_idx: usize = 0;
    var hovered_pt_kind: PointKind = .none;

    var vrts: std.ArrayList(Vtx) = .init(gpa);
    var idxs: std.ArrayList(u16) = .init(gpa);
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    state.shape.appendSlice(&[_][2]f32{
        .{    0,  150 },
        .{ -300, -150 },
        .{  300, -150 },
    }) catch unreachable;

    state.vrts.ensureTotalCapacity(1 << 13) catch unreachable;
    state.idxs.ensureTotalCapacity(1 << 14) catch unreachable;
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

fn drawCircle(center_x: f32, center_y: f32, radius: f32, clr: Clr) void {
    drawNgon(center_x, center_y, radius, 20, clr);
}

fn drawRhombus(center_x: f32, center_y: f32, radius: f32, clr: Clr) void {
    drawNgon(center_x, center_y, radius, 4, clr);
}

fn drawNgon(center_x: f32, center_y: f32, radius: f32, n: usize, clr: Clr) void {
    const vbuf_i: u16 = @truncate(state.vrts.items.len);

    state.vrts.appendAssumeCapacity(.{
        .pos = .{
            .x = center_x,
            .y = center_y,
            .z = 0.5,
        },
        .clr = clr
    });

    for (0..n) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        state.vrts.appendAssumeCapacity(.{
            .pos = .{
                .x = center_x + @cos(t * std.math.pi * 2.0) * radius,
                .y = center_y + @sin(t * std.math.pi * 2.0) * radius,
                .z = 0.5,
            },
            .clr = clr
        });

        const i_u16: u16 = @truncate(i);
        const n_u16: u16 = @truncate(n);
        state.idxs.appendSliceAssumeCapacity(&[_]u16{
            vbuf_i + 0, vbuf_i + if (i == 0) n_u16 else i_u16, vbuf_i + i_u16 + 1,
        });
    }
}

fn drawTriangle(a: [2]f32, b: [2]f32, c: [2]f32, clr: Clr) void {
    const vbuf_i: u16 = @truncate(state.vrts.items.len);

    state.vrts.appendSliceAssumeCapacity(&[_]Vtx{
        .{ .pos = .{ .x = a[0], .y = a[1], .z = 0.5 }, .clr = clr },
        .{ .pos = .{ .x = b[0], .y = b[1], .z = 0.5 }, .clr = clr },
        .{ .pos = .{ .x = c[0], .y = c[1], .z = 0.5 }, .clr = clr }
    });

    state.idxs.appendSliceAssumeCapacity(&[_]u16{ vbuf_i + 0, vbuf_i + 1, vbuf_i + 2 });
}

fn drawLine(a_x: f32, a_y: f32, b_x: f32, b_y: f32, thickness: f32, clr: Clr) void {
    const vbuf_i: u16 = @truncate(state.vrts.items.len);

    var dx = a_x - b_x;
    var dy = a_y - b_y;
    dx /= @sqrt(dx*dx + dy*dy);
    dy /= @sqrt(dx*dx + dy*dy);
    const px = -dy * thickness * 0.5;
    const py =  dx * thickness * 0.5;

    state.vrts.appendSliceAssumeCapacity(&[_]Vtx{
        .{ .pos = .{ .x = a_x + px, .y = a_y + py, .z = 0.5 }, .clr = clr },
        .{ .pos = .{ .x = a_x - px, .y = a_y - py, .z = 0.5 }, .clr = clr },
        .{ .pos = .{ .x = b_x + px, .y = b_y + py, .z = 0.5 }, .clr = clr },
        .{ .pos = .{ .x = b_x - px, .y = b_y - py, .z = 0.5 }, .clr = clr },
    });

    state.idxs.appendSliceAssumeCapacity(&[_]u16{
        vbuf_i + 0, vbuf_i + 1, vbuf_i + 2,
        vbuf_i + 2, vbuf_i + 3, vbuf_i + 1
    });
}

// see https://floooh.github.io/sokol-html5/events-sapp.html
export fn input(event: ?*const sapp.Event) void {
    const ev = event.?;

    if (ev.type == .MOUSE_DOWN) {
        state.mouse_down = true;
        state.mouse_down_x = ev.mouse_x;
        state.mouse_down_y = ev.mouse_y;
        state.mouse_down_pt_idx  = state.hovered_pt_idx;
        state.mouse_down_pt_kind = state.hovered_pt_kind;
        if (state.hovered_pt_kind != .none) {
            state.mouse_down_pt_x = ev.mouse_x;
            state.mouse_down_pt_y = ev.mouse_y;
        }
    }
    if (ev.type == .MOUSE_UP  ) state.mouse_down = false;

    if (ev.type == .MOUSE_MOVE) {
        // I may be crazy, but I think "zero is the center of the screen"
        // is actually a fairly ergonomic coordinate space for a tool like this.
        state.mouse_x = -sapp. widthf()*0.5 + ev.mouse_x;
        state.mouse_y =  sapp.heightf()*0.5 - ev.mouse_y;
    }

    if (ev.type == .KEY_DOWN and ev.key_code == .ESCAPE)
        sapp.requestQuit();

    if (ev.type == .KEY_DOWN and ev.key_code == .Q and (ev.modifiers & sapp.modifier_super) > 0)
        sapp.requestQuit();
}

export fn frame() void {
    state.vrts.clearRetainingCapacity();
    state.idxs.clearRetainingCapacity();

    const clr_line     = Clr.premultiplied(155, 155, 155, 255);
    const clr_vertex   = Clr.premultiplied(255,  20, 255, 255);
    const clr_tri_fill = Clr.premultiplied(125,  10, 125,  10);
    const clr_tri_edge = Clr.premultiplied(125,  10, 125,  20);
    const clr_midpt    = Clr.premultiplied(125,  10, 125, 255);

    if (state.mouse_down and state.mouse_down_pt_kind != .none) {
        if (state.mouse_down_pt_kind == .midpt) {
            const shape = state.shape.items;
            const idx = state.mouse_down_pt_idx;
            const next = if ((idx + 1) == shape.len) 0 else idx + 1;
            const c_x = std.math.lerp(shape[idx + 0][0], shape[next][0], 0.5);
            const c_y = std.math.lerp(shape[idx + 0][1], shape[next][1], 0.5);
            state.shape.insert(idx, .{ c_x, c_y }) catch unreachable;
            state.mouse_down_pt_kind = .vertex;
        }

        if (state.mouse_down_pt_kind == .vertex) {
            const dx = state.mouse_x - state.mouse_down_x;
            const dy = state.mouse_y - state.mouse_down_y;
            state.shape.items[state.mouse_down_pt_idx][0] = state.mouse_down_pt_x + dx;
            state.shape.items[state.mouse_down_pt_idx][1] = state.mouse_down_pt_y + dy;
        }
    }

    state.earclip_out.clearRetainingCapacity();
    earclip(&state.gpa, &state.shape.items, &state.earclip_out);
    for (0..(state.earclip_out.items.len / 3)) |i| {
        const a = state.shape.items[state.earclip_out.items[i*3 + 0]];
        const b = state.shape.items[state.earclip_out.items[i*3 + 1]];
        const c = state.shape.items[state.earclip_out.items[i*3 + 2]];
        drawTriangle(a, b, c, clr_tri_fill);
        drawLine(a[0], a[1], b[0], b[1], 5, clr_tri_edge);
    }

    var next_hovered_pt_dist: f32 = std.math.inf(f64);
    var next_hovered_pt_idx: usize = 0;
    var next_hovered_pt_kind: PointKind = .none;
    {
        for (0..state.shape.items.len) |i| {
            const before = if (i == 0) state.shape.items.len else i;
            const b = state.shape.items[before - 1];
            const p = state.shape.items[i];
            drawLine(b[0], b[1], p[0], p[1], 8.0, clr_line);

            const c_x = std.math.lerp(b[0], p[0], 0.5);
            const c_y = std.math.lerp(b[1], p[1], 0.5);
            const mouse_dist = @sqrt((c_x - state.mouse_x)*(c_x - state.mouse_x) +
                                     (c_y - state.mouse_y)*(c_y - state.mouse_y)) - 10.0;
            if (mouse_dist < 0 and mouse_dist < next_hovered_pt_dist) {
                next_hovered_pt_idx = @bitCast(i);
                next_hovered_pt_dist = mouse_dist;
                next_hovered_pt_kind = .midpt;
            }
            const hovered = i == state.hovered_pt_idx and state.hovered_pt_kind == .midpt;
            const radius: f32 = if (hovered) 15 else 12;
            drawRhombus(c_x, c_y, radius, clr_midpt.scaleRgb(if (hovered) 0.6 else 1.0));
        }

        for (state.shape.items, 0..) |p, i| {
            const mouse_dist = @sqrt((p[0] - state.mouse_x)*(p[0] - state.mouse_x) +
                                     (p[1] - state.mouse_y)*(p[1] - state.mouse_y)) - 10.0;
            if (mouse_dist < 0 and mouse_dist < next_hovered_pt_dist) {
                next_hovered_pt_idx = @bitCast(i);
                next_hovered_pt_dist = mouse_dist;
                next_hovered_pt_kind = .vertex;
            }
            const hovered = i == state.hovered_pt_idx and state.hovered_pt_kind == .vertex;
            const radius: f32 = if (hovered) 15 else 12;
            drawCircle(p[0], p[1], radius, clr_vertex.scaleRgb(if (hovered) 0.6 else 1.0));
        }
    }
    state.hovered_pt_idx  = next_hovered_pt_idx;
    state.hovered_pt_kind = next_hovered_pt_kind;

    sg.updateBuffer(state.bind.vertex_buffers[0], sg.asRange(state.vrts.items));
    sg.updateBuffer(state.bind.index_buffer, sg.asRange(state.idxs.items));

    // default pass-action clears to grey
    var chain = sglue.swapchain();
    if (SRGB) chain.color_format = .SRGB8A8;
    sg.beginPass(.{ .action = state.pass_action, .swapchain = chain });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);

    {
        const zoom_x = 2.0 / sapp. widthf();
        const zoom_y = 2.0 / sapp.heightf();
        const vs_params: shd.VsParams = .{ .u_zoom = .{ zoom_x, zoom_y }, .u_pos = .{ 0, 0 } };
        sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    }

    sg.draw(0, @truncate(state.idxs.items.len), 1);
    sg.endPass();
    sg.commit();
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

        // these make it look nice
        .sample_count = 8,
        .high_dpi = true,

        .width = 1280,
        .height = 960,
        .icon = .{ .sokol_default = true },
        .window_title = "triangle.zig",
        .logger = .{ .func = slog.func },
    });
}
