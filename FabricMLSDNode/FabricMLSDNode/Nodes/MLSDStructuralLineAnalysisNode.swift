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
                        StructuralLineLimits.mlsd512Tiny.maximumEdges,
                        1,
                        StructuralLineLimits.mlsd512Tiny.maximumEdges,
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
        let image: FabricImage
        let sourceSize: StructuralLineImageSize
        let textureTransform: simd_float4x4
        let decoderConfiguration: MLSDDecoderConfiguration
    }

    private typealias AnalysisResult = Result<StructuralLineFrame, any Error>

    private final class AnalysisMailbox
    {
        private let lock = NSLock()
        private var result: AnalysisResult?

        var outcome: AnalysisResult? { self.lock.withLock { self.result } }

        func finish(_ result: AnalysisResult)
        {
            self.lock.withLock
            {
                if self.result == nil { self.result = result }
            }
        }
    }

    // The completion handler owns the source image and its external backing
    // through GPU work and inference. Releasing the handler before it reports an
    // outcome also retires the request.
    private final class AnalysisCompletion
    {
        let mailbox = AnalysisMailbox()
        private let sourceImage: FabricImage

        init(sourceImage: FabricImage) { self.sourceImage = sourceImage }

        func finish(_ result: AnalysisResult) { self.mailbox.finish(result) }

        deinit { self.mailbox.finish(.failure(CancellationError())) }
    }

    private struct ActiveAnalysis
    {
        let mailbox: AnalysisMailbox
        // Clearing the request cancels publication while the mailbox still tracks retirement.
        var request: AnalysisRequest?
    }

    private var analyzer: MLSDStructuralLineAnalyzer?
    private var activeAnalysis: ActiveAnalysis?
    private var latestPendingRequest: AnalysisRequest?
    private var inputConnectionID: UUID?
    private var changedImageCount = 0
    private var hasRequestedAnalysis = false

    public override var isDirty: Bool
    {
        if super.isDirty { return true }
        guard self.executionState == .started else { return false }
        if let activeAnalysis { return activeAnalysis.mailbox.outcome != nil }
        return self.latestPendingRequest != nil
    }

    public override func startExecution(renderer: GraphRenderer) throws
    {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        self.analyzer = try MLSDStructuralLineAnalyzer(
            device: self.context.device,
            modelConfiguration: configuration
        )
        self.markDirty()
        try super.startExecution(renderer: renderer)
    }

    public override func stopExecution(renderer: GraphRenderer) throws
    {
        self.invalidateInput()
        self.inputConnectionID = nil
        if self.activeAnalysis?.mailbox.outcome != nil { self.activeAnalysis = nil }
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
        let image = self.inputImage.value
        if self.inputImage.valueDidChange
        {
            let connectionID = self.inputImage.connectedOutlets.first.flatMap {
                self.inputImage.connection(to: $0)?.id
            }
            if connectionID != self.inputConnectionID { self.invalidateInput() }
            self.inputConnectionID = connectionID
        }
        if image == nil { self.invalidateInput() }

        let completedError = self.retireCompletedAnalysis()
        let decoderParametersChanged = self.inputMinimumConfidence.valueDidChange
            || self.inputMaximumLines.valueDidChange
        let intervalChanged = self.inputAnalysisInterval.valueDidChange

        if let image
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
                do
                {
                    self.latestPendingRequest = try self.makeRequest(image: image)
                }
                catch
                {
                    self.invalidateInput()
                    throw Self.analysisError(error)
                }
                self.hasRequestedAnalysis = true
            }
        }

        if self.activeAnalysis == nil, let request = self.latestPendingRequest
        {
            self.latestPendingRequest = nil
            try self.beginAnalysis(request: request, commandBuffer: commandBuffer)
        }

        if let completedError { throw Self.analysisError(completedError) }
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
            throw StructuralLineValidationError.invalidSourceSize
        }

        let presentationWidth = max(1, Int(image.presentationSize.width.rounded()))
        let presentationHeight = max(1, Int(image.presentationSize.height.rounded()))
        let minimumConfidence = min(max(self.inputMinimumConfidence.value ?? 0.05, 0), 1)
        let lineLimit = StructuralLineLimits.mlsd512Tiny.maximumEdges
        let maximumLines = min(max(self.inputMaximumLines.value ?? lineLimit, 1), lineLimit)
        let decoderConfiguration = try MLSDDecoderConfiguration(
            minimumConfidence: minimumConfidence,
            minimumMapLength: 20,
            maximumEdges: maximumLines
        )
        return AnalysisRequest(
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

        let completion = AnalysisCompletion(sourceImage: request.image)
        do
        {
            try analyzer.analyzeAfterCommandBufferCompletes(
                texture: request.image.texture,
                sourceSize: request.sourceSize,
                textureTransform: request.textureTransform,
                commandBuffer: commandBuffer,
                decoderConfiguration: request.decoderConfiguration,
                completion: completion.finish
            )
        }
        catch
        {
            self.publishEmptyState()
            throw Self.analysisError(error)
        }
        self.activeAnalysis = ActiveAnalysis(mailbox: completion.mailbox, request: request)
    }

    private func retireCompletedAnalysis() -> (any Error)?
    {
        guard let active = self.activeAnalysis, let outcome = active.mailbox.outcome else { return nil }
        self.activeAnalysis = nil
        guard let request = active.request else { return nil }

        switch outcome
        {
            case let .success(frame):
                self.publish(frame: frame, image: request.image)
                return nil
            case .failure(is CancellationError):
                // A newer eligible input takes precedence when the lost work is retried.
                if self.latestPendingRequest == nil { self.latestPendingRequest = request }
                return nil
            case let .failure(error):
                self.publishEmptyState()
                return error
        }
    }

    private static func analysisError(_ error: any Error) -> FabricError
    {
        FabricError(
            .execution(.failed), severity: .recoverable,
            message: "M-LSD structural-line analysis failed: \(error.localizedDescription)",
            underlyingError: error
        )
    }

    private func invalidateInput()
    {
        self.activeAnalysis?.request = nil
        self.latestPendingRequest = nil
        self.changedImageCount = 0
        self.hasRequestedAnalysis = false
        self.publishEmptyState()
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
}
