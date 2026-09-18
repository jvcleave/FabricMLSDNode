# Fabric M-LSD Node

This repository owns a reusable macOS Swift package for M-LSD structural-line
analysis and its Fabric plug-in integration. The package bundles the pinned
M-LSD 512-tiny Core ML model and its Apache-2.0 license, resizes Metal textures
into the model's image input, and decodes up to 200 scored line segments into a
validated `StructuralLineFrame`.

Each segment owns two junction entries because M-LSD does not infer shared
topology. Public positions use normalized full-image bottom-left coordinates;
the decoder clamps endpoints at that public contract boundary. Host
applications own scheduling and rendering. The package has no dependency on
Fabric, Satin, MESS, MessScene, Python, TensorFlow, or TFLite at runtime.

The Fabric plug-in provides two nodes: an analysis node that publishes typed
segment data and a separate overlay node that renders those segments.
User-authored sample `.fabric` scenes will demonstrate both the
direct overlay path and independent use of the analysis outputs. See
[`docs/internal/handoffs/fabric-mlsd-node.md`](docs/internal/handoffs/fabric-mlsd-node.md)
for current milestone status.

Current Fabric constraints, the plug-in's local adaptations, and candidate
host API improvements are tracked in
[`docs/FABRIC_INTEGRATION_GAPS.md`](docs/FABRIC_INTEGRATION_GAPS.md).

## Development layout

The default local layout is:

```text
MAC_APPS/
├── Fabric/
└── FabricMLSDNode/
```

The reusable `MLSDStructuralLineKit` package is rooted at this repository's
`Package.swift`. The native plug-in target lives under `FabricMLSDNode/` and
builds against the adjacent Fabric checkout. Override its location with the
`FABRIC_SOURCE_ROOT` build setting when necessary.

## Build and install

Build the reusable package and its reference tests with:

```sh
swift test
```

Open `FabricMLSDNode/FabricMLSDNode.xcodeproj` and build the
`FabricMLSDNode` scheme, or run:

```sh
xcodebuild \
  -project FabricMLSDNode/FabricMLSDNode.xcodeproj \
  -scheme FabricMLSDNode \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

The build prepares the matching Fabric Swift module, builds the plug-in, and
installs a development-signed bundle at:

```text
~/Library/Application Support/Fabric/Plugins/FabricMLSDNode.fabricplugin
```

Use the same configuration for Fabric Editor and the plug-in. Restart Fabric
Editor after rebuilding because Fabric discovers plug-ins when its node
registry starts. Fabric is compiled in the repository-local `.fabric-spm/`
scratch directory so the plug-in build does not depend on or overwrite the
adjacent checkout's existing `.build` cache.

## Analysis node contract

The plug-in registers `M-LSD Analyze`. It accepts an `Image` plus `Min Score`
(minimum confidence), `Max Lines`, and `Interval` parameters. It publishes:

- `Lines`: `Array<Vector4>`, with each value packed as
  `[startX, startY, endX, endY]` in normalized bottom-left coordinates.
- `Scores`: an index-aligned confidence `Array<Float>`.
- `Count`: the number of completed segments.
- `Size`: the analyzed image's presentation width and height.
- `Frame`: the source image paired with those completed segments.

The node encodes orientation-aware preprocessing into Fabric's current command
buffer, then performs Core ML inference asynchronously after GPU completion.
It permits one active inference and retains only the newest eligible pending
image. Outputs therefore represent the latest completed interactive analysis;
Fabric currently has no same-frame asynchronous barrier for deterministic
export. That limitation is detailed in the integration-gaps document above.

## Overlay node contract

`M-LSD Overlay` accepts an `Image`, `Lines` in the
analysis node's normalized bottom-left `Array<Vector4>` format, and optional
index-aligned `Scores` (`Array<Float>`). Connect the analysis node's
two array outlets to the identically named overlay inlets. The overlay works
with any compatible segment producer; it does not run inference.

For frame-aligned interactive results, connect analysis `Frame` to the overlay's
`Image` inlet. Connecting the current upstream image instead is possible, but
its content can be newer than the asynchronously completed line arrays.

The overlay has line color, width in presentation pixels, opacity, and minimum
confidence controls. If confidences are omitted, every line is treated as
confidence 1. It accepts at most 200 lines with finite normalized endpoints;
if confidences are connected, their count must match. Invalid arrays produce
a recoverable Fabric execution error. With no visible lines it passes the
source image through. Otherwise it copies the stored image, draws anti-aliased
lines in presentation space, and preserves the source image's Fabric texture
transform on the output. Its output is an RGBA16-float `Image`.

The offscreen Metal shader fixture can be run against an installed bundle with:

```sh
swift scripts/verify_overlay_shader.swift \
  "$HOME/Library/Application Support/Fabric/Plugins/FabricMLSDNode.fabricplugin"
```

## Samples

Checked-in examples belong in [`FabricScenes/`](FabricScenes/). The directory
is established now for the user-authored scenes, which will be added once the
real nodes and their serialized port contracts are stable.

See [ResearchFixtures/MLSD/PROVENANCE.md](ResearchFixtures/MLSD/PROVENANCE.md)
for model source and license pins, conversion, independent reference fixtures,
and measured Apple-runtime performance.

Developers evaluating another official checkpoint family should follow
[`BUILDING_MODEL_VARIANTS.md`](BUILDING_MODEL_VARIANTS.md). Conversion tooling
supports selecting the official 320/512 and tiny/large families, but the
shipping Swift runtime remains deliberately pinned to the verified 512-tiny
artifact until another variant completes the documented integration and
acceptance process.
