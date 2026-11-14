import Fabric
import Foundation
import Metal
import Satin
import simd

enum CapacityFailure: Error
{
    case failed(String)
}

func require<Value>(_ value: Value?, _ message: String) throws -> Value
{
    guard let value else { throw CapacityFailure.failed(message) }
    return value
}

func expect(_ condition: Bool, _ message: String) throws
{
    if !condition { throw CapacityFailure.failed(message) }
}

let path = try require(CommandLine.arguments.dropFirst().first, "Pass the .fabricplugin path")
let bundle = try require(Bundle(path: path), "Missing plug-in bundle")
try bundle.loadAndReturnError()
let plugin = try require(bundle.principalClass as? any FabricPlugin.Type, "Missing principal class")
let device = try require(MTLCreateSystemDefaultDevice(), "Missing Metal device")
let context = Context(device: device, sampleCount: 1, colorPixelFormat: .rgba16Float)
let graph = Graph(context: context)
let renderer = GraphRenderer(context: context, graph: graph)
let timing = GraphExecutionTiming(time: 0, deltaTime: 0, displayTime: nil,
    systemTime: 0, hostMediaTime: 0, frameNumber: 0)
let executionInfo = GraphExecutionInfo(timing: timing)
let commandBuffer = try require(context.commandQueue.makeCommandBuffer(), "Missing command buffer")
let pass = MTLRenderPassDescriptor()

func makeNode(_ name: String) throws -> Node
{
    let nodeClass = try require(plugin.additionalNodeClasses().first { $0.name == name }, "Missing \(name)")
    return nodeClass.init(context: context)
}

func execute(_ node: Node) throws
{
    try node.execute(renderer: renderer, executionInfo: executionInfo,
        renderPassDescriptor: pass, commandBuffer: commandBuffer)
}

func copyPixels(from texture: MTLTexture) throws -> MTLBuffer
{
    let bytesPerRow = 256
    let length = bytesPerRow * texture.height
    let buffer = try require(device.makeBuffer(length: length, options: .storageModeShared), "Missing readback buffer")
    let blit = try require(commandBuffer.makeBlitCommandEncoder(), "Missing overlay readback encoder")
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(),
        sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
        to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
        destinationBytesPerImage: length)
    blit.endEncoding()
    return buffer
}

func greenChannel(_ buffer: MTLBuffer, x: Int, y: Int) -> Float16
{
    buffer.contents().load(fromByteOffset: y * 256 + x * 8 + 2, as: Float16.self)
}

let analysis = try makeNode("M-LSD Analyze")
let maximumLines: ParameterPort<Int> = analysis.port(named: "inputMaximumLines")
let maximumParameter = try require(maximumLines.parameter as? IntParameter, "Missing Max Lines parameter")
try expect(maximumLines.value == 1000 && maximumParameter.max == 1000, "Analyze capacity/default")

let segments = ContiguousArray(repeating: SIMD4<Float>(0.25, 0.25, 0.75, 0.25), count: 1000)
let positions = try makeNode("M-LSD Positions")
let positionLines: NodePort<ContiguousArray<SIMD4<Float>>> = positions.port(named: "inputSegments")
let size: NodePort<SIMD2<Float>> = positions.port(named: "inputSourceSize")
let width: ParameterPort<Float> = positions.port(named: "inputPlaneWidth")
let outputPositions: NodePort<ContiguousArray<SIMD3<Float>>> = positions.port(named: "outputPositions")
positionLines.value = segments
size.value = SIMD2(1920, 1080)
width.value = 2
try execute(positions)
let endpoints = try require(outputPositions.value, "Missing endpoints")
try expect(endpoints.count == 2000, "Positions truncated the 1,000 line pairs")
try expect(endpoints[1998] == SIMD3(-0.5, -0.28125, 0), "Final start endpoint or aspect mismatch")
try expect(endpoints[1999] == SIMD3(0.5, -0.28125, 0), "Final end endpoint mismatch")
positionLines.value = []
try execute(positions)
try expect(outputPositions.value?.isEmpty == true, "Positions failed to clear on empty input")
positionLines.value = segments + [SIMD4<Float>(0, 0, 1, 1)]
do
{
    try execute(positions)
    throw CapacityFailure.failed("Positions accepted 1,001 lines")
}
catch is FabricError {}
try expect(outputPositions.value?.isEmpty == true, "Invalid Positions input left stale endpoints")

let overlay = try makeNode("M-LSD Overlay")
let overlayLines: NodePort<ContiguousArray<SIMD4<Float>>> = overlay.port(named: "inputSegments")
let inputImage: NodePort<FabricImage> = overlay.port(named: "inputImage")
let outputImage: NodePort<FabricImage> = overlay.port(named: "outputImage")
let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba8Unorm, width: 16, height: 16, mipmapped: false)
textureDescriptor.storageMode = .shared
textureDescriptor.usage = .shaderRead
let texture = try require(device.makeTexture(descriptor: textureDescriptor), "Missing source texture")
let pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
pixels.withUnsafeBytes { bytes in
    if let address = bytes.baseAddress
    {
        texture.replace(region: MTLRegionMake2D(0, 0, 16, 16), mipmapLevel: 0,
            withBytes: address, bytesPerRow: 16 * 4)
    }
}
let sourceImage = FabricImage.unmanaged(texture: texture)
inputImage.value = sourceImage
// Only the final instance crosses the asserted pixel in each draw.
var firstDraw = ContiguousArray(repeating: SIMD4<Float>(0, 0, 0.05, 0), count: 1000)
firstDraw[999] = SIMD4(0.25, 0.25, 0.75, 0.25)
overlayLines.value = firstDraw
try execute(overlay)
let firstOutput = try require(outputImage.value, "Overlay failed to encode 1,000 segments")
let secondOverlay = try makeNode("M-LSD Overlay")
let secondImage: NodePort<FabricImage> = secondOverlay.port(named: "inputImage")
let secondLines: NodePort<ContiguousArray<SIMD4<Float>>> = secondOverlay.port(named: "inputSegments")
let secondOutput: NodePort<FabricImage> = secondOverlay.port(named: "outputImage")
var secondDraw = firstDraw
secondDraw[999] = SIMD4(0.25, 0.75, 0.75, 0.75)
secondImage.value = sourceImage
secondLines.value = secondDraw
try execute(secondOverlay)
let secondResult = try require(secondOutput.value, "Second overlay failed to encode 1,000 segments")
try expect(firstOutput.texture.pixelFormat == .rgba16Float && secondResult.texture.pixelFormat == .rgba16Float,
           "Overlay changed output format")
let firstPixels = try copyPixels(from: firstOutput.texture)
let secondPixels = try copyPixels(from: secondResult.texture)

secondLines.value = []
try execute(secondOverlay)
try expect(secondOutput.value === sourceImage, "Empty overlay did not pass through the source image")
let scores: NodePort<ContiguousArray<Float>> = secondOverlay.port(named: "inputConfidences")
let minScore: ParameterPort<Float> = secondOverlay.port(named: "inputMinimumConfidence")
secondLines.value = secondDraw
scores.value = ContiguousArray(repeating: 0.1, count: secondDraw.count)
minScore.value = 0.2
try execute(secondOverlay)
try expect(secondOutput.value === sourceImage, "Filtered overlay did not pass through the source image")

commandBuffer.commit()
commandBuffer.waitUntilCompleted()
try expect(commandBuffer.status == .completed, "Overlay GPU execution failed")
try expect(greenChannel(firstPixels, x: 8, y: 11) > 0.5 && greenChannel(firstPixels, x: 8, y: 3) == 0,
           "First draw lost its final segment or read the second draw's upload")
try expect(greenChannel(secondPixels, x: 8, y: 3) > 0.5 && greenChannel(secondPixels, x: 8, y: 11) == 0,
           "Second draw lost its final segment or read the first draw's upload")

overlayLines.value = segments + [SIMD4<Float>(0, 0, 1, 1)]
do
{
    try execute(overlay)
    throw CapacityFailure.failed("Overlay accepted 1,001 lines")
}
catch is FabricError {}

print("M-LSD capacity fixture passed: Analyze default/range 1,000; Positions 2,000 ordered endpoints and clearing; independent 1,000-segment overlay draws and pass-through; both reject 1,001 lines")
