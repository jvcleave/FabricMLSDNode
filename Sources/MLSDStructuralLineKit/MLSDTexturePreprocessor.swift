import CoreVideo
import Foundation
import Metal

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

    func prepare(texture sourceTexture: MTLTexture, commandQueue: MTLCommandQueue) throws -> CVPixelBuffer
    {
        guard sourceTexture.width > 0, sourceTexture.height > 0 else
        {
            throw MLSDStructuralLineError.invalidSourceTexture
        }
        guard sourceTexture.device.registryID == self.device.registryID,
              commandQueue.device.registryID == self.device.registryID
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

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else
        {
            throw MLSDStructuralLineError.commandEncodingFailed
        }
        commandBuffer.label = "M-LSD texture preprocessing"
        encoder.label = "Resize source texture to M-LSD 512x512 RGB input"
        encoder.setComputePipelineState(self.pipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(destinationTexture, index: 1)
        let width = self.pipeline.threadExecutionWidth
        let height = max(1, min(8, self.pipeline.maxTotalThreadsPerThreadgroup / width))
        encoder.dispatchThreads(
            MTLSize(width: 512, height: 512, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
        encoder.endEncoding()
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
}
