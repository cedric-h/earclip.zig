@vs vs
layout(binding=0) uniform vs_params {
    vec2 u_pos;
    vec2 u_zoom;
};

in vec4 position;
in vec4 color0;

out vec4 color;

void main() {
    gl_Position = vec4(position.xy * u_zoom + u_pos, position.z, position.w);
    color = color0;
}
@end

@fs fs
in vec4 color;
out vec4 frag_color;

void main() {
    // software gamma/SRGB ?
    // frag_color = vec4(pow(color.xyz, vec3(1.0 / 2.2)), 1);
    frag_color = color;
}
@end

@program triangle vs fs
