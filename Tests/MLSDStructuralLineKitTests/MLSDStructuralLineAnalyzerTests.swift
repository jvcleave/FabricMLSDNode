import CoreML
import CoreVideo
import Metal
import MetalKit
import simd
import Testing
@testable import MLSDStructuralLineKit

@Suite("M-LSD structural-line analyzer", .serialized)
struct MLSDStructuralLineAnalyzerTests
{
    @Test("Bundled Core ML artifact and license match the pinned upstream files")
    func bundledArtifactIdentity() throws
    {
        try MLSDModelResource.validatePinnedArtifact()
    }

    @Test("Decoder preserves independent segments and normalized coordinates")
    func decodesIndependentSegments() throws
    {
        let points = try MLMultiArray(shape: [1, 200, 2], dataType: .float32)
        let scores = try MLMultiArray(shape: [1, 200], dataType: .float32)
        let displacements = try MLMultiArray(
            shape: [1, 256, 256, 4],
            dataType: .float32
        )
        self.set(points, [0, 0, 0], 100)
        self.set(points, [0, 0, 1], 50)
        self.set(scores, [0, 0], 0.9)
        self.set(displacements, [0, 100, 50, 0], -30)
        self.set(displacements, [0, 100, 50, 1], 0)
        self.set(displacements, [0, 100, 50, 2], 30)
        self.set(displacements, [0, 100, 50, 3], 0)

        let frame = try MLSDDecoder().decode(
            centerPoints: points,
            centerScores: scores,
            displacementMap: displacements,
            sourceSize: StructuralLineImageSize(width: 1_280, height: 720)
        )

        #expect(frame.junctions.count == 2)
        #expect(frame.edges.count == 1)
        #expect(frame.edges[0].startJunctionIndex == 0)
        #expect(frame.edges[0].endJunctionIndex == 1)
        #expect(frame.junctions[0].position == SIMD2(0.078125, 0.609375))
        #expect(frame.junctions[1].position == SIMD2(0.3125, 0.609375))
        #expect(frame.edges[0].confidence == 0.9)
    }

    @Test("CPU model and Swift decoder reproduce the pinned city reference")
    func reproducesCityReference() async throws
    {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let commandQueue = try #require(device.makeCommandQueue())
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let analyzer = try MLSDStructuralLineAnalyzer(
            device: device,
            modelConfiguration: configuration
        )

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot
            .appendingPathComponent("ResearchFixtures/MLSD/Sources/city-28s.png")
        let texture = try await MTKTextureLoader(device: device).newTexture(
            URL: sourceURL,
            options: [
                .SRGB: false,
                .origin: MTKTextureLoader.Origin.topLeft,
            ]
        )

        let start = ContinuousClock.now
        let frame = try analyzer.analyze(
            texture: texture,
            sourceSize: StructuralLineImageSize(width: 1_280, height: 720),
            commandQueue: commandQueue
        )
        print("M-LSD CPU city analysis: \(start.duration(to: .now))")

        #expect(frame.edges.count == 46)
        #expect(frame.junctions.count == 92)
        #expect(abs(frame.edges[0].confidence - 0.68369615) < 0.00001)
        let firstStart = frame.junctions[0].position
        let firstEnd = frame.junctions[1].position
        #expect(abs(firstStart.x - 490.206225 / 1_280) < 0.0001)
        #expect(abs(firstStart.y - (1 - 217.775921 / 720)) < 0.0001)
        #expect(abs(firstEnd.x - 495.932437 / 1_280) < 0.0001)
        #expect(abs(firstEnd.y - (1 - 467.799193 / 720)) < 0.0001)

        let gpuConfiguration = MLModelConfiguration()
        gpuConfiguration.computeUnits = .cpuAndGPU
        let gpuAnalyzer = try MLSDStructuralLineAnalyzer(
            device: device,
            modelConfiguration: gpuConfiguration
        )
        let gpuCommandBuffer = try #require(commandQueue.makeCommandBuffer())
        let gpuFrame: StructuralLineFrame = try await withCheckedThrowingContinuation
        { continuation in
            do
            {
                try gpuAnalyzer.analyzeAfterCommandBufferCompletes(
                    texture: texture,
                    sourceSize: StructuralLineImageSize(width: 1_280, height: 720),
                    commandBuffer: gpuCommandBuffer
                )
                { result in
                    continuation.resume(with: result)
                }
                #expect(gpuCommandBuffer.status == .notEnqueued)
                gpuCommandBuffer.commit()
            }
            catch
            {
                continuation.resume(throwing: error)
            }
        }
        #expect(gpuFrame.edges.count >= 40)
        #expect(gpuFrame.edges.count <= 60)
        #expect(gpuFrame.junctions.count == gpuFrame.edges.count * 2)
        #expect(abs(gpuFrame.junctions[0].position.x - firstStart.x) < 0.01)
        #expect(abs(gpuFrame.junctions[0].position.y - firstStart.y) < 0.01)
    }

    @Test("Preprocessing honors presentation orientation on a caller-owned command buffer")
    func preprocessesPresentationOrientation() throws
    {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let commandQueue = try #require(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let pixels: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 255,
        ]
        try pixels.withUnsafeBytes
        { bytes in
            let baseAddress = try #require(bytes.baseAddress)
            texture.replace(
                region: MTLRegionMake2D(0, 0, 2, 2),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: 8
            )
        }

        let preprocessor = try MLSDTexturePreprocessor(device: device)
        let commandBuffer = try #require(commandQueue.makeCommandBuffer())
        let verticalFlip = simd_float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, -1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 1, 0, 1)
        )
        let pixelBuffer = try preprocessor.encode(
            texture: texture,
            sourceSize: StructuralLineImageSize(width: 2, height: 2),
            textureTransform: verticalFlip,
            commandBuffer: commandBuffer
        )

        #expect(commandBuffer.status == .notEnqueued)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed)

        let topLeft = try self.rgbPixel(pixelBuffer, x: 64, y: 64)
        let bottomLeft = try self.rgbPixel(pixelBuffer, x: 64, y: 448)
        #expect(topLeft == SIMD3<UInt8>(0, 0, 255))
        #expect(bottomLeft == SIMD3<UInt8>(255, 0, 0))
    }

    private func set(_ array: MLMultiArray, _ indices: [Int], _ value: Float)
    {
        array[indices.map(NSNumber.init(value:))] = NSNumber(value: value)
    }

    private func rgbPixel(
        _ pixelBuffer: CVPixelBuffer,
        x: Int,
        y: Int
    ) throws -> SIMD3<UInt8>
    {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let baseAddress = try #require(CVPixelBufferGetBaseAddress(pixelBuffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelAddress = baseAddress
            .advanced(by: y * bytesPerRow + x * 4)
            .assumingMemoryBound(to: UInt8.self)
        return SIMD3(pixelAddress[2], pixelAddress[1], pixelAddress[0])
    }
}
