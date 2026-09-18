# Codex Handoff: Fabric M-LSD Node

- Updated: 2026-09-18
- Owning repository: `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/FabricMLSDNode`
- Branch and HEAD: `main` at `3b6b24c` (`Add standalone M-LSD structural line package`)

## Objective and Definition of Done

Create a standalone Fabric plug-in repository that owns one canonical reusable M-LSD structural-line package plus two Fabric nodes: an analysis node that outputs typed segment data and a separate overlay node that renders those segments. Support focused, user-authored sample content comparable to the samples in `FabricBodyMeshProvider` and `FabricScenes` so plug-in integration and intended node composition are demonstrable. Preserve the verified 512-tiny Core ML behavior, provenance, licensing, and focused reference verification. Include reproducible documentation for developers who want to convert, package, and validate another upstream M-LSD variant.

## Current Repository State

The package-migration milestone is committed and pushed on `main` at `3b6b24c`. The working tree now contains the completed plug-in scaffold and model-variant documentation/tooling milestones plus the handoff updates that record them. The verified package tree was copied from `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit` and renamed to `MLSDStructuralLineKit`; the original MESS checkout was not modified. The package manifest uses Swift tools 5.9 and macOS 15. Source identity and the pinned model and license hashes match the verified source. MESS has unrelated dirty submodule pointers for `MessApp/MessApp` and `MessSceneApp/MessSceneApp`; Fabric has unrelated project-file, package-resolution, and `Lygia/` changes. Those existing changes must remain untouched.

The resulting Fabric plug-in is explicitly self-contained: MESS is migration provenance only, not a build-time or runtime dependency. This repository must not import, link, reference, or require any MESS-owned target. Any later MESS adoption points from MESS to this package, never from this repository back to MESS.

## Selected Bounded Milestone

Document and support reproducible model-variant conversion. Add `BUILDING_MODEL_VARIANTS.md`, parameterize the research converter for the official 320/512 and tiny/large checkpoint families where the pinned upstream architecture supports it, and preserve the verified 512-tiny output as the default. Clearly separate conversion support from runtime support: alternate variants are not production-supported until the Swift model contract, preprocessing, decoding, hashes, fixtures, and performance checks are deliberately updated and verified.

Definition of done: the guide contains a reproducible environment and pinned-source workflow, exact variant commands, variant configuration mapping, artifact installation checklist, Swift assumptions to update, licensing/hash requirements, parity acceptance criteria, performance validation, and final package/plug-in verification. The converter exposes validated variant selection without changing its no-argument defaults for the accepted 512-tiny path. Focused static checks and the existing package tests pass.

Non-goals for this milestone: shipping a second production model, claiming runtime compatibility without validating it, implementing Fabric nodes, authoring `.fabric` scenes, changing MESS, committing, or pushing.

## Milestone Status

Complete and verified. The completed plug-in scaffold and this documentation/tooling milestone remain uncommitted. `BUILDING_MODEL_VARIANTS.md`, pinned research dependencies, shared variant configuration, converter selection, reference-generator selection and shape validation, and focused Python tests are implemented. The pinned upstream checkout was inspected at the exact recorded commit. Its 320-tiny README example incorrectly says 512/256; direct inspection of all eight shipped TFLite artifacts confirms both 320 families use a 320 input and 160 map, while both 512 families use a 512 input and 256 map.

## Relevant Files

- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit/`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/docs/internal/handoffs/mlsd-structural-lines.md`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit/ResearchFixtures/MLSD/PROVENANCE.md`
- `Package.swift`
- `Sources/MLSDStructuralLineKit/`
- `Tests/MLSDStructuralLineKitTests/`
- `BUILDING_MODEL_VARIANTS.md`
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

All four official variants converted successfully and passed CPU parity on both fixtures. City results at score `0.05`: 320-tiny 5/5 lines with `1.09e-6` maximum score error and `0.00219` maximum displacement error; 320-large 10/10 with `4.20e-6` and `0.01236`; 512-tiny 46/46 with `3.93e-6` and `0.01477`; 512-large 45/45 with `5.33e-6` and `0.01942`. Every variant had matching TFLite/Core ML segment counts at every recorded threshold on both city and sky-control fixtures. The 320-large sky control reordered raw low-confidence centers while retaining all count and error gates; the public guide explains why this requires investigation but is not itself evidence of a meaningful detection mismatch. Temporary verification outputs remain under `/tmp/fabric-mlsd-variant-verification.eEIuSi` and are recoverable by rerunning the documented commands; they are not repository inputs.

## Unresolved Concerns

- The later Fabric adapter needs a safe asynchronous node-invalidation path after inference completes; current `Node.markDirty()` has no documented thread-safety contract.
- Fabric image preprocessing must honor `FabricImage.textureTransform` and presentation dimensions instead of assuming storage orientation.
- The later MESS migration must be handled as a separate cross-repository milestone.
- The user will author the `.fabric` sample scenes after the node contracts stabilize. `FabricScenes/README.md` records the intended direct-overlay and independent-analysis scenarios; Codex should not create placeholder scene files.

## Next Exact Action

Review the completed plug-in scaffold and model-variant documentation/tooling changes and obtain explicit authorization before committing or pushing them. The next bounded milestone is the analysis-node architecture and Fabric API boundary, including a safe asynchronous invalidation path and correct handling of `FabricImage.textureTransform`; do not begin the overlay node or sample scenes in that milestone.
