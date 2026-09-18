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
Fabric's current external plug-in setup.

**Local workaround:** The Xcode preparation phase builds Fabric in this
repository's ignored `.fabric-spm/` scratch directory with SwiftPM's native
build system, then points the plug-in compiler and linker at that isolated
configuration-matched output. Debug and Release are built separately, and the
host Editor must use the matching configuration.

**Potential Fabric tooling direction:** Publish a supported Fabric SDK or
package product for plug-in compilation with stable module and linker paths,
or provide an official build helper that resolves the host revision, compiler,
architecture, and Debug/Release variant without depending on SwiftPM's
internal scratch layout. This is a build/distribution concern rather than a
runtime Node API change.

## Proposal priorities

The highest-value changes are thread-safe invalidation and deterministic async
export because they affect correctness for every GPU-to-CPU analysis plug-in.
Custom value registration would most improve plug-in ergonomics and preserve
atomic domain contracts. A general cadence API is useful but can follow the
core asynchronous scheduling contract.
