"../sokol-tools-bin/bin/win32/sokol-shdc.exe" -i src/shaders/triangle.glsl -o src/shaders/triangle.glsl.zig -l glsl410:glsl300es:metal_macos:hlsl5:wgsl -f sokol_zig --reflection

zig.exe build run
