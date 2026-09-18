import CoreML
import CoreVideo
import Metal
import simd

struct MLSDBackboneOutput
{
    let centerPoints: MLMultiArray
    let centerScores: MLMultiArray
    let displacementMap: MLMultiArray

    init(provider: MLFeatureProvider) throws
    {
        func array(named name: String) throws -> MLMultiArray
        {
            guard let array = provider.featureValue(for: name)?.multiArrayValue else
            {
                throw MLSDStructuralLineError.missingPredictionOutput(name)
            }
            try MLSDModelMetadata.validate(array: array, named: name)
            return array
        }

        self.centerPoints = try array(named: "center_points")
        self.centerScores = try array(named: "center_scores")
        self.displacementMap = try array(named: "displacement_map")
    }
}

final class MLSDBackbone
{
    private let device: MTLDevice
    private let model: MLModel
    private let preprocessor: MLSDTexturePreprocessor
    private let predictionLock = NSLock()

    init(
        device: MTLDevice,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws
    {
        let modelURL = try MLSDModelResource.modelURL()
        let compiledURL = try MLModel.compileModel(at: modelURL)
        let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        try MLSDModelMetadata.validate(modelDescription: model.modelDescription)

        self.device = device
        self.model = model
        self.preprocessor = try MLSDTexturePreprocessor(device: device)
    }

    func warmUp(commandQueue: MTLCommandQueue) throws
    {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = self.device.makeTexture(descriptor: descriptor) else
        {
            throw MLSDStructuralLineError.sourceTextureCreationFailed
        }
        let black: [UInt8] = [0, 0, 0, 255]
        black.withUnsafeBytes
        { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4
            )
        }
        _ = try self.predict(
            texture: texture,
            sourceSize: StructuralLineImageSize(width: 1, height: 1),
            textureTransform: matrix_identity_float4x4,
            commandQueue: commandQueue
        )
    }

    func predict(
        texture: MTLTexture,
        sourceSize: StructuralLineImageSize,
        textureTransform: simd_float4x4,
        commandQueue: MTLCommandQueue
    ) throws -> MLSDBackboneOutput
    {
        let pixelBuffer = try self.preprocessor.prepare(
            texture: texture,
            sourceSize: sourceSize,
            textureTransform: textureTransform,
            commandQueue: commandQueue
        )
        return try self.predict(pixelBuffer: pixelBuffer)
    }

    func encodePreprocessing(
        texture: MTLTexture,
        sourceSize: StructuralLineImageSize,
        textureTransform: simd_float4x4,
        commandBuffer: MTLCommandBuffer
    ) throws -> CVPixelBuffer
    {
        try self.preprocessor.encode(
            texture: texture,
            sourceSize: sourceSize,
            textureTransform: textureTransform,
            commandBuffer: commandBuffer
        )
    }

    func predict(pixelBuffer: CVPixelBuffer) throws -> MLSDBackboneOutput
    {
        self.predictionLock.lock()
        defer { self.predictionLock.unlock() }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            MLSDModelMetadata.inputName: MLFeatureValue(pixelBuffer: pixelBuffer),
        ])
        return try MLSDBackboneOutput(provider: self.model.prediction(from: input))
    }
}
