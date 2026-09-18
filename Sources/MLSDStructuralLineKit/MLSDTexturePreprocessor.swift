import CoreVideo
import Foundation
import Metal
import simd

final class MLSDTexturePreprocessor
{
    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let pixelBufferPool: CVPixelBufferPool
    private let textureCache: CVMetalTextureCache

    init(device: MTLDevice) throws
    {
        self.device = device

        guard let shaderURL = Bundle.module.url(
            forResource: "MLSDTexturePreprocess",
            withExtension: "metal",
            subdirectory: "Compute"
        ) else
        {
            throw MLSDStructuralLineError.missingPreprocessingResource
        }
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "resizeTextureForMLSD") else
        {
            throw MLSDStructuralLineError.missingPreprocessingFunction
        }
        self.pipeline = try device.makeComputePipelineState(function: function)

        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 2,
        ]
        let pixelAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: MLSDModelMetadata.inputWidth,
            kCVPixelBufferHeightKey: MLSDModelMetadata.inputHeight,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var pool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelAttributes as CFDictionary,
            &pool
        )
        guard poolStatus == kCVReturnSuccess, let pool else
        {
            throw MLSDStructuralLineError.pixelBufferPoolCreationFailed(poolStatus)
        }
        self.pixelBufferPool = pool

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        guard cacheStatus == kCVReturnSuccess, let cache else
        {
            throw MLSDStructuralLineError.textureCacheCreationFailed(cacheStatus)
        }
        self.textureCache = cache
    }

    func prepare(
        texture sourceTexture: MTLTexture,
        sourceSize: StructuralLineImageSize,
        textureTransform: simd_float4x4,
        commandQueue: MTLCommandQueue
    ) throws -> CVPixelBuffer
    {
        guard commandQueue.device.registryID == self.device.registryID else
        {
            throw MLSDStructuralLineError.deviceMismatch
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else
        {
            throw MLSDStructuralLineError.commandEncodingFailed
        }
        commandBuffer.label = "M-LSD texture preprocessing"
        let pixelBuffer = try self.encode(
            texture: sourceTexture,
            sourceSize: sourceSize,
            textureTransform: textureTransform,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else
        {
            throw MLSDStructuralLineError.gpuExecutionFailed(
                commandBuffer.error?.localizedDescription
            )
        }
        return pixelBuffer
    }

    /// Encodes preprocessing after upstream work already present in the
    /// caller's command buffer. The caller owns submission and synchronization.
    func encode(
        texture sourceTexture: MTLTexture,
        sourceSize: StructuralLineImageSize,
        textureTransform: simd_float4x4,
        commandBuffer: MTLCommandBuffer
    ) throws -> CVPixelBuffer
    {
        guard sourceTexture.width > 0, sourceTexture.height > 0 else
        {
            throw MLSDStructuralLineError.invalidSourceTexture
        }
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              sourceSize.width <= Int(UInt32.max),
              sourceSize.height <= Int(UInt32.max)
        else
        {
            throw StructuralLineValidationError.invalidSourceSize
        }
        guard sourceTexture.device.registryID == self.device.registryID,
              commandBuffer.device.registryID == self.device.registryID
        else
        {
            throw MLSDStructuralLineError.deviceMismatch
        }

        var pixelBuffer: CVPixelBuffer?
        let bufferStatus = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            self.pixelBufferPool,
            &pixelBuffer
        )
        guard bufferStatus == kCVReturnSuccess, let pixelBuffer else
        {
            throw MLSDStructuralLineError.pixelBufferCreationFailed(bufferStatus)
        }

        let textureAttributes: [CFString: Any] = [
            kCVMetalTextureUsage: NSNumber(value: MTLTextureUsage.shaderWrite.rawValue),
        ]
        var metalTexture: CVMetalTexture?
        let textureStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            self.textureCache,
            pixelBuffer,
            textureAttributes as CFDictionary,
            .bgra8Unorm,
            MLSDModelMetadata.inputWidth,
            MLSDModelMetadata.inputHeight,
            0,
            &metalTexture
        )
        guard textureStatus == kCVReturnSuccess,
              let metalTexture,
              let destinationTexture = CVMetalTextureGetTexture(metalTexture)
        else
        {
            throw MLSDStructuralLineError.destinationTextureCreationFailed(textureStatus)
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw MLSDStructuralLineError.commandEncodingFailed
        }
        encoder.label = "Orient and resize source texture to M-LSD 512x512 RGB input"
        encoder.setComputePipelineState(self.pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(destinationTexture, index: 1)
        var transform = textureTransform
        var presentationSize = SIMD2<UInt32>(
            UInt32(sourceSize.width),
            UInt32(sourceSize.height)
        )
        encoder.setBytes(
            &transform,
            length: MemoryLayout<simd_float4x4>.stride,
            index: 0
        )
        encoder.setBytes(
            &presentationSize,
            length: MemoryLayout<SIMD2<UInt32>>.stride,
            index: 1
        )
        let width = self.pipeline.threadExecutionWidth
        let height = max(1, min(8, self.pipeline.maxTotalThreadsPerThreadgroup / width))
        encoder.dispatchThreads(
            MTLSize(width: 512, height: 512, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
        encoder.endEncoding()
        return pixelBuffer
    }
}
