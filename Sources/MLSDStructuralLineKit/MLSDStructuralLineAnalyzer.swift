import CoreML
import Metal

/// End-to-end native M-LSD 512-tiny analysis from a source Metal texture to a
/// bounded set of normalized, independent line segments.
public final class MLSDStructuralLineAnalyzer
{
    private let backbone: MLSDBackbone
    private let decoder = MLSDDecoder()

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
        commandQueue: MTLCommandQueue,
        decoderConfiguration: MLSDDecoderConfiguration = .standard
    ) throws -> StructuralLineFrame
    {
        let output = try self.backbone.predict(
            texture: texture,
            commandQueue: commandQueue
        )
        return try self.decoder.decode(
            output,
            sourceSize: sourceSize,
            configuration: decoderConfiguration
        )
    }
}
