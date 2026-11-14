# Handoff for M-LSD Fabric and Satin integration

- Updated 2026-11-14, 03:33 EST
- Owning repository `FabricMLSDNode`
- Starting revision `ad3e7ae` (workspace checkout)
- Host revisions Fabric `c1da6639`, Satin `ff825e49`

## Objective

Implement and verify the current-pin changes in the
[integration plan](../todos/MLSD_SATIN_INTEGRATION_PLAN.md). Preserve saved
ports and settings, model parity, and frame-aligned analysis and overlay.

## Current milestone

The current-pin implementation and verification are complete. The workspace
Debug Editor rendered both sample scenes, and the offscreen fixture verified
their authored `Max Lines` values after reopening. The implementation is ready
for the authorized push to M-LSD `main` and the verified workspace pin.

## Repository state

The M-LSD checkout started clean. The workspace publication covers the M-LSD
gitlink and its change log entry.
The core retains the Core Video wrapper and pixel buffer through the encoding
segment and keeps the pixel buffer alive through Core ML prediction.
The overlay allocates a separate Satin `.cpuWrites` buffer for each draw and
keeps it alive through the encoding segment.
Analyze uses a synchronized mailbox for each active request. Graph execution
consumes the result and updates all five outlets. Disconnect and stop suppress
publication while the request drains. An abandoned GPU segment releases the
active slot and retries the latest eligible image.

## Decisions and constraints

Use the current Fabric and Satin pins. Fabric upstream `main` still points to
`c1da6639`. The Stroke Geometry example depends on a later host revision.

## Relevant files

- `Sources/MLSDStructuralLineKit/MLSDTexturePreprocessor.swift`
- `Sources/MLSDStructuralLineKit/MLSDBackbone.swift`
- `Tests/MLSDStructuralLineKitTests/MLSDStructuralLineAnalyzerTests.swift`
- `FabricMLSDNode/FabricMLSDNode/Nodes/MLSDStructuralLineAnalysisNode.swift`
- `FabricMLSDNode/FabricMLSDNode/Nodes/MLSDStructuralLineOverlayNode.swift`
- `scripts/verify_node_capacity.py` and `scripts/verify_overlay_shader.swift`
- `scripts/verify_analysis_delivery.swift`

## Verification

The Fabric and M-LSD `main` revisions were checked with `git ls-remote`.
Xcode 26.3 is available at `/Applications/Xcode.app`. Pass its developer
directory via `DEVELOPER_DIR` for workspace builds.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed all
nine tests. The new fixture gates a Metal segment with a shared event, records
a second preprocessing pass after `commitAndContinue()`, then checks both
model input buffers for their expected pixels. The decoder fixture now zeros
all unused confidence entries after a run exposed uninitialized test data.

The Debug plug-in build passed. `scripts/verify_node_capacity.py` checked
the last instance of two distinct 1,000-segment draws in one command buffer,
as well as empty and fully filtered pass-through. `scripts/verify_overlay_shader.swift`
passed the identity, vertical flip, and quarter-turn pixel checks.

`scripts/verify_node_capacity.py --fixture analysis` passed against the Debug
plug-in. It checked a clean Processor subgraph, more than
`maxBuffersInFlight` draws with preprocessing held by a shared event on a
separate queue, the newest eligible frame, `Interval`, score and limit edits,
an unsubmitted Metal segment, an actual Metal execution error, disconnect,
wire replacement in one frame, invalid presentation dimensions, and restart.
On this system, discarding the Metal buffer calls its completion handler with
`.notEnqueued`. Callback disposal also retires abandoned work.

The workspace `./Scripts/build-workspace.sh` and strict deep signature checks
passed. Both node fixtures and the overlay shader check passed against the
embedded Debug bundle. Fabric registered all three M-LSD nodes. Each reopened
scene retained `Max Lines = 200` and rendered 177 lines through `GraphRenderer`.
The original scenes reported a retired `inputRenderPass` on their host mesh
nodes. The fixture kept their nodes and wires through serialization.

The Editor visually rendered both scene copies with the bundled JPEG relinked.
LaunchServices stalled in `dyld` when starting the Debug app. Launching its
executable with `DYLD_FRAMEWORK_PATH` pointing at the app's `Contents/Frameworks`
loaded the embedded Fabric framework and M-LSD bundle. The workspace Audio
Analysis verifier and the nine research artifact hashes also passed.

Logs are in the workspace's ignored `.build/logs/mlsd-*.log` and
`.build/mlsd-editor-check/` directories.

Run the embedded bundle checks from the workspace root after the Debug build.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
editor="$PWD/.build/Fabric Editor.app"
plugin="$editor/Contents/PlugIns/FabricMLSDNode.fabricplugin"
fabric_build="Fabric/.build/$(uname -m)-apple-macosx/debug"
for fixture in capacity analysis; do
    CFFIXED_USER_HOME="$PWD/.build/RuntimeHome" \
        python3 FabricMLSDNode/scripts/verify_node_capacity.py \
        --fixture "$fixture" --fabric-build "$fabric_build" \
        --plugin "$plugin" --framework-path "$editor/Contents/Frameworks"
done
swift FabricMLSDNode/scripts/verify_overlay_shader.swift "$plugin"
```

## Remaining issues

Stroke Geometry and scoped Iterator delivery depend on Fabric host changes.
This implementation was verified against Fabric `c1da6639`.

## Next exact action

The workspace's M-LSD gitlink records the published component revision. Once
Fabric `main` includes Stroke Geometry and its Satin dependency, use the
workspace update runbook to verify and save the geometry example with those
revisions.
