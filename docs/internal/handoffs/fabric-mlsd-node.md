# Codex Handoff: Fabric M-LSD Node

- Updated: 2026-09-18
- Owning repository: `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/FabricMLSDNode`
- Branch and HEAD: `main` at unborn branch

## Objective and Definition of Done

Create a standalone Fabric plug-in repository that owns one canonical reusable M-LSD structural-line package plus two Fabric nodes: an analysis node that outputs typed segment data and a separate overlay node that renders those segments. Preserve the verified 512-tiny Core ML behavior, provenance, licensing, and focused reference verification.

## Current Repository State

The GitHub repository was cloned successfully and has no commits. The verified package tree has been copied from `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit` and renamed to `MLSDStructuralLineKit`; the original MESS checkout was not modified. The package manifest now uses Swift tools 5.9 and macOS 15. Source identity and the pinned model and license hashes match the verified source. MESS has unrelated dirty submodule pointers for `MessApp/MessApp` and `MessSceneApp/MessSceneApp`; Fabric has unrelated project-file, package-resolution, and `Lygia/` changes. Those existing changes must remain untouched.

The resulting Fabric plug-in is explicitly self-contained: MESS is migration provenance only, not a build-time or runtime dependency. This repository must not import, link, reference, or require any MESS-owned target. Any later MESS adoption points from MESS to this package, never from this repository back to MESS.

## Selected Bounded Milestone

Establish the repository-root `MLSDStructuralLineKit` Swift package by migrating the verified implementation, model, license, research provenance, and focused tests from MESS. Adopt Swift tools 5.9 and macOS 15, rename the package/module cleanly, and pass its package tests.

Non-goals for this milestone: creating the Fabric bundle target, changing MESS dependencies, implementing either Fabric node, changing model behavior, committing, or pushing.

## Milestone Status

Complete and verified. The user explicitly authorized committing and pushing this checkpoint on 2026-09-18.

## Relevant Files

- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit/`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/docs/internal/handoffs/mlsd-structural-lines.md`
- `/Users/jvcleave/Documents/WORK_IN_PROGRESS/MAC_APPS/MESS/MessStructuralLineKit/ResearchFixtures/MLSD/PROVENANCE.md`
- `Package.swift`
- `Sources/MLSDStructuralLineKit/`
- `Tests/MLSDStructuralLineKitTests/`

## Intended Implementation

Mechanically import the standalone package without changing the source checkout. Rename `MessStructuralLineKit` to the neutral `MLSDStructuralLineKit` package, product, target, and test target. Keep the production model, Apache-2.0 license, Metal area-resampling preprocessor, model hash validation, CPU reference fixtures, and research provenance. Keep runtime dependencies limited to Apple frameworks.

## Verification Command and Latest Result

`swift test`

Passed on 2026-09-18: 6 tests in 2 suites, including bundled artifact hashes, structural-line value contracts, decoder parity, and the pinned CPU city reference. The first invocation exposed that PackageDescription 5.9 does not provide the `.v15` convenience constant; changing the equivalent deployment declaration to `.macOS("15.0")` fixed the manifest while preserving the required target.

`swift package dump-package` confirms macOS 15.0, no external package dependencies, and only the local core library dependency for its test target. A source/test scan found no MESS imports or dependencies. Production and research model/license copies match each other and the pinned SHA-256 values.

## Unresolved Concerns

- The later Fabric adapter needs a safe asynchronous node-invalidation path after inference completes; current `Node.markDirty()` has no documented thread-safety contract.
- Fabric image preprocessing must honor `FabricImage.textureTransform` and presentation dimensions instead of assuming storage orientation.
- The later MESS migration must be handled as a separate cross-repository milestone.

## Next Exact Action

After the authorized checkpoint is pushed, define the Fabric plug-in scaffold as a separate bounded milestone. Do not begin node implementation until that milestone's scope and definition of done are recorded here.
