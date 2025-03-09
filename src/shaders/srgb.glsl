@vs vs
in vec4 position;
in vec4 color0;

out vec4 color;

void main() {
    gl_Position = position;
    color = color0;
}
@end

@fs fs
in vec4 color;
out vec4 frag_color;

void main() {
    // SRGB
    frag_color = vec4(pow(abs(color.xyz), vec3(1.0 / 2.2)), 1);
}
@end

@program triangle vs fs
