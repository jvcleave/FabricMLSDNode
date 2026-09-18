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
segments. See
[`docs/internal/handoffs/fabric-mlsd-node.md`](docs/internal/handoffs/fabric-mlsd-node.md)
for current milestone status.

See [ResearchFixtures/MLSD/PROVENANCE.md](ResearchFixtures/MLSD/PROVENANCE.md)
for model source and license pins, conversion, independent reference fixtures,
and measured Apple-runtime performance.
