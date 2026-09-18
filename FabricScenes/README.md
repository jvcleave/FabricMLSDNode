# Fabric sample scenes

[`MLSDExample.fabric`](MLSDExample.fabric) is the user-authored direct-overlay
sample. It uses [`DubaiTestImage.jpg`](DubaiTestImage.jpg) as its Image Provider
source; [`MLSDExample.jpg`](MLSDExample.jpg) shows the scene and its output in
Fabric Editor.

After cloning, open the scene and use Image Provider's `File Path` picker to
reselect the included JPEG, then save. Fabric serializes an absolute file URL,
so the author's saved path is not portable between machines.

Codex will not generate placeholder `.fabric` files. A separate scene showing
independent use of the analysis outputs may be added later.
