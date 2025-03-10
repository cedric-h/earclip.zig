Basic, 100 line zig port of the earclipping algorithm seen [here](https://cedric-h.github.io/linear-webgl/earclip). (Interactive web demo, click "next" and hold it.)

You can try to pull in this dependency from the zig package manager thingy, but it's probably easier to just copy-paste the function into your file. Call it "stb" style. (The code you want is in `src/root.zig`.)

The executable in src/ is built with sokol, and provides a minimal fascimile of the web demo at the link above. It works with Zig 0.14.0 on Windows and Mac.

# Memory Footprint
Currently, the algorithm allocates
 - a copy of all the vertices (it removes a vertex from this array when it finds one)
 - one u16 for each vertex, this is used to determine what the original index of a vertex was (needed to provide the final output)
 - the array of triangle indices, which is the output you're interested in.

Even the javascript version triangulates any shape I could make in fractions of a millisecond, but if you were triangulating really complicated shapes, you might want to speed up this basic algorithm with some sort of spatial hash/quadtree for finding triangles inside of other triangles. (which would increase the memory footprint)

There's also an "escape hatch" where, to prevent infinite loops on degenerate cases (self-intersecting shapes, etc.) the algorithm bails after a million iterations.
