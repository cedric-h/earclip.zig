// vim: sw=4 ts=4 expandtab smartindent
const std = @import("std");

pub fn earclip(
    allo: std.mem.Allocator,
    vertices_slice: []const [2]f32,
    indices: *std.ArrayList(u16)
) !void {
    var vertices = try std.ArrayList([2]f32).initCapacity(allo, vertices_slice.len);
    defer vertices.deinit();

    var original_indices = try std.ArrayList(u16).initCapacity(allo, vertices_slice.len);
    defer original_indices.deinit();

    // initialize the arrays, reversing along the way if necessary
    {
        // determine if it's necessary to reverse the shape
        // (otherwise determinants will have wrong sign, convex check will fail)
        const reverse: bool = rev: {
            var signed_area_sum: f32 = 0;

            const v = vertices_slice;
            var j = v.len - 1;
            for (0..v.len) |i| {
                signed_area_sum += (v[j][0] - v[i][0]) * (v[i][1] + v[j][1]);
                j = i;
            }

            break :rev (signed_area_sum < 0);
        };

        const n = vertices_slice.len;
        for (0..n) |j| {
            const i = if (reverse) n - 1 - j else j;
            vertices.appendAssumeCapacity(vertices_slice[i]);
            original_indices.appendAssumeCapacity(@truncate(i));
        }
    }

    // prevents infinite loop
    var escape_hatch: usize = 0;

    // continue clipping until we run out of ears
    while (vertices.items.len >= 3) {
        for (vertices.items, 0..) |_, i| {
            const a = (i + 0) % vertices.items.len;
            const b = (i + 1) % vertices.items.len;
            const c = (i + 2) % vertices.items.len;

            const is_ear = is_ear: {
                const v1 = vertices.items[a];
                const v2 = vertices.items[b];
                const v3 = vertices.items[c];

                // convex check
                {
                    const d1x = v1[0] - v2[0];
                    const d1y = v1[1] - v2[1];
                    const d2x = v2[0] - v3[0];
                    const d2y = v2[1] - v3[1];
                    if ((d1x*d2y - d1y*d2x) < 0) break :is_ear false;
                }

                // make sure triangle is empty, e.g.
                // i.e. make sure no points from other triangles are inside this triangle
                for (vertices.items, 0..) |_, j| {
                    if (j == a or j == b or j == c) continue;

                    const p = vertices.items[j];
                    const alpha = ((v2[1] - v3[1]) * ( p[0] - v3[0]) + (v3[0] - v2[0]) * ( p[1] - v3[1])) /
                                  ((v2[1] - v3[1]) * (v1[0] - v3[0]) + (v3[0] - v2[0]) * (v1[1] - v3[1]));
                    const beta = ((v3[1] - v1[1]) * ( p[0] - v3[0]) + (v1[0] - v3[0]) * ( p[1] - v3[1])) /
                                 ((v2[1] - v3[1]) * (v1[0] - v3[0]) + (v3[0] - v2[0]) * (v1[1] - v3[1]));
                    const gamma = 1.0 - alpha - beta;
                    const contained = (alpha > 0 and beta > 0 and gamma > 0);

                    if (contained) {
                        break :is_ear false;
                    }
                }

                break :is_ear true;
            };

            if (is_ear) {
                try indices.appendSlice(&[_]u16{
                    original_indices.items[a],
                    original_indices.items[b],
                    original_indices.items[c]
                });

                _ = vertices.orderedRemove(b);
                _ = original_indices.orderedRemove(b);
                break;
            }
        }

        escape_hatch += 1;
        if (escape_hatch > 1e6) return;
    }
}

test "detect leak" {
    var idx = std.ArrayList(u16).init(std.testing.allocator);
    defer idx.deinit();
    try earclip(std.testing.allocator, &[4][2]f32{
        .{ 10,0 }, .{ 0,50 }, .{ 60,60 }, .{ 70,10 }
    }, &idx);

    try std.testing.expect(idx.items[0] == 3);
    try std.testing.expect(idx.items[1] == 2);
    try std.testing.expect(idx.items[2] == 1);
    try std.testing.expect(idx.items[3] == 3);
    try std.testing.expect(idx.items[4] == 1);
    try std.testing.expect(idx.items[5] == 0);
}
