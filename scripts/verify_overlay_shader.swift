import Foundation
import Metal
import simd

enum SmokeFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let value): value
        }
    }
}

func require<Value>(_ value: Value?, _ message: String) throws -> Value {
    guard let value else { throw SmokeFailure.message(message) }
    return value
}

let bundlePath = try require(CommandLine.arguments.dropFirst().first, "Pass the installed .fabricplugin path")
let bundle = try require(Bundle(path: bundlePath), "Could not open plug-in bundle")
let device = try require(MTLCreateSystemDefaultDevice(), "No Metal device")
let library = try device.makeDefaultLibrary(bundle: bundle)
let copyFunction = try require(library.makeFunction(name: "mlsdCopyImage"), "Missing copy function")
let vertexFunction = try require(library.makeFunction(name: "mlsdLineVertex"), "Missing line vertex function")
let fragmentFunction = try require(library.makeFunction(name: "mlsdLineFragment"), "Missing line fragment function")
let copyPipeline = try device.makeComputePipelineState(function: copyFunction)
let pipelineDescriptor = MTLRenderPipelineDescriptor()
pipelineDescriptor.vertexFunction = vertexFunction
pipelineDescriptor.fragmentFunction = fragmentFunction
pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
let linePipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
let queue = try require(device.makeCommandQueue(), "No Metal command queue")

let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba16Float, width: 16, height: 16, mipmapped: false
)
textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
textureDescriptor.storageMode = .shared

func render(transform: simd_float4x4, expectedLineColumn: Int, expectedLineRow: Int) throws {
    let source = try require(device.makeTexture(descriptor: textureDescriptor), "No source texture")
    let destination = try require(device.makeTexture(descriptor: textureDescriptor), "No destination texture")
    var pixels = [UInt16](repeating: 0, count: 16 * 16 * 4)
    for pixelIndex in 0..<(16 * 16) {
        pixels[pixelIndex * 4 + 2] = Float16(0.25).bitPattern
        pixels[pixelIndex * 4 + 3] = Float16(1).bitPattern
    }
    try pixels.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else {
            throw SmokeFailure.message("No source pixel buffer")
        }
        source.replace(region: MTLRegionMake2D(0, 0, 16, 16), mipmapLevel: 0,
            withBytes: baseAddress, bytesPerRow: 16 * 4 * 2)
    }

    let commandBuffer = try require(queue.makeCommandBuffer(), "No command buffer")
    let copyEncoder = try require(commandBuffer.makeComputeCommandEncoder(), "No copy encoder")
    copyEncoder.setComputePipelineState(copyPipeline)
    copyEncoder.setTexture(source, index: 0)
    copyEncoder.setTexture(destination, index: 1)
    copyEncoder.dispatchThreads(MTLSize(width: 16, height: 16, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    copyEncoder.endEncoding()

    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = destination
    pass.colorAttachments[0].loadAction = .load
    pass.colorAttachments[0].storeAction = .store
    let encoder = try require(commandBuffer.makeRenderCommandEncoder(descriptor: pass), "No render encoder")
    encoder.setRenderPipelineState(linePipeline)
    var segment = SIMD4<Float>(0.25, 0.25, 0.75, 0.25)
    var storedTransform = transform
    var presentationSize = SIMD2<Float>(16, 16)
    var width: Float = 2
    var color = SIMD4<Float>(1, 0, 0, 1)
    encoder.setVertexBytes(&segment, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
    encoder.setVertexBytes(&storedTransform, length: MemoryLayout<simd_float4x4>.stride, index: 1)
    encoder.setVertexBytes(&presentationSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
    encoder.setVertexBytes(&width, length: MemoryLayout<Float>.stride, index: 3)
    encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    guard commandBuffer.status == .completed else {
        throw SmokeFailure.message("GPU command failed: \(String(describing: commandBuffer.error))")
    }

    try pixels.withUnsafeMutableBytes { bytes in
        guard let baseAddress = bytes.baseAddress else {
            throw SmokeFailure.message("No destination pixel buffer")
        }
        destination.getBytes(baseAddress, bytesPerRow: 16 * 4 * 2,
            from: MTLRegionMake2D(0, 0, 16, 16), mipmapLevel: 0)
    }
    let linePixel = (expectedLineRow * 16 + expectedLineColumn) * 4
    let backgroundPixel = (2 * 16 + 8) * 4
    guard Float16(bitPattern: pixels[linePixel]) > 0.5,
          Float16(bitPattern: pixels[linePixel + 2]) < 0.25,
          Float16(bitPattern: pixels[backgroundPixel]) < 0.01,
          abs(Float(Float16(bitPattern: pixels[backgroundPixel + 2])) - 0.25) < 0.01 else {
        throw SmokeFailure.message("Overlay pixels did not match the expected line/background positions")
    }
}

try render(transform: matrix_identity_float4x4, expectedLineColumn: 8, expectedLineRow: 12)
var verticalFlip = matrix_identity_float4x4
verticalFlip.columns.1.y = -1
verticalFlip.columns.3.y = 1
try render(transform: verticalFlip, expectedLineColumn: 8, expectedLineRow: 4)
var quarterTurn = matrix_identity_float4x4
quarterTurn.columns.0 = SIMD4<Float>(0, -1, 0, 0)
quarterTurn.columns.1 = SIMD4<Float>(1, 0, 0, 0)
quarterTurn.columns.3 = SIMD4<Float>(0, 1, 0, 1)
try render(transform: quarterTurn, expectedLineColumn: 12, expectedLineRow: 8)
print("M-LSD overlay Metal fixture passed: identity, vertical-flip, and quarter-turn orientation; background copy and line compositing")
