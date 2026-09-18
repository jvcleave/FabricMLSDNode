import CoreML
import Metal
import simd

/// End-to-end native M-LSD 512-tiny analysis from a source Metal texture to a
/// bounded set of normalized, independent line segments.
public final class MLSDStructuralLineAnalyzer
{
    private let backbone: MLSDBackbone
    private let decoder = MLSDDecoder()
    private let predictionQueue = DispatchQueue(
        label: "com.jvclabs.MLSDStructuralLineKit.prediction",
        qos: .userInitiated
    )

    public init(
        device: MTLDevice,
        modelConfiguration: MLModelConfiguration = MLModelConfiguration()
    ) throws
    {
        self.backbone = try MLSDBackbone(
            device: device,
            configuration: modelConfiguration
        )
    }

    public func warmUp(commandQueue: MTLCommandQueue) throws
    {
        try self.backbone.warmUp(commandQueue: commandQueue)
    }

    public func analyze(
        texture: MTLTexture,
        sourceSize: StructuralLineImageSize,
        textureTransform: simd_float4x4 = matrix_identity_float4x4,
        commandQueue: MTLCommandQueue,
        decoderConfiguration: MLSDDecoderConfiguration = .standard
    ) throws -> StructuralLineFrame
    {
        let output = try self.backbone.predict(
            texture: texture,
            sourceSize: sourceSize,
            textureTransform: textureTransform,
            commandQueue: commandQueue
        )
        return try self.decoder.decode(
            output,
            sourceSize: sourceSize,
            configuration: decoderConfiguration
        )
    }

    /// Encodes texture preprocessing into a caller-owned command buffer, then
    /// performs Core ML prediction and decoding after its GPU work completes.
    /// The command buffer is neither committed nor waited on by this method.
    public func analyzeAfterCommandBufferCompletes(
        texture: MTLTexture,
        sourceSize: StructuralLineImageSize,
        textureTransform: simd_float4x4 = matrix_identity_float4x4,
        commandBuffer: MTLCommandBuffer,
        decoderConfiguration: MLSDDecoderConfiguration = .standard,
        completion: @escaping (Result<StructuralLineFrame, any Error>) -> Void
    ) throws
    {
        let pixelBuffer = try self.backbone.encodePreprocessing(
            texture: texture,
            sourceSize: sourceSize,
            textureTransform: textureTransform,
            commandBuffer: commandBuffer
        )
        commandBuffer.addCompletedHandler
        { [backbone, decoder, predictionQueue] completedCommandBuffer in
            guard completedCommandBuffer.status == .completed else
            {
                let message = completedCommandBuffer.error?.localizedDescription
                predictionQueue.async
                {
                    completion(.failure(MLSDStructuralLineError.gpuExecutionFailed(message)))
                }
                return
            }

            predictionQueue.async
            {
                do
                {
                    let output = try backbone.predict(pixelBuffer: pixelBuffer)
                    let frame = try decoder.decode(
                        output,
                        sourceSize: sourceSize,
                        configuration: decoderConfiguration
                    )
                    completion(.success(frame))
                }
                catch
                {
                    completion(.failure(error))
                }
            }
        }
    }
}
