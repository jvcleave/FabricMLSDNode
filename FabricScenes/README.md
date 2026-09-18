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

After cloning, open the scene and use Image Provider's `File Path` picker to
reselect the included JPEG, then save. Fabric serializes an absolute file URL,
so the author's saved path is not portable between machines.

Both scenes use the included JPEG. The geometry scene also contains an
unconnected Movie Provider from its authoring session; it is not part of the
sample's execution path and does not need to be relinked.
