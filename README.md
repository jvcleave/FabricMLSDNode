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

The Fabric plug-in is being developed as two nodes: an analysis node that
publishes typed segment data and a separate overlay node that renders those
segments. User-authored sample `.fabric` scenes will demonstrate both the
direct overlay path and independent use of the analysis outputs. See
[`docs/internal/handoffs/fabric-mlsd-node.md`](docs/internal/handoffs/fabric-mlsd-node.md)
for current milestone status.

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

The bundle foundation intentionally registers no nodes yet. Node registration
will be added with the analysis and overlay implementation milestone.

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
