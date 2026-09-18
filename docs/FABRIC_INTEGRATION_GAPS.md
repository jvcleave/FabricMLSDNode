# Fabric Integration Gaps

This document records places where the M-LSD plug-in must adapt around the
current Fabric API. It is an input to possible Fabric API proposals, not a
request for this plug-in to modify Fabric. Each entry separates the observed
constraint from the local workaround and the more general capability that
would remove it.

## 1. Plug-ins cannot publish domain-specific value types

**Observed constraint:** `PortType` and `PortValue` are closed enums owned by
Fabric. `NodePort<Value>` also requires `Value: PortValueRepresentable`, whose
boxing and unboxing contract terminates in `PortValue`. An external plug-in
therefore cannot register a serializable `StructuralLineFrame` value without
adding cases to Fabric itself.

Host source: `Fabric/Graph/Port/PortType.swift`,
`Fabric/Graph/Port/PortValueRepresentable.swift`, and
`Fabric/Graph/Port/NodePort.swift` in the adjacent Fabric repository.

**Local workaround:** The analysis node decomposes one structural-line frame
into Fabric's existing typed values:

- `ContiguousArray<SIMD4<Float>>` for segments, packed as
  `[startX, startY, endX, endY]` in normalized bottom-left coordinates.
- `ContiguousArray<Float>` for index-aligned confidence values.
- `Int` for line count.
- `SIMD2<Float>` for presentation source size.
- `FabricImage` for the image paired with the completed result, avoiding a
  mismatch with newer upstream frames during interactive overlay rendering.

This remains typed and serializable, but Fabric cannot express that both arrays
belong to one atomic frame or enforce equal counts at a connection boundary.

**Potential Fabric API direction:** Add a public custom-value registration
mechanism with a stable type identifier, Codable snapshot representation,
runtime compatibility check, and optional inspector metadata. A plug-in should
be able to register one value adapter without extending Fabric enums or
requiring Fabric to link the plug-in's concrete type when a document is merely
inspected.

## 2. Asynchronous completion has no documented invalidation boundary

**Observed constraint:** `Node.markDirty()` mutates a plain Boolean and has no
documented thread-safety or actor contract. Metal completion handlers and model
callbacks do not run on Fabric's graph-execution thread. Publishing ports or
calling `markDirty()` directly from those callbacks could race graph traversal
and `markClean()`.

Host source: `Fabric/Graph/Node/Node.swift` and
`Fabric/Graph/GraphRenderer.swift`.

**Local workaround:** The plug-in transfers completed inference from its serial
queue through `Task { @MainActor in ... }` to update node bookkeeping and call
`markDirty()`. Port publication occurs only when Fabric next calls `execute()`.
This assumes interactive graph execution and node mutation are main-thread
owned, an assumption reflected by existing Fabric asynchronous UI state but not
stated as a Node API guarantee.

**Potential Fabric API direction:** Provide a renderer- or graph-owned method
such as `scheduleNodeInvalidation(_:)` that is safe from any thread and orders
invalidation against the current pass's final `markClean()`. Alternatively,
declare Node lifecycle and port publication `@MainActor` and provide an explicit
nonisolated ingress for asynchronous results.

## 3. GPU-dependent CPU analysis has no node scheduling protocol

**Observed constraint:** An image supplied to a node may be produced earlier in
Fabric's still-uncommitted command buffer. Starting a separate command buffer
for preprocessing can race those upstream writes, while waiting inside
`execute()` would deadlock or serialize rendering. Fabric exposes the current
command buffer but no standard continuation hook for CPU work that depends on
its completion.

Host source: `Fabric/Graph/GraphRenderer.swift`, especially its
`execute(graph:executionInfo:renderPassDescriptor:commandBuffer:)` contract.

**Local workaround:** M-LSD preprocessing is encoded onto Fabric's current
command buffer. The package attaches a completion handler, moves Core ML work
to its own serial queue, and returns from `execute()` immediately. The node
allows one active inference and retains only the newest eligible pending image,
preventing an unbounded frame backlog.

**Potential Fabric API direction:** Define an asynchronous processor contract
that can:

1. Encode GPU preparation into the current pass.
2. Start CPU/model work after that pass completes.
3. Publish a result tagged with its source frame or generation.
4. Request a later graph evaluation through Fabric-owned scheduling.
5. Cancel or supersede obsolete pending work during stop, seek, or source
   replacement.

Fabric could then own ordering, lifetime, cancellation, diagnostics, and frame
provenance instead of every plug-in rebuilding that state machine.

## 4. Deterministic export cannot await asynchronous node results

**Observed constraint:** `GraphExportRenderer.renderFrame` executes the graph,
commits the Metal command buffer, waits for GPU completion, and returns. It has
no settle phase for CPU work launched after command-buffer completion and no
way for an asynchronous analysis node to make its result available to
downstream nodes in that same graph pass. An overlay connected to M-LSD will
therefore render the most recently completed analysis, not necessarily the
image requested for the current exported frame.

Host source: `Fabric/Graph/GraphExportRenderer.swift`, particularly
`renderFrame(into:depthTexture:time:)`.

**Local workaround:** The initial node is suitable for interactive latest-frame
analysis and explicitly bounds latency. It does not claim same-frame,
deterministic export semantics. A caller that requires exact pairing would need
an external two-stage workflow or a future Fabric scheduling facility.

**Potential Fabric API direction:** Add an export-aware asynchronous barrier or
multi-phase frame evaluation. Export could await registered node futures, then
re-evaluate only affected downstream nodes before drawing. `GraphExecutionInfo`
should expose execution intent (interactive, single-frame export, sequence
export) and a stable frame token so nodes can choose latency or determinism
without detecting renderer implementation types.

## 5. Processor nodes have no independent cadence request

**Observed constraint:** A Processor runs when dirty; a Provider runs every
pass. There is no public way for a Processor to request evaluation on a future
frame while remaining semantically input-driven. This makes a cadence control
easy for continually changing video inputs but ambiguous for a final static
image skipped between cadence intervals.

Host source: `Fabric/Graph/GraphRenderer.swift` and
`Fabric/Graph/Node/Node.swift` (`ExecutionMode`).

**Local workaround:** The node analyzes the first image immediately, then uses
the analysis-interval parameter as a count of changed input images. Parameter
changes bypass the interval. While inference is active, only an interval-
eligible newest request is retained.

**Potential Fabric API direction:** Allow a node to request its next evaluation
by frame number, graph time, or explicit invalidation token without changing
its `ExecutionMode`. Fabric should cancel that request automatically when the
node stops or leaves the graph.

## 6. External plug-in builds depend on Fabric's compiler artifacts

**Observed constraint:** The plug-in imports Fabric as a Swift module from an
adjacent checkout. Using Fabric's existing `.build` tree failed when that tree
contained module artifacts from a different compiler. Under Xcode 27, the
default SwiftPM build system also omitted the module-map layout required by
Fabric's current external plug-in setup. Swift modules are compiler- and
configuration-sensitive, so architecture, toolchain, and Debug/Release must
also agree between the host artifacts and the plug-in build.

The plug-in currently compiles against Fabric's generated module files and
uses `-undefined dynamic_lookup` so its Fabric symbols resolve from the host at
runtime. Its Swift include paths, C/C++ module maps, and transitive framework
paths therefore point inside SwiftPM's scratch-directory layout. Those paths
are build-system implementation details, not a supported Fabric SDK contract.
They can change without any source-level Fabric API change.

**Local workaround:** The Xcode preparation phase builds Fabric in this
repository's ignored `.fabric-spm/` scratch directory with SwiftPM's native
build system, then points the plug-in compiler and linker at that isolated
configuration-matched output. Debug and Release are built separately, and the
host Editor must use the matching configuration. This prevents an unrelated
Fabric build from poisoning the plug-in build, but it does not make the
artifact paths or linking model stable.

**Potential Fabric tooling direction:** Publish a supported Fabric SDK or
package product for plug-in compilation with stable module and linker paths,
or provide an official build helper that resolves the host revision, compiler,
architecture, and Debug/Release variant without depending on SwiftPM's
internal scratch layout. This is a build/distribution concern rather than a
runtime Node API change.

[#308](https://github.com/Fabric-Project/Fabric/issues/308) proposes a separate
Fabric plug-in target to avoid redundant SwiftPM resources and framework
embedding. That is a useful foundation, but resource cleanup alone does not
cover compiler compatibility, configuration selection, module-map discovery,
runtime symbol ownership, or host/API-version compatibility.

An acceptable supported build surface should:

1. Expose the node, port, parameter, plug-in registration, execution,
   `FabricImage`, error, and required Satin/Metal-facing contracts through a
   deliberately public product or SDK.
2. Build with, or provide compatible module interfaces for, the consuming
   plug-in's Swift toolchain, target triple, architecture, and configuration.
3. Preserve one host-owned Fabric runtime and one set of Node/Port type
   identities. A plug-in must not statically embed a second Fabric registry or
   runtime merely because it declared a package dependency.
4. Define the supported link/load mechanism—such as an official host-resolved
   dynamic-lookup setup or a shared dynamic framework—and provide stable
   compiler, linker, runpath, and module-map inputs for it.
5. Exclude Editor code, samples, models, shaders, and unrelated package
   resources/frameworks from the plug-in-facing surface.
6. Match the compiled surface to `FabricPluginAPIVersion` and report an
   actionable incompatibility when the host cannot load a plug-in safely.
7. Support clean-checkout Xcode and command-line/CI builds without consumers
   discovering or hard-coding paths under `.build` or another scratch tree.
8. Include a minimal external plug-in fixture that Fabric's CI builds and
   loads in both Debug and Release, guarding discovery, subclassing,
   registration, serialization, and symbol resolution.

A source-based `FabricPluginAPI` product is likely the simplest approach while
Fabric evolves rapidly, provided both the host and plug-ins share the same
runtime definitions rather than embedding duplicates. A versioned binary SDK
or XCFramework is another option, but it would need library-evolution module
interfaces, architecture coverage, distribution/versioning policy, and a
guarantee that the host ships the corresponding runtime. If #308 remains
limited to resource embedding, this broader build contract should be a linked,
focused SDK/tooling issue rather than being treated as solved by #308.

## 7. Plug-ins cannot request a wider canvas node

**Observed constraint:** Fabric computes canvas-node dimensions in
`Node.computeNodeSize()`. Horizontal ports affect height, while vertical ports
affect width. A node with only horizontal ports therefore stays at the
150-point minimum width regardless of its title or port-label lengths.
`NodeView` uses that computed width, `NodeTitleView` clips an overlong title,
and inlet/outlet labels occupy opposing stacks without a collision-avoidance
layout. A plug-in has no public node-width override. The original M-LSD
analysis labels visibly overlapped in the Editor even though their ports were
valid and correctly registered.

Host source: `Fabric/Graph/Node/Node.swift` (`nodeSize` and
`computeNodeSize()`), `Fabric/Views/Nodes/NodeView.swift`,
`Fabric/Views/Nodes/NodeTitleView.swift`, and
`Fabric/Graph/GraphAutoLayout.swift` in the adjacent Fabric repository.

**Local workaround:** The plug-in shortened its visible node titles and port
labels (`M-LSD Analyze`, `Min Score`, `Lines`, `Scores`, `Frame`) while retaining
stable Swift class names and port registry keys. Full meanings remain in port
descriptions and documentation. This improves the current layout but limits
how descriptive plug-in labels can be on the canvas.

**Potential Fabric API direction:** Let a node declare a preferred or minimum
canvas width, or let Fabric measure title and opposing port labels and choose
a bounded content-aware width. Fabric should apply the resolved size
consistently to `NodeView`, port anchors, selection, dragging, and graph
auto-layout; it should also define truncation behavior when labels exceed the
chosen maximum. This would let external plug-ins keep readable names without
managing Fabric's layout themselves.

## 8. Geometry Compose retains old vertices when Positions becomes empty

**Observed constraint:** `PixelArrayToGeometryNode.evaluate()` calls
`PointCloudGeometry.setData(...)` only when `inputPositions.value` is
nonempty. If a connected producer changes from line endpoints to an empty
array, the existing geometry retains its previous vertices. The M-LSD
positions adapter correctly publishes an empty array for zero detections, but
the built-in geometry path can continue drawing stale lines.

Host source: `Fabric/Nodes/Geometry/PixelArrayToGeometryNode.swift` in the
adjacent Fabric repository. This is a source-level finding; a live Editor
zero-line transition has not yet been verified.

**Local workaround:** Document `Positions → Geometry Compose (Line) → Mesh`
as an initial geometry experiment, not a validated live zero-line solution.
Keep zero-line publication explicit in the positions adapter. If the host
behavior persists in a live graph, a dedicated plug-in geometry node can own
and clear its stable geometry instance on empty input.

**Potential Fabric API direction:** Have Geometry Compose treat an empty
Positions array as a valid update and clear its vertex data, then force
publication of the changed geometry even when the object identity is stable.
Add a transition test covering nonempty → empty → nonempty arrays for Point
and Line primitives. This is likely a host-node correctness fix rather than a
new plug-in API.

## Existing Fabric GitHub issue coverage

Reviewed against the Fabric issue tracker on 2026-09-18. “Partial” means the
existing issue provides an appropriate discussion venue but does not yet state
the complete contract proposed above.

| Gap | Existing issue coverage | Assessment and next action |
| --- | --- | --- |
| 1. Domain-specific plug-in value types | [#296 Node Typification II](https://github.com/Fabric-Project/Fabric/issues/296) | **Related, not equivalent.** It covers unbounded type declarations and typed/virtual UX, but not external registration of a stable, serializable plug-in value. Open a focused issue or explicitly expand #296 before treating this gap as tracked. |
| 2. Thread-safe async invalidation | [#247 Async Node Protocol / Graph Renderer support](https://github.com/Fabric-Project/Fabric/issues/247); closed [#336 async inference texture lifetime](https://github.com/Fabric-Project/Fabric/issues/336) | **Partial.** #247 is the right umbrella for async nodes, while #336 confirms a related resource-lifetime hazard. Neither defines a thread-safe graph-owned invalidation boundary ordered against `markClean()`. Propose that contract on #247. |
| 3. GPU-dependent CPU analysis scheduling | [#247 Async Node Protocol / Graph Renderer support](https://github.com/Fabric-Project/Fabric/issues/247); [#155 FabricImage frame-time metadata](https://github.com/Fabric-Project/Fabric/issues/155) | **Strong conceptual coverage.** #247 explicitly includes ML inference and GraphRenderer-controlled async/sync modes; #155 is useful for source-frame provenance. Add the GPU-completion continuation, cancellation, latest-pending, and frame-token requirements to #247. |
| 4. Deterministic export awaiting async work | [#247 Async Node Protocol / Graph Renderer support](https://github.com/Fabric-Project/Fabric/issues/247) | **Strong conceptual coverage, incomplete contract.** Its realtime/async versus offline/sync distinction is the right home, but it does not yet define an export settle barrier or affected-downstream reevaluation. Extend #247 rather than opening a duplicate. |
| 5. Independent Processor cadence | None found | **Untracked.** Open a focused issue for future-frame/time/token evaluation requests that preserve Processor semantics and cancel with node lifecycle. |
| 6. Supported plug-in build surface | [#308 SwiftPM embeds resources not needed for plugins](https://github.com/Fabric-Project/Fabric/issues/308) | **Partial.** Its proposed Fabric Plugin target addresses redundant resources, but not compiler-version artifacts, module-map layout, configuration matching, or a stable SDK/build helper. Expand #308 if one plug-in build epic is desired; otherwise open a narrower SDK/tooling issue linked to it. |
| 7. Configurable canvas-node width | Closed [#110 Node title legibility](https://github.com/Fabric-Project/Fabric/issues/110); closed [#221 Layout issues](https://github.com/Fabric-Project/Fabric/issues/221) | **Adjacent only.** Neither supplies a plug-in preferred/minimum width or content-aware port-label layout contract. Open a focused editor/API issue. |
| 8. Geometry Compose empty-array clearing | [#265 Line Geometry Node](https://github.com/Fabric-Project/Fabric/issues/265) is adjacent only | **Untracked.** #265 concerns generating thick line geometry, not clearing composed geometry. After reproducing the nonempty → empty transition live, open a focused Geometry Compose correctness issue with a transition test. |

The most efficient upstream path is therefore to consolidate gaps 2–4 on
[#247](https://github.com/Fabric-Project/Fabric/issues/247), add the missing
plug-in build requirements to [#308](https://github.com/Fabric-Project/Fabric/issues/308),
and file focused issues for gaps 5 and 7. Gap 8 should wait for the planned live
transition reproduction. Gap 1 needs an explicit decision from the #296 owners
on whether plug-in-defined serialized values belong within that issue's scope.

## Proposal priorities

The highest-value changes are thread-safe invalidation and deterministic async
export because they affect correctness for every GPU-to-CPU analysis plug-in.
Custom value registration would most improve plug-in ergonomics and preserve
atomic domain contracts. A general cadence API is useful but can follow the
core asynchronous scheduling contract. Configurable node width is a lower-risk
editor ergonomics improvement that would benefit any plug-in with descriptive
port labels. Geometry Compose's empty-array behavior is a focused correctness
fix if confirmed in a live graph.
