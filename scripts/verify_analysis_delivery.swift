import Fabric
import Foundation
import Metal
import MetalKit
import Satin
import simd

struct VerificationError: Error, CustomStringConvertible
{
    let description: String
    init(_ description: String) { self.description = description }
}

func require<Value>(_ value: Value?, _ message: String) throws -> Value
{
    guard let value else { throw VerificationError(message) }
    return value
}

func expect(_ condition: Bool, _ message: String) throws
{
    guard condition else { throw VerificationError(message) }
}

final class StaticImageSource: Node
{
    override class var name: String { "M-LSD Test Image Source" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String { "Publishes a test image on demand" }

    override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) + [("image", NodePort<FabricImage>(name: "Image", kind: .Outlet))]
    }

    var output: NodePort<FabricImage> { port(named: "image") }
}

final class Fixture
{
    let context: Context
    let graph: Graph
    let renderer: GraphRenderer
    let target: MTLTexture
    var frameNumber = 0

    init(context: Context, graph: Graph) throws
    {
        self.context = context
        self.graph = graph
        self.renderer = GraphRenderer(context: context, graph: graph)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 128, height: 128, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        self.target = try require(context.device.makeTexture(descriptor: descriptor), "Missing draw target")
        self.renderer.resize(size: (128, 128), scaleFactor: 1)
        try self.renderer.startExecution()
    }

    func record(_ commands: MTLCommandBuffer) throws
    {
        let timing = GraphExecutionTiming(time: Double(frameNumber) / 60, deltaTime: 1 / 60,
            displayTime: nil, systemTime: 0, hostMediaTime: 0, frameNumber: frameNumber)
        frameNumber += 1
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        if context.depthPixelFormat != .invalid
        {
            pass.depthAttachment.texture = renderer.getDepthTexture(ref: target, index: 0)
            pass.depthAttachment.loadAction = .clear
        }
        try renderer.executeAndDraw(executionInfo: GraphExecutionInfo(timing: timing),
                                    renderPassDescriptor: pass, commandBuffer: commands)
    }

    func draw() throws
    {
        let commands = try require(renderer.makeCommandBuffer(), "Missing Fabric command buffer")
        var recoverableError: FabricError?
        do { try record(commands) }
        catch let error as FabricError where error.severity == .recoverable { recoverableError = error }
        commands.commit()
        commands.waitUntilCompleted()
        try expect(commands.status == .completed, "Fabric draw failed")
        if let recoverableError { throw recoverableError }
    }

    func drawUntil(_ message: String, _ condition: () -> Bool) throws
    {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat
        {
            try draw()
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.005)
        }
        while ContinuousClock.now < deadline
        throw VerificationError(message)
    }
}

struct AnalysisPorts
{
    let node: Node
    var image: NodePort<FabricImage> { node.port(named: "inputImage") }
    var maxLines: ParameterPort<Int> { node.port(named: "inputMaximumLines") }
    var minScore: ParameterPort<Float> { node.port(named: "inputMinimumConfidence") }
    var interval: ParameterPort<Int> { node.port(named: "inputAnalysisInterval") }
    var lines: NodePort<ContiguousArray<SIMD4<Float>>> { node.port(named: "outputSegments") }
    var scores: NodePort<ContiguousArray<Float>> { node.port(named: "outputConfidences") }
    var count: NodePort<Int> { node.port(named: "outputLineCount") }
    var size: NodePort<SIMD2<Float>> { node.port(named: "outputSourceSize") }
    var frame: NodePort<FabricImage> { node.port(named: "outputAnalyzedImage") }

    func expectResult(image: FabricImage, lineCount: Int) throws
    {
        try expect(frame.value === image, "Frame did not match its request")
        try expect(count.value == lineCount && lines.value?.count == lineCount && scores.value?.count == lineCount,
                   "Count, Lines, and Scores did not match the request")
        try expect(size.value == SIMD2(Float(image.presentationSize.width), Float(image.presentationSize.height)),
                   "Size did not match the paired frame")
    }

    func expectEmpty() throws
    {
        try expect(frame.value == nil && count.value == 0 && lines.value?.isEmpty == true
                   && scores.value?.isEmpty == true && size.value == .zero, "Analyze left stale outlets")
    }
}

let path = try require(CommandLine.arguments.dropFirst().first, "Pass the .fabricplugin path")
let pluginURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
let bundle = try require(Bundle(url: pluginURL), "Missing plug-in bundle")
let pluginID = try require(bundle.bundleIdentifier, "Missing M-LSD bundle ID")
let registry = try NodeRegistry.shared
let loaded = try require(PluginLoader.shared.loadedPlugins[pluginID], "Fabric did not discover M-LSD")
try expect(loaded.bundleURL.resolvingSymlinksInPath().path == pluginURL.path,
           "Fabric discovered a different M-LSD bundle")
let analyzeClass = try require(registry.nodeClass(pluginID: pluginID, nodeID: "MLSDStructuralLineAnalysisNode"), "Missing Analyze node")
let device = try require(MTLCreateSystemDefaultDevice(), "Missing Metal device")
let context = Context(device: device, sampleCount: 1, colorPixelFormat: .rgba16Float)
let delayedQueue = try require(device.makeCommandQueue(), "Missing independent Metal queue")
let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("FabricScenes/DubaiTestImage.jpg")
let texture = try MTKTextureLoader(device: device).newTexture(URL: sourceURL, options: [.SRGB: false])

func testCleanSubgraph() throws
{
    let analysis = AnalysisPorts(node: analyzeClass.init(context: context))
    analysis.image.published = true
    analysis.frame.published = true
    analysis.maxLines.value = 3
    let inner = Graph(context: context)
    inner.addNode(analysis.node)
    let subgraph = SubgraphNode(context: context, subGraph: inner)
    let input = try require(subgraph.ports.first { $0.id == analysis.image.id } as? NodePort<FabricImage>, "Missing image inlet")
    let frame = try require(subgraph.ports.first { $0.id == analysis.frame.id } as? NodePort<FabricImage>, "Missing frame outlet")
    frame.published = true
    let graph = Graph(context: context)
    graph.addNode(subgraph)
    let fixture = try Fixture(context: context, graph: graph)
    let image = FabricImage.unmanaged(texture: texture)
    input.value = image

    let gate = try require(device.makeSharedEvent(), "Missing Metal shared event")
    let commands = try require(delayedQueue.makeCommandBuffer(), "Missing delayed command buffer")
    commands.encodeWaitForEvent(gate, value: 1)
    try fixture.record(commands)
    commands.commit()
    defer { gate.signaledValue = 1 }

    try expect(!subgraph.isDirty && frame.value == nil, "Subgraph was not clean while work was pending")
    for _ in 0 ..< (context.maxBuffersInFlight + 2) { try fixture.draw() }
    try expect(frame.value == nil, "Result published before GPU preparation completed")
    gate.signaledValue = 1
    try fixture.drawUntil("Clean subgraph did not publish its completed static image") { frame.value === image }
    try analysis.expectResult(image: image, lineCount: 3)
    let topLines = analysis.lines.value
    let topScores = analysis.scores.value

    analysis.maxLines.value = 2
    try fixture.drawUntil("Max Lines edit did not analyze the static image") { analysis.count.value == 2 }
    try analysis.expectResult(image: image, lineCount: 2)
    try expect(analysis.lines.value == topLines.map { ContiguousArray($0.prefix(2)) }
               && analysis.scores.value == topScores.map { ContiguousArray($0.prefix(2)) }, "Cap changed the highest-scoring lines")
    analysis.minScore.value = 1
    try fixture.drawUntil("Threshold edit did not analyze the static image") { analysis.count.value == 0 }
    try analysis.expectResult(image: image, lineCount: 0)
}

func testRequestRetirement() throws
{
    let graph = Graph(context: context)
    let source = StaticImageSource(context: context)
    let analysis = AnalysisPorts(node: analyzeClass.init(context: context))
    analysis.frame.published = true
    analysis.maxLines.value = 3
    analysis.interval.value = 2
    graph.addNode(source)
    graph.addNode(analysis.node)
    try expect(graph.connect(source.output, to: analysis.image) != nil, "Missing image connection")
    let fixture = try Fixture(context: context, graph: graph)
    let first = FabricImage.unmanaged(texture: texture)
    let lastEligible = FabricImage.unmanaged(texture: texture)
    lastEligible.textureTransform = simd_float4x4(
        SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
        SIMD4(0, 0, 1, 0), SIMD4(1, 0, 0, 1)
    )
    let lastIneligible = FabricImage.unmanaged(texture: texture)
    source.output.send(first)

    let gate = try require(device.makeSharedEvent(), "Missing Metal shared event")
    let commands = try require(delayedQueue.makeCommandBuffer(), "Missing delayed command buffer")
    commands.encodeWaitForEvent(gate, value: 1)
    try fixture.record(commands)
    commands.commit()
    defer { gate.signaledValue = 1 }

    for image in [FabricImage.unmanaged(texture: texture), FabricImage.unmanaged(texture: texture),
                  FabricImage.unmanaged(texture: texture), lastEligible, lastIneligible]
    {
        source.output.send(image)
        try fixture.draw()
    }
    try expect(analysis.frame.value == nil, "Analyze published while the active request was blocked")
    gate.signaledValue = 1
    try fixture.drawUntil("Newest eligible image was lost when the input stopped changing") { analysis.frame.value === lastEligible }
    try analysis.expectResult(image: lastEligible, lineCount: 3)
    try expect(analysis.size.value == SIMD2(Float(texture.height), Float(texture.width)),
               "Analyze lost the orientation of the queued frame")
    analysis.interval.value = 1
    try fixture.drawUntil("Interval edit did not analyze the latest static image") { analysis.frame.value === lastIneligible }

    let abandoned = FabricImage.unmanaged(texture: texture)
    source.output.send(abandoned)
    try autoreleasepool {
        let commands = try require(fixture.renderer.makeCommandBuffer(), "Missing abandoned segment")
        try fixture.record(commands)
    }
    try fixture.drawUntil("Dropped command buffer stranded Analyze") { analysis.frame.value === abandoned }

    let failed = FabricImage.unmanaged(texture: texture)
    source.output.send(failed)
    let failedBuffer = try require(fixture.renderer.makeCommandBuffer(), "Missing failure fixture buffer")
    let failureLibrary = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        kernel void failCommand() { __builtin_trap(); }
        """, options: nil)
    let failureFunction = try require(failureLibrary.makeFunction(name: "failCommand"), "Missing failure kernel")
    let failedEncoder = try require(failedBuffer.makeComputeCommandEncoder(), "Missing failure encoder")
    failedEncoder.setComputePipelineState(try device.makeComputePipelineState(function: failureFunction))
    let oneThread = MTLSize(width: 1, height: 1, depth: 1)
    failedEncoder.dispatchThreads(oneThread, threadsPerThreadgroup: oneThread)
    failedEncoder.endEncoding()
    try fixture.record(failedBuffer)
    failedBuffer.commit()
    failedBuffer.waitUntilCompleted()
    try expect(failedBuffer.status == .error, "Failure fixture did not produce a Metal error")
    do
    {
        try fixture.drawUntil("GPU failure did not reach Fabric") { analysis.frame.value == nil }
        throw VerificationError("GPU failure cleared outlets without reporting an error")
    }
    catch let error as FabricError
    {
        try expect(error.severity == .recoverable, "GPU failure was fatal")
        try analysis.expectEmpty()
    }

    source.output.send(first)
    try fixture.drawUntil("Valid image after failure did not run") { analysis.frame.value === first }
    let reconnectGate = try require(device.makeSharedEvent(), "Missing disconnect gate")
    let reconnectCommands = try require(delayedQueue.makeCommandBuffer(), "Missing disconnect segment")
    reconnectCommands.encodeWaitForEvent(reconnectGate, value: 1)
    source.output.send(lastEligible)
    try fixture.record(reconnectCommands)
    reconnectCommands.commit()
    defer { reconnectGate.signaledValue = 1 }

    try expect(graph.disconnect(source.output, from: analysis.image), "Image did not disconnect")
    try fixture.draw()
    try analysis.expectEmpty()
    source.output.send(lastIneligible)
    try expect(graph.connect(source.output, to: analysis.image) != nil, "Image did not reconnect")
    try fixture.draw()
    try analysis.expectEmpty()
    try fixture.renderer.stopExecution()
    try analysis.expectEmpty()
    try fixture.renderer.startExecution()
    try fixture.draw()
    try analysis.expectEmpty()
    reconnectGate.signaledValue = 1
    try fixture.drawUntil("Stopped request published after restart or blocked its replacement") {
        analysis.frame.value != nil
    }
    try analysis.expectResult(image: lastIneligible, lineCount: 3)

    // Replacing the wire within one frame can leave a nonnil Image throughout
    // the next evaluation. Reject the waiting result using the connection ID.
    source.output.send(lastEligible)
    try fixture.draw()
    try waitForAnalysis(analysis.node)
    try expect(graph.disconnect(source.output, from: analysis.image), "Could not replace image connection")
    source.output.send(first)
    try expect(graph.connect(source.output, to: analysis.image) != nil, "Could not replace image connection")
    try fixture.draw()
    try analysis.expectEmpty()
    try fixture.drawUntil("New source did not run after replacing its connection") { analysis.frame.value != nil }
    try analysis.expectResult(image: first, lineCount: 3)

    let invalid = FabricImage.unmanaged(texture: texture)
    invalid.textureTransform = simd_float4x4(diagonal: SIMD4(0, 1, 1, 1))
    source.output.send(invalid)
    do
    {
        try fixture.draw()
        throw VerificationError("Analyze accepted invalid presentation dimensions")
    }
    catch let error as FabricError
    {
        try expect(error.severity == .recoverable, "Invalid input was fatal")
        try analysis.expectEmpty()
    }
    source.output.send(lastIneligible)
    try fixture.drawUntil("Valid image after invalid input did not run") { analysis.frame.value === lastIneligible }
}

func waitForAnalysis(_ node: Node) throws
{
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !node.isDirty && ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.005) }
    try expect(node.isDirty, "M-LSD did not complete the submitted request")
}

func testSavedScenes() throws
{
    let registeredNames = registry.availableNodes.filter { $0.pluginBundleID == pluginID }.map(\.nodeName)
    try expect(Set(registeredNames) == ["M-LSD Analyze", "M-LSD Overlay", "M-LSD Positions"],
               "Fabric registered unexpected M-LSD nodes: \(registeredNames)")
    let sceneContext = Context(device: device, sampleCount: 1, colorPixelFormat: .rgba16Float, depthPixelFormat: .depth32Float)
    let decoder = JSONDecoder()
    decoder.context = DecoderContext(documentContext: sceneContext, fileReferenceBaseURL: sourceURL.deletingLastPathComponent())

    for name in ["MLSDExample", "MLSDGeoExample"]
    {
        let url = sourceURL.deletingLastPathComponent().appendingPathComponent("\(name).fabric")
        let graph = try decoder.decode(Graph.self, from: Data(contentsOf: url))
        let savedAnalysis = AnalysisPorts(node: try require(graph.nodes.first { type(of: $0) == analyzeClass }, "\(name) lost Analyze"))
        try expect(savedAnalysis.maxLines.value == 200, "\(name) lost its authored Max Lines value")
        let savedProvider = try require(graph.nodes.compactMap { $0 as? ImageProviderNode }.first, "\(name) lost Image Provider")
        savedProvider.setFileURL(sourceURL)

        let reopened = try decoder.decode(Graph.self, from: JSONEncoder().encode(graph))
        try expect(reopened.nodes.map(\.id) == graph.nodes.map(\.id)
                   && Set(reopened.connections.map(\.id)) == Set(graph.connections.map(\.id)), "\(name) changed nodes or wires on reopen")
        let analysis = AnalysisPorts(node: try require(reopened.nodes.first { $0.id == savedAnalysis.node.id }, "\(name) lost Analyze on reopen"))
        try expect(analysis.maxLines.value == 200 && (analysis.maxLines.parameter as? IntParameter)?.max == 1000,
                   "\(name) lost its saved limit or current range on reopen")
        let fixture = try Fixture(context: sceneContext, graph: reopened)
        try fixture.drawUntil("\(name) did not finish analysis") { analysis.frame.value != nil }
        let image = try require(analysis.frame.value, "\(name) has no paired frame")
        let count = try require(analysis.count.value, "\(name) has no segment count")
        try expect((1...200).contains(count), "\(name) did not detect any lines within the saved limit")
        try analysis.expectResult(image: image, lineCount: count)

        if let compose = reopened.nodes.compactMap({ $0 as? PixelArrayToGeometryNode }).first
        {
            let mesh = try require(reopened.nodes.compactMap { $0 as? MeshNode }.first, "\(name) lost Mesh")
            try expect(mesh.inputGeometry.value === compose.geometry && compose.geometry.vertexCount == 2 * count
                       && compose.geometry.primitiveType == .line, "\(name) did not produce two line vertices per segment")
        }
        else
        {
            let overlay = try require(reopened.nodes.first { type(of: $0).name == "M-LSD Overlay" }, "\(name) lost Overlay")
            let background: NodePort<FabricImage> = overlay.port(named: "inputImage")
            let output: NodePort<FabricImage> = overlay.port(named: "outputImage")
            try expect(background.value === image && output.value?.texture.pixelFormat == .rgba16Float,
                       "\(name) did not draw the paired analysis frame")
        }

        let width = fixture.target.width
        let height = fixture.target.height
        var pixels = [Float16](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            fixture.target.getBytes(bytes.baseAddress!, bytesPerRow: width * 8,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        try expect(pixels.contains { $0 > 0.05 }, "\(name) rendered an empty image")
        print("\(name) loaded, round-tripped Max Lines = 200, and rendered \(count) paired lines")
    }
}

do
{
    try testCleanSubgraph()
    print("M-LSD clean subgraph passed: static result delivery, continued drawing, threshold and limit edits")
    try testRequestRetirement()
    print("M-LSD request retirement passed: latest eligible frame, interval edit, abandonment, recoverable failure, disconnect and restart")
    try testSavedScenes()
}
catch
{
    FileHandle.standardError.write(Data("M-LSD verification failed: \(error)\n".utf8))
    exit(1)
}
