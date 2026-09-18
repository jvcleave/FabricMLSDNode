import Fabric
import Foundation
import Metal
import Satin
import simd

/// Renders normalized, bottom-left line segments over a Fabric image without running inference.
public final class MLSDStructuralLineOverlayNode: Node
{
    public override class var name: String { "M-LSD Overlay" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Composite) }
    public override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    public override class var nodeTimeMode: Node.TimeMode { .None }
    public override class var nodeDescription: String
    {
        "Draws independent structural line segments over an image in presentation coordinates."
    }

    public override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet,
                description: "Background image in Fabric presentation orientation")),
            ("inputSegments", NodePort<ContiguousArray<SIMD4<Float>>>(name: "Lines", kind: .Inlet,
                description: "Normalized bottom-left [startX, startY, endX, endY] segments")),
            ("inputConfidences", NodePort<ContiguousArray<Float>>(name: "Scores", kind: .Inlet,
                description: "Optional confidence values aligned with Lines")),
            ("inputColor", ParameterPort(parameter: Float4Parameter(
                "Color", simd_float4(0, 1, 1, 1), .colorpicker,
                "Overlay line color (RGBA)"))),
            ("inputWidth", ParameterPort(parameter: FloatParameter(
                "Width", 2, 0.5, 32, .slider,
                "Line width in presentation pixels"))),
            ("inputOpacity", ParameterPort(parameter: FloatParameter(
                "Opacity", 1, 0, 1, .slider,
                "Overlay opacity multiplied by line color alpha"))),
            ("inputMinimumConfidence", ParameterPort(parameter: FloatParameter(
                "Min Score", 0, 0, 1, .slider,
                "Only draw lines meeting this confidence; requires aligned confidences"))),
            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet,
                description: "Source image with anti-aliased structural lines")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputSegments: NodePort<ContiguousArray<SIMD4<Float>>> { port(named: "inputSegments") }
    public var inputConfidences: NodePort<ContiguousArray<Float>> { port(named: "inputConfidences") }
    public var inputColor: ParameterPort<simd_float4> { port(named: "inputColor") }
    public var inputWidth: ParameterPort<Float> { port(named: "inputWidth") }
    public var inputOpacity: ParameterPort<Float> { port(named: "inputOpacity") }
    public var inputMinimumConfidence: ParameterPort<Float> { port(named: "inputMinimumConfidence") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    private var copyPipeline: MTLComputePipelineState?
    private var linePipeline: MTLRenderPipelineState?
    private var pipelineError: String?

    public required init(context: Context)
    {
        super.init(context: context)
        self.preparePipelines()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.preparePipelines()
    }

    private func preparePipelines()
    {
        do
        {
            let library = try self.context.device.makeDefaultLibrary(bundle: Bundle(for: Self.self))
            guard let copyFunction = library.makeFunction(name: "mlsdCopyImage"),
                  let vertexFunction = library.makeFunction(name: "mlsdLineVertex"),
                  let fragmentFunction = library.makeFunction(name: "mlsdLineFragment")
            else
            {
                self.pipelineError = "The M-LSD overlay Metal functions are missing from the plug-in bundle."
                return
            }

            self.copyPipeline = try self.context.device.makeComputePipelineState(function: copyFunction)

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "M-LSD Structural Line Overlay"
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            self.linePipeline = try self.context.device.makeRenderPipelineState(descriptor: descriptor)
            self.pipelineError = nil
        }
        catch
        {
            self.pipelineError = "The M-LSD overlay Metal pipeline could not be created: \(error)"
        }
    }

    public override func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        guard let sourceImage = self.inputImage.value else
        {
            self.outputImage.send(nil)
            return
        }

        let segments = self.inputSegments.value ?? []
        let confidences = self.inputConfidences.value
        try self.validate(segments: segments, confidences: confidences)

        let minimumConfidence = min(max(self.inputMinimumConfidence.value ?? 0, 0), 1)
        let visibleSegments = ContiguousArray(segments.enumerated().compactMap { index, segment in
            (confidences?[index] ?? 1) >= minimumConfidence ? segment : nil
        })
        let opacity = min(max(self.inputOpacity.value ?? 1, 0), 1)
        let lineColor = self.inputColor.value ?? simd_float4(0, 1, 1, 1)
        guard visibleSegments.isEmpty == false, opacity > 0, lineColor.w > 0 else
        {
            self.outputImage.send(sourceImage)
            return
        }

        guard let copyPipeline, let linePipeline else
        {
            throw Self.overlayError(self.pipelineError ?? "The M-LSD overlay Metal pipeline is unavailable.")
        }

        let width = Float(sourceImage.presentationSize.width)
        let height = Float(sourceImage.presentationSize.height)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else
        {
            throw Self.overlayError("The image has invalid M-LSD presentation dimensions.")
        }

        let output = try renderer.newImage(
            withWidth: sourceImage.texture.width,
            height: sourceImage.texture.height,
            format: .rgba16Float
        )
        output.textureTransform = sourceImage.textureTransform
        output.texture.label = "M-LSD Structural Line Overlay"
        try self.encodeBackgroundCopy(
            source: sourceImage.texture,
            destination: output.texture,
            pipeline: copyPipeline,
            commandBuffer: commandBuffer
        )
        try self.encodeLines(
            segments: visibleSegments,
            source: sourceImage,
            destination: output.texture,
            presentationSize: simd_float2(width, height),
            color: simd_float4(lineColor.x, lineColor.y, lineColor.z,
                min(max(lineColor.w, 0), 1) * opacity),
            width: min(max(self.inputWidth.value ?? 2, 0.5), 32),
            pipeline: linePipeline,
            commandBuffer: commandBuffer
        )
        self.outputImage.send(output)
    }

    private func validate(
        segments: ContiguousArray<SIMD4<Float>>,
        confidences: ContiguousArray<Float>?
    ) throws
    {
        guard segments.count <= 200 else
        {
            throw Self.overlayError("M-LSD overlay accepts at most 200 line segments.")
        }
        if let confidences, confidences.count != segments.count
        {
            throw Self.overlayError("M-LSD overlay confidence count must match the line segment count.")
        }
        for segment in segments
        {
            guard (0...1).contains(segment.x), (0...1).contains(segment.y),
                  (0...1).contains(segment.z), (0...1).contains(segment.w) else
            {
                throw Self.overlayError("M-LSD overlay endpoints must be finite normalized coordinates.")
            }
        }
        for confidence in confidences ?? []
        {
            guard (0...1).contains(confidence) else
            {
                throw Self.overlayError("M-LSD overlay confidences must be finite values from zero to one.")
            }
        }
    }

    private func encodeBackgroundCopy(
        source: MTLTexture,
        destination: MTLTexture,
        pipeline: MTLComputePipelineState,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw Self.overlayError("Could not create the M-LSD background-copy encoder.")
        }
        defer { encoder.endEncoding() }
        encoder.label = "M-LSD Background Copy"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        let threadSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: destination.width, height: destination.height, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadSize)
    }

    private func encodeLines(
        segments: ContiguousArray<SIMD4<Float>>,
        source: FabricImage,
        destination: MTLTexture,
        presentationSize: simd_float2,
        color: simd_float4,
        width: Float,
        pipeline: MTLRenderPipelineState,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = destination
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else
        {
            throw Self.overlayError("Could not create the M-LSD line render encoder.")
        }
        defer { encoder.endEncoding() }
        encoder.label = "M-LSD Structural Lines"
        encoder.setRenderPipelineState(pipeline)
        var textureTransform = source.textureTransform
        var size = presentationSize
        var lineWidth = width
        var lineColor = color
        segments.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            encoder.setVertexBytes(baseAddress, length: buffer.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setVertexBytes(&textureTransform, length: MemoryLayout<simd_float4x4>.stride, index: 1)
            encoder.setVertexBytes(&size, length: MemoryLayout<simd_float2>.stride, index: 2)
            encoder.setVertexBytes(&lineWidth, length: MemoryLayout<Float>.stride, index: 3)
            encoder.setFragmentBytes(&lineColor, length: MemoryLayout<simd_float4>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                instanceCount: buffer.count)
        }
    }

    private static func overlayError(_ message: String) -> FabricError
    {
        FabricError(.execution(.gpu), severity: .recoverable, message: message)
    }
}
