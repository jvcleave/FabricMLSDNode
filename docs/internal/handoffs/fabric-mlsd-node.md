# Codex Handoff: Fabric M-LSD Node

- Updated: 2026-09-18
- Owning repository: `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/FabricMLSDNode`
- Latest implementation commit on `main`: `3087797` (`Shorten M-LSD node display labels`)
- Latest planning/documentation commit on `main`: `1199baa` (`Plan M-LSD points and geometry adapters`)

## Objective and Definition of Done

Create a standalone Fabric plug-in repository that owns one canonical reusable M-LSD structural-line package plus two Fabric nodes: an analysis node that outputs typed segment data and a separate overlay node that renders those segments. Support focused, user-authored sample content comparable to the samples in `FabricBodyMeshProvider` and `FabricScenes` so plug-in integration and intended node composition are demonstrable. Preserve the verified 512-tiny Core ML behavior, provenance, licensing, and focused reference verification. Include reproducible documentation for developers who want to convert, package, and validate another upstream M-LSD variant.

## Current Repository State

The package-migration milestone is committed and pushed on `main` at `3b6b24c`. The completed plug-in scaffold and model-variant documentation/tooling milestones are committed and pushed at `53c8467`. The verified package tree was copied from `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit` and renamed to `MLSDStructuralLineKit`; the original MESS checkout was not modified. The package manifest uses Swift tools 5.9 and macOS 15. Source identity and the pinned model and license hashes match the verified source. MESS has unrelated dirty submodule pointers for `MessApp/MessApp` and `MessSceneApp/MessSceneApp`; Fabric has unrelated project-file, package-resolution, and `Lygia/` changes. Those existing changes must remain untouched.

The resulting Fabric plug-in is explicitly self-contained: MESS is migration provenance only, not a build-time or runtime dependency. This repository must not import, link, reference, or require any MESS-owned target. Any later MESS adoption points from MESS to this package, never from this repository back to MESS.

## Selected Bounded Milestone

Record the agreed future points/geometry path as a planned extension, without implementing it yet. Keep the detector's existing scored 2D-segment contract intact; put conversion into downstream nodes.

Definition of done: the handoff specifies the first planar positions adapter, the possible use of Fabric's Geometry Compose and Mesh, the criteria for a later dedicated geometry node, and the distinction between planar placement and genuine 3D recovery. No plug-in runtime or Fabric source changes.

Non-goals: adding new ports or nodes now, authoring another scene, claiming inferred depth or shared junction topology, or changing the shipped model.

## Milestone Status

Points/geometry plan is recorded below as a future extension, not an active implementation. It keeps 2D detection separate from planar positions and optional geometry construction, with explicit zero-line and coordinate-contract gates. The scoped documentation diff and `git diff --check` pass; no source or sample files changed. Committed and pushed at `1199baa`.

Example-publication stage: the user-authored scene JSON parses, declares plug-in version 1.0, and contains the intended Image Provider → analysis → overlay → Image Mesh chain with five active connections. Its only file dependency is the included `DubaiTestImage.jpg`. The scene and source image bytes remain unchanged. README and `FabricScenes/README.md` link the files and explain the required one-time `File Path` relink after cloning; `git diff --check` passes. The source JPEG has no indexed GPS or camera make/model metadata. Committed and pushed at `a0d33a8`; no plug-in build was run because runtime source is untouched.

README screenshot stage: `FabricScenes/MLSDExample.jpg` was inspected visually; it shows the user-authored Image Provider → analysis → overlay → Image Mesh chain and visible city-line output in Fabric Editor. README embeds it by a verified relative path. `git diff --check` passed. The screenshot bytes are unchanged; the user's `.fabric` scene and source JPEG remain untracked and untouched. Committed and pushed at `ed2054a`. A still screenshot is evidence of rendering, not cadence or deterministic-export validation.

The node-width wishlist entry is section 7 of `docs/FABRIC_INTEGRATION_GAPS.md`. It records the 150-point default for all-horizontal-port nodes, the M-LSD label workaround, and a preferred/minimum or content-aware width API that would keep canvas layout consistent. Scoped documentation review and `git diff --check` pass. No source code or bundle changed. Committed and pushed at `979a260`.

Display-label stage: both node titles and visible port labels have been shortened; the registry keys, Swift class names, port types/order/defaults, and processing code are unchanged. Fabric's `PortHydrationSession` matches snapshots by registry key and restores UUIDs while leaving code-owned display names as declared; `PluginLoader` identifies these node classes by Swift class name. Existing saved connections should therefore survive the label update. The README now uses `Frame`/`Lines`/`Scores` for direct wiring. Release plug-in build, installation, strict deep signature verification, and `git diff --check` pass; no package test is needed for this reversible metadata-only change. Committed and pushed at `3087797`. Visual fit in the Editor remains for the user to assess after restart.

Analysis-node milestone complete, verified, committed at `b6df802`, and pushed with its checkpoint at `7427a59`; overlay milestone is implemented, verified, committed at `d4e656c`, and pushed. The overlay uses a plug-in Metal shader, Fabric-managed RGBA16-float output, a raw storage-space copy, and presentation-space instanced line quads; its source transform is retained. During wiring review, a frame-pairing gap emerged: direct reuse of the latest source image can mismatch asynchronously completed segments. An `Analyzed Image` outlet now publishes the retained source image with each completed result; the README uses it for direct overlay wiring. Debug and Release builds, package tests, offscreen identity/vertical-flip/quarter-turn GPU fixture, installed shader packaging/signature, and model/license identity checks pass. Architecture inspection confirmed that Fabric's `PortType` and `PortValue` are closed enums, while `ContiguousArray<SIMD4<Float>>` and `ContiguousArray<Float>` are already supported typed values. A self-contained plug-in therefore cannot introduce a first-class `StructuralLineFrame` port without changing Fabric; the selected parallel-array contract preserves type safety and avoids that cross-repository change.

Fabric supplies one uncommitted command buffer for an execution pass. Starting a separate preprocessing command buffer from `execute()` could race upstream image production, so preprocessing will be encoded after upstream work on the supplied buffer. Core ML prediction begins only in its completion handler. Fabric's `markDirty()` is not documented as thread-safe; completion publication will therefore be staged through `Task { @MainActor in ... }`, consistent with Fabric's existing asynchronous node state transitions. At most one inference is active and only the newest request is retained while it runs.

The core implementation stage is complete. Preprocessing now accepts presentation dimensions and a canonical-to-stored texture transform, can encode without committing a caller-owned command buffer, and dispatches Core ML prediction to a dedicated serial queue after GPU completion. The analysis node and plug-in registration are implemented with the selected typed-array contract and one-active/one-latest-pending scheduling. `docs/FABRIC_INTEGRATION_GAPS.md` records seven host constraints and possible API directions, including deterministic-export, plug-in-build, and node-width limitations.

## Planned Extension: Points and Geometry

Keep `M-LSD Analyze` responsible for scored, normalized bottom-left 2D segments. First, add a separate processor that converts each retained segment into **two ordered `Vector3` positions** on a flat XY plane (`z = 0`), preserving segment pairing and never merging coincident endpoints into claimed shared junctions. Decide the plane's world-size/aspect mapping and any score-filtering or paired-score output before implementation; document those choices in this owning repository's handoff.

Prototype the positions output with Fabric's existing `Geometry Compose` node: `Positions` → `Geometry Compose` with `Primitive = Point` or `Line` → `Mesh` with a material. Fabric already supports `Array<Vector3>` and `Geometry` ports. Verify pairwise line rendering and empty-array behavior in a live graph; the current `Geometry Compose` source updates only for nonempty positions, so a zero-line frame may leave stale geometry.

Add a dedicated plug-in geometry node only if the built-in composition path cannot meet live-update correctness, score filtering, line-specific rendering controls, or performance requirements. That node should own a stable reusable geometry instance and explicitly clear it on empty results. These outputs are planar representations of image detections, **not** depth, camera pose, tracked structure, or recovered 3D geometry. Any depth lifting is a separate design milestone.

## Relevant Files

- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit/`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/docs/internal/handoffs/mlsd-structural-lines.md`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit/ResearchFixtures/MLSD/PROVENANCE.md`
- `Package.swift`
- `Sources/MLSDStructuralLineKit/`
- `Tests/MLSDStructuralLineKitTests/`
- `BUILDING_MODEL_VARIANTS.md`
- `docs/FABRIC_INTEGRATION_GAPS.md`
- `ResearchFixtures/MLSD/Conversion/mlsd_variants.py`
- `ResearchFixtures/MLSD/Conversion/requirements-model-conversion.txt`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/BodyMeshProvider/BodyMeshProvider/BodyMeshProvider.xcodeproj/project.pbxproj`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/BodyMeshProvider/BodyMeshProvider/BodyMeshProvider/Info.plist`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/BodyMeshProvider/FabricScenes/`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/Fabric/Fabric/Nodes/Plugin/`

## Intended Implementation

Follow the proven Body Mesh Provider repository shape while keeping the existing root package: place the Xcode project and bundle sources under `FabricMLSDNode/`, reference the root package as a local Swift package, and build Fabric's module from the adjacent checkout before compiling the bundle. Use `com.jvclabs.FabricMLSDNode`, module/product name `FabricMLSDNode`, and bundle name `FabricMLSDNode.fabricplugin`. Keep registration in a minimal `FabricMLSDPlugin` principal class and do not register placeholder nodes. Add `FabricScenes/README.md` now; add actual `.fabric` scenes only when the real nodes can serialize into them.

## Verification Command and Latest Result

Previous milestone: `swift test` passed on 2026-09-18 with 6 tests in 2 suites. `swift package dump-package` confirmed macOS 15.0 and no external package dependencies. Production and research model/license copies matched the pinned SHA-256 values.

Pre-build checks passed: `plutil -lint` accepts both `FabricMLSDNode/FabricMLSDNode/Info.plist` and `FabricMLSDNode/FabricMLSDNode.xcodeproj/project.pbxproj`; a project scan found no copied Body Mesh or CoMotion references.

Debug `xcodebuild` passed after correcting two cache-layout issues discovered by the initial attempts. The first attempt reused Fabric's existing `.build` and found an older-compiler module. The scaffold now builds Fabric in the ignored repository-local `.fabric-spm/` scratch directory. Xcode 27's default SwiftPM build system does not produce the module-map layout required by Fabric's current external plug-in setup, so the preparation phase explicitly uses SwiftPM's native build system and all dependency paths point into the isolated scratch root.

The built Debug bundle reports identifier `com.jvclabs.FabricMLSDNode`, API version 1, principal class `FabricMLSDNode.FabricMLSDPlugin`, and minimum macOS 15.0. It is arm64, contains the Metal preprocessor plus the pinned model and license with matching hashes, installs to the user Fabric plug-in directory, and both built and installed bundles pass strict deep signature verification. Warnings came from Fabric and its dependencies, not the new plug-in source.

Release `xcodebuild` also passed. Its arm64 bundle and the installed copy both pass strict deep signature verification. Release metadata reports identifier `com.jvclabs.FabricMLSDNode`, API version 1, principal class `FabricMLSDNode.FabricMLSDPlugin`, and minimum macOS 15.0. The embedded model SHA-256 is `3394446fabb834545a11f7445965ed31ffc43e3d1a5d4c19a00bbeeca7c804f3`; the embedded license SHA-256 is `b8a6637c19443e6792ce93c37fe1faac3c745e319ffcd90ac8be0a170a9a1900`. The package regression run passed all 6 tests in 2 suites, including the CPU city reference. `git diff --check` passed, and the source/project audit found no MESS import or copied Body Mesh/CoMotion reference.

Current documentation/tooling checks: the two Python variant-contract tests pass; all three research scripts compile; converter `--help` exposes the four variants and defaults to 512-tiny; the existing Core ML artifact compiles successfully with `coremlcompiler`; `swift test` still passes all 6 tests in 2 suites. A clean Python 3.10 install exposed an incompatible unconstrained SciPy selection, so compatible JAX 0.4.30, JAXlib 0.4.30, and SciPy 1.10.1 versions are now pinned. With those pins, the converter regenerated 512-tiny successfully from the pinned checkpoint and the parameterized reference generator produced JSON and preview files byte-for-byte identical to the accepted baseline. The regenerated `.mlmodel` hash differs because its descriptive author metadata no longer mentions MESS; CPU numerical parity is unchanged.

Current analysis-node checks: `swift test` passes all 7 tests in 2 suites. The unchanged identity path still reproduces 46 city-reference lines; the public asynchronous API leaves its caller-owned command buffer unsubmitted; and a new independent 2-by-2 color fixture verifies that a Fabric-style vertical transform flips preprocessing into presentation orientation correctly. Debug and Release `xcodebuild` both pass and install the plug-in; Release was rebuilt after the final source review. The installed arm64 bundle passes strict deep signature verification, retains API version 1 and the expected principal class, contains the analysis-node symbols and orientation-aware Metal source, and preserves the pinned model and license hashes. The builds emit existing Fabric dependency and stale module-cache warnings; no warning names the new plug-in source. The final review added an immutable transform snapshot per request, stale-result invalidation when the image disconnects, and recoverable presentation-size validation. Package tests and `git diff --check` still pass. A user-authored Editor scene and screenshot were published later.

Current overlay checks: Debug and Release `xcodebuild` pass, and the installed bundle contains `default.metallib` with all three overlay functions. `scripts/verify_overlay_shader.swift` loads that bundle and passes copy/compositing fixtures for identity, vertical-flip, and quarter-turn transforms. `swift test` passes 7 tests in 2 suites. The installed Release bundle passes strict deep signature verification, has API version 1 and principal class `FabricMLSDNode.FabricMLSDPlugin`, and retains the pinned model/license SHA-256 values `3394446fabb834545a11f7445965ed31ffc43e3d1a5d4c19a00bbeeca7c804f3` and `b8a6637c19443e6792ce93c37fe1faac3c745e319ffcd90ac8be0a170a9a1900`. `git diff --check` passes. One audit command initially used nonexistent source resource paths and exited 1; rerunning against installed resource paths succeeded. A user-authored Editor scene and screenshot were published later.

All four official variants converted successfully and passed CPU parity on both fixtures. City results at score `0.05`: 320-tiny 5/5 lines with `1.09e-6` maximum score error and `0.00219` maximum displacement error; 320-large 10/10 with `4.20e-6` and `0.01236`; 512-tiny 46/46 with `3.93e-6` and `0.01477`; 512-large 45/45 with `5.33e-6` and `0.01942`. Every variant had matching TFLite/Core ML segment counts at every recorded threshold on both city and sky-control fixtures. The 320-large sky control reordered raw low-confidence centers while retaining all count and error gates; the public guide explains why this requires investigation but is not itself evidence of a meaningful detection mismatch. Temporary verification outputs remain under `/tmp/fabric-mlsd-variant-verification.eEIuSi` and are recoverable by rerunning the documented commands; they are not repository inputs.

## Unresolved Concerns

- The user-authored screenshot shows line rendering in Fabric Editor; live cadence and deterministic export have not been validated from that still capture.
- Fabric has no same-frame barrier for asynchronous GPU-to-CPU analysis during deterministic export. The first node will explicitly support bounded latest-frame interactive analysis; the limitation and possible host APIs are recorded in `docs/FABRIC_INTEGRATION_GAPS.md`.
- The later MESS migration must be handled as a separate cross-repository milestone.
- The user-authored `FabricScenes/MLSDExample.fabric` and `FabricScenes/DubaiTestImage.jpg` are being published as the direct-overlay sample. Fabric's absolute file URL requires one-time relinking on another machine. A separate independent-analysis sample may be added later; Codex should not create a placeholder.

## Next Exact Action

The points/geometry extension is planned but not started. On implementation go-ahead, select the planar positions adapter as one bounded milestone, settle world-size/aspect and score contracts, and test the `Geometry Compose` empty-input case before deciding on a dedicated geometry node. Live cadence and deterministic export remain separate checks.
