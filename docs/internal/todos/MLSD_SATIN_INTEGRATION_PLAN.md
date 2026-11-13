# M-LSD Fabric and Satin integration plan

Use the Fabric and Satin APIs available in the workspace to fix a GPU resource
lifetime issue, simplify overlay buffer allocation, and deliver inference results
on Fabric's graph execution owner. Adopt Satin strokes for the geometry example
when Fabric ships its Stroke Geometry node.

The baseline is M-LSD `6b5c73d`, Fabric `c1da6639`, and Satin `ff825e49`. The
staged Debug bundle passed the capacity and overlay pixel fixtures, including
the 1,000th segment, identity, vertical flip, and quarter turn. An offscreen
check of the current geometry path produced 4, 4, and 2 vertices for two lines,
zero lines, and one line, respectively. Geometry Compose retained the old
vertices on empty input. [Capacity fixture](../../../scripts/verify_node_capacity.swift) ·
[Overlay fixture](../../../scripts/verify_overlay_shader.swift) ·
[Geometry Compose source](https://github.com/Fabric-Project/Fabric/blob/c1da66398ae4b28c266e0b3d4ef456d60c97f171/Fabric/Nodes/Geometry/PixelArrayToGeometryNode.swift#L51-L101)

Preserve the three registered nodes, port keys and types, saved parameter
values, and the 1,000-line contract. Keep `MLSDStructuralLineKit` standalone
with its pinned model, 512×512 stretch, confidence and displacement filtering,
and normalized bottom-left endpoints. [Node and package contracts](../../../README.md)

## Preprocessing lifetime

Retain the `CVMetalTexture` wrapper and its pixel buffer until the Metal
command-buffer segment that writes the model input finishes. Keep the prepared
pixel buffer alive through Core ML prediction. Attach GPU ownership at encode
time so it also covers cancellation and errors after encoding. Keep the
existing standalone synchronous and callback entry points usable.
[Preprocessor](../../../Sources/MLSDStructuralLineKit/MLSDTexturePreprocessor.swift) ·
[Core Video texture lifetime](https://developer.apple.com/documentation/corevideo/cvmetaltexturecachecreatetexturefromimage%28_%3A_%3A_%3A_%3A_%3A_%3A_%3A_%3A_%3A%29?changes=_3_2&language=objc)

Run `swift test` from the M-LSD repository root. Use the
existing CPU city reference, GPU inference and orientation checks, and artifact
identity checks. Exercise overlapping encodes with distinct inputs and delayed
GPU completion to verify each inference reads its own pixels.

## Overlay segment buffers

Replace the segment upload's `MTLDevice.makeBuffer(bytes:…)` with
`context.gpuAllocator.makeBuffer(length:memoryClass:label:)` using `.cpuWrites`.
Upload into a distinct buffer per encoded draw so each draw owns its data
through GPU completion. The output texture already uses the shared allocator
through `renderer.newImage`. Keep the current compositing path for fixed
RGBA16-float output, presentation-pixel width, transforms, alpha, and score
filtering. Fabric's `newImage(copying:)` preserves the source format.
[Overlay node](../../../FabricMLSDNode/FabricMLSDNode/Nodes/MLSDStructuralLineOverlayNode.swift) ·
[Satin allocator](https://github.com/Fabric-Project/Satin/pull/68) ·
[Fabric image copy API](https://github.com/Fabric-Project/Fabric/blob/c1da66398ae4b28c266e0b3d4ef456d60c97f171/Fabric/Graph/GraphRenderer.swift#L887-L906)

Rebuild the Debug bundle and run `verify_node_capacity.py` and
`verify_overlay_shader.swift` against it. Also check pixels from two overlay
node draws with different segments in one command buffer to catch upload
overwrites. Include an empty or fully filtered input to check pass-through.

## Analyze result delivery

On the current pin, combine `super.isDirty` with readiness from a synchronized
mailbox so a Processor with a completed result runs even on a static input.
The worker writes only the mailbox. The graph execution owner consumes it in
`execute`, updates scheduling state, and publishes `Lines`, `Scores`, `Count`,
`Size`, and the matching `Frame` before downstream evaluation. This replaces the
`Task { @MainActor }` and `markDirty()` handoff. Preserve one active inference,
one newest eligible pending input, and the `Interval` rules for changed images
and parameter edits. Encode preprocessing after upstream writes in the graph's
current command-buffer segment.
[Analyze node](../../../FabricMLSDNode/FabricMLSDNode/Nodes/MLSDStructuralLineAnalysisNode.swift) ·
[Fabric processor hook](https://github.com/Fabric-Project/Fabric/blob/c1da66398ae4b28c266e0b3d4ef456d60c97f171/Fabric/Graph/Node/Node.swift#L210-L215)

Keep request retirement independent of output delivery. A failed or abandoned
GPU segment, model error, disconnect, or stop must release or invalidate the
appropriate request so the next valid input can run. Check request identity at
publication and clear the outputs on disconnect. Preserve recoverable error
reporting and the empty result on inference failure. Retain the request's
source image and presentation metadata for frame pairing.

Fabric's `addCompletion(operation:receive:)` is the candidate for grouped
delivery to the matching Iterator scope. On this pin it holds a frame slot
until the async operation finishes, so slow inference can stall new frame
admission. Keep Core ML outside that batch on the current pin. Adopt scoped
delivery when the host can keep drawing with inference held past
`maxBuffersInFlight` and deliver separate results to each Iterator occurrence.
Use Fabric's scope for that migration. The public iteration index describes
only the innermost iteration. Same-frame Core ML output would require an
export-aware scheduling change. [Deferred delivery](https://github.com/Fabric-Project/Fabric/pull/442) ·
[Frame admission test](https://github.com/Fabric-Project/Fabric/blob/c1da66398ae4b28c266e0b3d4ef456d60c97f171/Tests/DeferredGPUResultTests.swift#L494-L514) ·
[Export render path](https://github.com/Fabric-Project/Fabric/blob/c1da66398ae4b28c266e0b3d4ef456d60c97f171/Fabric/Graph/GraphExportRenderer.swift#L96-L120)

Verify through `GraphRenderer` with a static image in a clean subgraph, a
sequence of identifiable frames, and deliberately delayed inference. Confirm
the graph keeps drawing, the final pending eligible frame is consumed even
after input stops changing, and all five outlets refer to the same request.
Exercise `Interval`, threshold and limit edits, disconnect/reconnect,
stop/restart, GPU abandonment, and recoverable failure. For scoped delivery,
include distinct inputs in nested Iterator slots and confirm that removing a
slot discards its old result.

## Geometry example with Stroke Geometry

Once Fabric `main` includes Stroke Geometry and pins the corresponding Satin
API, prototype the wiring in a copy of `MLSDGeoExample.fabric`. Connect
`M-LSD Positions` to Stroke Geometry's `Positions`. Send Analyze `Count` to an
integer `Repeat` with `Value = 2` and connect its array to `Stroke Lengths`.
Each pair draws a separate stroke with a width in world units.
[Satin polyline PR](https://github.com/Fabric-Project/Satin/pull/58) ·
[Fabric feature branch node](https://github.com/Fabric-Project/Fabric/blob/861f83e8c9ab49b20c361e42c3b3dbfb631db9c0/Fabric/Nodes/Geometry/StrokeGeometryNode.swift#L40-L52) ·
[Repeat node](https://github.com/Fabric-Project/Fabric/blob/c1da66398ae4b28c266e0b3d4ef456d60c97f171/Fabric/Nodes/Parameters/Numeric/RepeatNode.swift)

Verify two separated segments, a nonempty → empty → nonempty transition, and
1,000 segments. Check the geometry scene after save and reopen before updating
the shipped example and its wiring instructions. The image overlay continues to
use its presentation-pixel Metal shader. The Geometry Compose empty-input bug
belongs to Fabric's Geometry Compose node.

## Workspace verification

Start implementation with the preprocessing lifetime fix and checkpoint each
verified milestone in the plug-in handoff. Build the embedded Debug Editor
with `./Scripts/build-workspace.sh` after the current-pin changes and check
the three M-LSD nodes and both sample scenes, including a saved graph with an
authored `Max Lines` value. Update the affected integration-gap notes with the
verified behavior. Advance workspace pins for the stroke example through the
workspace update runbook after testing the compatible host and plug-in pair.
[Fabric integration gaps](../../FABRIC_INTEGRATION_GAPS.md)
