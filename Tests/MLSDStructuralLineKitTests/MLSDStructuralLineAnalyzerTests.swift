import CoreML
import Metal
import MetalKit
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
    func reproducesCityReference() throws
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
        let texture = try MTKTextureLoader(device: device).newTexture(
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
        let gpuFrame = try gpuAnalyzer.analyze(
            texture: texture,
            sourceSize: StructuralLineImageSize(width: 1_280, height: 720),
            commandQueue: commandQueue
        )
        #expect(gpuFrame.edges.count >= 40)
        #expect(gpuFrame.edges.count <= 60)
        #expect(gpuFrame.junctions.count == gpuFrame.edges.count * 2)
        #expect(abs(gpuFrame.junctions[0].position.x - firstStart.x) < 0.01)
        #expect(abs(gpuFrame.junctions[0].position.y - firstStart.y) < 0.01)
    }

    private func set(_ array: MLMultiArray, _ indices: [Int], _ value: Float)
    {
        array[indices.map(NSNumber.init(value:))] = NSNumber(value: value)
    }
}
