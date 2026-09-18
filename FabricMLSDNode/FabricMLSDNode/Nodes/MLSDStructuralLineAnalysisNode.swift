import CoreML
import Fabric
import Foundation
import MLSDStructuralLineKit
import Metal
import Satin
import simd

public final class MLSDStructuralLineAnalysisNode: Node
{
    public override class var name: String { "M-LSD Analyze" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    public override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    public override class var nodeTimeMode: Node.TimeMode { .None }
    public override class var nodeDescription: String
    {
        "Detects independent scored line segments in an image using M-LSD 512-tiny."
    }

    public override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) +
        [
            (
                "inputImage",
                NodePort<FabricImage>(
                    name: "Image",
                    kind: .Inlet,
                    description: "Image to analyze in its Fabric presentation orientation"
                )
            ),
            (
                "inputMinimumConfidence",
                ParameterPort(
                    parameter: FloatParameter(
                        "Min Score",
                        0.05,
                        0,
                        1,
                        .slider,
                        "Minimum model confidence required to output a line"
                    )
                )
            ),
            (
                "inputMaximumLines",
                ParameterPort(
                    parameter: IntParameter(
                        "Max Lines",
                        200,
                        1,
                        200,
                        .inputfield,
                        "Maximum number of highest-confidence lines to output"
                    )
                )
            ),
            (
                "inputAnalysisInterval",
                ParameterPort(
                    parameter: IntParameter(
                        "Interval",
                        1,
                        1,
                        120,
                        .inputfield,
                        "Analyze every Nth changed input image; parameter changes analyze immediately"
                    )
                )
            ),
            (
                "outputSegments",
                NodePort<ContiguousArray<SIMD4<Float>>>(
                    name: "Lines",
                    kind: .Outlet,
                    description: "Normalized bottom-left [startX, startY, endX, endY] values"
                )
            ),
            (
                "outputConfidences",
                NodePort<ContiguousArray<Float>>(
                    name: "Scores",
                    kind: .Outlet,
                    description: "Confidence values index-aligned with Lines"
                )
            ),
            (
                "outputLineCount",
                NodePort<Int>(
                    name: "Count",
                    kind: .Outlet,
                    description: "Number of lines in the current completed analysis"
                )
            ),
            (
                "outputSourceSize",
                NodePort<SIMD2<Float>>(
                    name: "Size",
                    kind: .Outlet,
                    description: "Presentation width and height of the analyzed image"
                )
            ),
            (
                "outputAnalyzedImage",
                NodePort<FabricImage>(
                    name: "Frame",
                    kind: .Outlet,
                    description: "The image paired with the completed Lines result"
                )
            ),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputMinimumConfidence: ParameterPort<Float> { port(named: "inputMinimumConfidence") }
    public var inputMaximumLines: ParameterPort<Int> { port(named: "inputMaximumLines") }
    public var inputAnalysisInterval: ParameterPort<Int> { port(named: "inputAnalysisInterval") }
    public var outputSegments: NodePort<ContiguousArray<SIMD4<Float>>> { port(named: "outputSegments") }
    public var outputConfidences: NodePort<ContiguousArray<Float>> { port(named: "outputConfidences") }
    public var outputLineCount: NodePort<Int> { port(named: "outputLineCount") }
    public var outputSourceSize: NodePort<SIMD2<Float>> { port(named: "outputSourceSize") }
    public var outputAnalyzedImage: NodePort<FabricImage> { port(named: "outputAnalyzedImage") }

    private struct AnalysisRequest
    {
        let identifier: UInt64
        let image: FabricImage
        let sourceSize: StructuralLineImageSize
        let textureTransform: simd_float4x4
        let decoderConfiguration: MLSDDecoderConfiguration
    }

    private enum CompletedAnalysis
    {
        case success(requestIdentifier: UInt64, frame: StructuralLineFrame, image: FabricImage)
        case failure(requestIdentifier: UInt64, message: String)
    }

    private var analyzer: MLSDStructuralLineAnalyzer?
    private var inferenceIsActive = false
    private var latestPendingRequest: AnalysisRequest?
    private var completedAnalysis: CompletedAnalysis?
    private var lifecycleGeneration: UInt64 = 0
    private var nextRequestIdentifier: UInt64 = 0
    private var minimumAcceptedRequestIdentifier: UInt64 = 0
    private var changedImageCount = 0
    private var hasRequestedAnalysis = false

    public override func startExecution(renderer: GraphRenderer) throws
    {
        try super.startExecution(renderer: renderer)
        self.lifecycleGeneration &+= 1
        self.resetSchedulingState()

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        self.analyzer = try MLSDStructuralLineAnalyzer(
            device: self.context.device,
            modelConfiguration: configuration
        )
    }

    public override func stopExecution(renderer: GraphRenderer) throws
    {
        self.lifecycleGeneration &+= 1
        self.minimumAcceptedRequestIdentifier = self.nextRequestIdentifier
        self.resetSchedulingState()
        self.analyzer = nil
        try super.stopExecution(renderer: renderer)
    }

    public override func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        if self.inputImage.valueDidChange, self.inputImage.value == nil
        {
            self.nextRequestIdentifier &+= 1
            self.minimumAcceptedRequestIdentifier = self.nextRequestIdentifier
            self.latestPendingRequest = nil
            self.hasRequestedAnalysis = false
            self.changedImageCount = 0
        }

        let completedErrorMessage = self.publishCompletedAnalysisIfAvailable()
        let decoderParametersChanged = self.inputMinimumConfidence.valueDidChange
            || self.inputMaximumLines.valueDidChange
        let intervalChanged = self.inputAnalysisInterval.valueDidChange

        if self.inputImage.value == nil
        {
            self.publishEmptyState()
        }
        else if let image = self.inputImage.value
        {
            var shouldRequestAnalysis = decoderParametersChanged || intervalChanged

            if self.inputImage.valueDidChange
            {
                self.changedImageCount &+= 1
                let interval = min(max(self.inputAnalysisInterval.value ?? 1, 1), 120)
                let changedImageIsEligible = self.hasRequestedAnalysis == false
                    || (self.changedImageCount - 1).isMultiple(of: interval)
                shouldRequestAnalysis = shouldRequestAnalysis || changedImageIsEligible
            }
            else if self.hasRequestedAnalysis == false
            {
                shouldRequestAnalysis = true
            }

            if shouldRequestAnalysis
            {
                self.latestPendingRequest = try self.makeRequest(image: image)
                self.hasRequestedAnalysis = true
            }
        }

        if self.inferenceIsActive == false, let request = self.latestPendingRequest
        {
            self.latestPendingRequest = nil
            try self.beginAnalysis(request: request, commandBuffer: commandBuffer)
        }

        if let completedErrorMessage
        {
            throw FabricError(
                .execution(.failed),
                severity: .recoverable,
                message: completedErrorMessage
            )
        }
    }

    private func makeRequest(image: FabricImage) throws -> AnalysisRequest
    {
        guard image.presentationSize.width.isFinite,
              image.presentationSize.height.isFinite,
              image.presentationSize.width > 0,
              image.presentationSize.height > 0,
              image.presentationSize.width <= CGFloat(UInt32.max),
              image.presentationSize.height <= CGFloat(UInt32.max)
        else
        {
            throw FabricError(
                .execution(.failed),
                severity: .recoverable,
                message: "The image has invalid M-LSD presentation dimensions."
            )
        }

        self.nextRequestIdentifier &+= 1
        let presentationWidth = max(1, Int(image.presentationSize.width.rounded()))
        let presentationHeight = max(1, Int(image.presentationSize.height.rounded()))
        let minimumConfidence = min(max(self.inputMinimumConfidence.value ?? 0.05, 0), 1)
        let maximumLines = min(max(self.inputMaximumLines.value ?? 200, 1), 200)
        let decoderConfiguration = try MLSDDecoderConfiguration(
            minimumConfidence: minimumConfidence,
            minimumMapLength: 20,
            maximumEdges: maximumLines
        )
        return AnalysisRequest(
            identifier: self.nextRequestIdentifier,
            image: image,
            sourceSize: StructuralLineImageSize(
                width: presentationWidth,
                height: presentationHeight
            ),
            textureTransform: image.textureTransform,
            decoderConfiguration: decoderConfiguration
        )
    }

    private func beginAnalysis(
        request: AnalysisRequest,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        guard let analyzer else
        {
            throw FabricError(
                .execution(.failed),
                severity: .recoverable,
                message: "The M-LSD analyzer is not initialized."
            )
        }

        let generation = self.lifecycleGeneration
        try analyzer.analyzeAfterCommandBufferCompletes(
            texture: request.image.texture,
            sourceSize: request.sourceSize,
            textureTransform: request.textureTransform,
            commandBuffer: commandBuffer,
            decoderConfiguration: request.decoderConfiguration
        )
        { [weak self] result in
            switch result
            {
                case let .success(frame):
                    Task { @MainActor [weak self] in
                        self?.completeAnalysis(
                            .success(
                                requestIdentifier: request.identifier,
                                frame: frame,
                                image: request.image
                            ),
                            lifecycleGeneration: generation
                        )
                    }
                case let .failure(error):
                    let message = error.localizedDescription
                    Task { @MainActor [weak self] in
                        self?.completeAnalysis(
                            .failure(
                                requestIdentifier: request.identifier,
                                message: message
                            ),
                            lifecycleGeneration: generation
                        )
                    }
            }
        }
        self.inferenceIsActive = true
    }

    private func completeAnalysis(
        _ analysis: CompletedAnalysis,
        lifecycleGeneration: UInt64
    )
    {
        guard lifecycleGeneration == self.lifecycleGeneration else { return }
        self.inferenceIsActive = false
        self.completedAnalysis = analysis
        self.markDirty()
    }

    private func publishCompletedAnalysisIfAvailable() -> String?
    {
        guard let completedAnalysis else { return nil }
        self.completedAnalysis = nil

        switch completedAnalysis
        {
            case let .success(requestIdentifier, frame, image):
                guard requestIdentifier >= self.minimumAcceptedRequestIdentifier else
                {
                    return nil
                }
                self.publish(frame: frame, image: image)
                return nil
            case let .failure(requestIdentifier, message):
                guard requestIdentifier >= self.minimumAcceptedRequestIdentifier else
                {
                    return nil
                }
                self.publishEmptyState()
                return "M-LSD structural-line analysis failed: \(message)"
        }
    }

    private func publish(frame: StructuralLineFrame, image: FabricImage)
    {
        var segments = ContiguousArray<SIMD4<Float>>()
        var confidences = ContiguousArray<Float>()
        segments.reserveCapacity(frame.edges.count)
        confidences.reserveCapacity(frame.edges.count)

        for edge in frame.edges
        {
            let start = frame.junctions[edge.startJunctionIndex].position
            let end = frame.junctions[edge.endJunctionIndex].position
            segments.append(SIMD4(start.x, start.y, end.x, end.y))
            confidences.append(edge.confidence)
        }

        self.outputSegments.send(segments)
        self.outputConfidences.send(confidences)
        self.outputLineCount.send(segments.count)
        self.outputSourceSize.send(SIMD2(
            Float(frame.sourceSize.width),
            Float(frame.sourceSize.height)
        ))
        self.outputAnalyzedImage.send(image)
    }

    private func publishEmptyState()
    {
        self.outputSegments.send(ContiguousArray<SIMD4<Float>>())
        self.outputConfidences.send(ContiguousArray<Float>())
        self.outputLineCount.send(0)
        self.outputSourceSize.send(.zero)
        self.outputAnalyzedImage.send(nil)
    }

    private func resetSchedulingState()
    {
        self.inferenceIsActive = false
        self.latestPendingRequest = nil
        self.completedAnalysis = nil
        self.changedImageCount = 0
        self.hasRequestedAnalysis = false
    }
}
