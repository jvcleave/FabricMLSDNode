# Fabric sample scenes

[`MLSDExample.fabric`](MLSDExample.fabric) is the user-authored direct-overlay
sample. It uses [`DubaiTestImage.jpg`](DubaiTestImage.jpg) as its Image Provider
source; [`MLSDExample.jpg`](MLSDExample.jpg) shows the scene and its output in
Fabric Editor.

[`MLSDGeoExample.fabric`](MLSDGeoExample.fabric) is the user-authored geometry
sample. It connects analysis `Lines` and `Size` to `M-LSD Positions`, sends
the resulting endpoint pairs to Geometry Compose with `Primitive = Line`, and
renders the geometry through Mesh with a Color Material.
[`MLSDGeoExample.jpg`](MLSDGeoExample.jpg) shows the node graph and rendered
line geometry in Fabric Editor.

Both scenes reference the included JPEG by a relative path. Keep the JPEG
beside the scenes when moving them. The geometry scene also contains an
disconnected Movie Provider from its authoring session with an empty file path.
