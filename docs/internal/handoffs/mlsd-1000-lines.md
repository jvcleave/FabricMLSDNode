# Handoff: Fabric M-LSD 1,000-line capacity

- Updated: 2026-10-23
- Owning repository: `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/FabricMLSDNode`
- Starting branch/HEAD: `main` at `fa2705d`

## Objective and Definition of Done

Ship the accepted 512-tiny weights with top-1,000 selection; support 1,000
lines throughout the decoder, analysis, overlay, and planar-positions nodes.
Update reproducible export instructions, artifact pins, and public port docs.
Verify unchanged backbone/first-200 results, decoding beyond 200, CPU/GPU
inference, plug-in builds, and installed bundle identity/signature.

## Current Bounded Milestone

Derive a top-1,000 Core ML artifact from the pinned accepted research baseline
by changing only TopK.K and descriptive metadata. Update the fixed shipping
contract coherently, then build/install and checkpoint the complete change.

## Decisions and Constraints

- Self-contained Fabric repository; no runtime/build dependency on MESS.
- Preserve the 512×512 stretch, learned weights, normalization, NMS, minimum
  map length 20, coordinate conventions, and `.cpuAndGPU` production policy.
- New Analyze nodes default to Max Lines 1,000. Saved parameter values (e.g.
  200) remain authored values; users can increase them after loading.
- Keep the exact top-200 model and independent TFLite fixtures in research.
  The production model resource can retain its existing filename with a new
  pinned hash and explicit top-1,000 metadata.
- Reuse the proven graph-only export technique, with a pinned baseline and a
  serialized equality check that restores TopK/metadata to prove no other
  operation or learned weight changed. No TensorFlow regeneration is required.
- Commit/push authorization persists from the user. Commit scoped task files.

## Repository State

- Preserve user-modified `FabricScenes/MLSDGeoExample.fabric`.
- Preserve untracked `docs/internal/handoffs/plugin-abi-rebuild.md` from the
  separate ABI-rebuild task; it records a Debug Editor host and prior rebuild.
- Fabric and MESS source are read-only context for this task.

## Relevant Files

- `ResearchFixtures/MLSD/Conversion/` — export and verification tooling.
- `Sources/MLSDStructuralLineKit/` — shipping model, limits, decoder, metadata.
- `FabricMLSDNode/FabricMLSDNode/Nodes/` — three node contracts.
- `Tests/MLSDStructuralLineKitTests/` — decoder boundary and inference tests.
- `README.md`, `BUILDING_MODEL_VARIANTS.md`, research provenance/hash manifest.

## Implemented Stage

- Added graph-only exporter (deterministic protobuf) and a CPU/GPU comparison
  script. Top-1,000 artifact hash is
  `e23a999f4d3ba993a667afacb399d8193ce1bb0d4853087153287fa2780234cd`.
- Shipping model, expected output shapes, shared 1,000-line/2,000-junction
  limits, decoder, and all three node contracts are updated. Overlay now uses
  a per-draw Metal vertex buffer: 16 KB of segments exceeds the 4 KB inline
  upload limit. Analysis startup calls super only after model loading succeeds,
  as required by current Fabric lifecycle state tracking.
- README, conversion instructions, provenance, and hash manifest are updated.
  Original research model/reference/preview remain unchanged.

## Verification

- `swift test`: all 8 tests in 2 suites pass, including 1,000-candidate decode,
  selected cap 321, legacy-shape rejection, real >200 detections, pinned model,
  original 46-line CPU city result, async GPU path, and texture orientation.
- Graph export proves only TopK/metadata changed. CPU comparison preserves the
  first 200 centers/scores and entire displacement map exactly on city and sky.
  City counts at 0.001: 104 → 205; at 0.01: 104 → 122; at 0.05: 46 → 46.
- Local city warm prediction: ~38.6 ms CPU, ~5.6 ms CPU/GPU. Loading,
  preprocessing, decoding, and rendering excluded; GPU gives 47 lines at 0.05.
- `shasum -a 256 -c SHA256SUMS`: all 9 research artifacts pass.
- Release plug-in build passed, log `/tmp/fabric-mlsd-1000-release.log`; strict
  deep signing passed. The Metal fixture passes 1,000 segments with only the
  final segment at the inspected pixel, in identity/flip/quarter-turn modes.
- Debug build passed, log `/tmp/fabric-mlsd-1000-debug.log`; updated Debug bundle
  is installed. Built Debug and installed bundles pass strict deep signing and
  the model/license hashes match their pins.
- `scripts/verify_node_capacity.py` passes against Release and installed Debug:
  Analyze default/max 1,000; Positions 2,000 ordered endpoints/aspect mapping,
  empty clearing and >1,000 rejection; Overlay 1,000-line GPU execution and
  >1,000 rejection. The 1,000th-instance orientation shader fixture passes
  against both bundles. The standalone fixture needs the existing Editor's
  Frameworks folder to resolve Sparkle (via HapInAVFoundation); no dependency
  was added to the plug-in.
- Repeated graph export is byte-for-byte identical; Python tools compile,
  existing 2 conversion-contract tests pass, and `git diff --check` passes.

## Remaining Issues

No current blocker. A larger candidate pool does not guarantee 1,000 accepted
lines; score and length filters still apply. Live quality/playback is a manual
check; do not invent new latency claims from the previous top-200 benchmark.

## Next Exact Action

Review the scoped final diff, commit and push the completed capacity upgrade,
and record the implementation revision. Exclude the user scene and unrelated
ABI-rebuild handoff from staging.
