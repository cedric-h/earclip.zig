~/sokol-tools-bin/bin/osx_arm64/sokol-shdc -i src/shaders/triangle.glsl -o src/shaders/triangle.glsl.zig -l glsl410:glsl300es:metal_macos:hlsl5:wgsl -f sokol_zig --reflection

zig build run
