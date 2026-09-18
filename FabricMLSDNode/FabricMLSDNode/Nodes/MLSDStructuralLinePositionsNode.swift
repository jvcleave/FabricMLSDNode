import Fabric
import Metal
import Satin
import simd

/// Places each independent image-space line on a centered, aspect-correct XY plane.
public final class MLSDStructuralLinePositionsNode: Node
{
    public override class var name: String { "M-LSD Positions" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    public override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    public override class var nodeTimeMode: Node.TimeMode { .None }
    public override class var nodeDescription: String
    {
        "Converts normalized M-LSD lines into ordered, unmerged endpoint positions on an XY plane."
    }

    public override class func registerPorts(context: Context) -> [(name: String, port: Fabric.Port)]
    {
        super.registerPorts(context: context) +
        [
            (
                "inputSegments",
                NodePort<ContiguousArray<SIMD4<Float>>>(
                    name: "Lines",
                    kind: .Inlet,
                    description: "Normalized bottom-left [startX, startY, endX, endY] line segments"
                )
            ),
            (
                "inputSourceSize",
                NodePort<SIMD2<Float>>(
                    name: "Size",
                    kind: .Inlet,
                    description: "Presentation width and height of the analyzed image"
                )
            ),
            (
                "inputPlaneWidth",
                ParameterPort(
                    parameter: FloatParameter(
                        "Width",
                        1,
                        0.001,
                        1000,
                        .inputfield,
                        "Width of the centered XY plane in world units"
                    )
                )
            ),
            (
                "outputPositions",
                NodePort<ContiguousArray<SIMD3<Float>>>(
                    name: "Positions",
                    kind: .Outlet,
                    description: "Start/end Vector3 pairs on an aspect-correct XY plane at Z = 0"
                )
            ),
        ]
    }

    public var inputSegments: NodePort<ContiguousArray<SIMD4<Float>>> { port(named: "inputSegments") }
    public var inputSourceSize: NodePort<SIMD2<Float>> { port(named: "inputSourceSize") }
    public var inputPlaneWidth: ParameterPort<Float> { port(named: "inputPlaneWidth") }
    public var outputPositions: NodePort<ContiguousArray<SIMD3<Float>>> { port(named: "outputPositions") }

    public override func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        guard self.inputSegments.valueDidChange
            || self.inputSourceSize.valueDidChange
            || self.inputPlaneWidth.valueDidChange
        else { return }

        guard let segments = self.inputSegments.value, !segments.isEmpty else
        {
            self.outputPositions.send(ContiguousArray<SIMD3<Float>>())
            return
        }

        guard segments.count <= 200 else
        {
            throw self.clearPositionsAndMakeError("M-LSD Positions accepts at most 200 lines.")
        }

        guard let sourceSize = self.inputSourceSize.value,
              sourceSize.x.isFinite, sourceSize.y.isFinite,
              sourceSize.x > 0, sourceSize.y > 0,
              let planeWidth = self.inputPlaneWidth.value,
              planeWidth.isFinite, planeWidth > 0
        else
        {
            throw self.clearPositionsAndMakeError(
                "M-LSD Positions needs finite positive Size and Width values for nonempty Lines."
            )
        }

        let planeHeight = planeWidth * (sourceSize.y / sourceSize.x)
        guard planeHeight.isFinite, planeHeight > 0 else
        {
            throw self.clearPositionsAndMakeError("M-LSD Positions cannot represent this plane aspect ratio.")
        }

        var positions = ContiguousArray<SIMD3<Float>>()
        positions.reserveCapacity(segments.count * 2)

        for segment in segments
        {
            guard Self.isNormalized(segment.x), Self.isNormalized(segment.y),
                  Self.isNormalized(segment.z), Self.isNormalized(segment.w)
            else
            {
                throw self.clearPositionsAndMakeError(
                    "M-LSD Positions needs finite, normalized line endpoints."
                )
            }

            positions.append(SIMD3(
                (segment.x - 0.5) * planeWidth,
                (segment.y - 0.5) * planeHeight,
                0
            ))
            positions.append(SIMD3(
                (segment.z - 0.5) * planeWidth,
                (segment.w - 0.5) * planeHeight,
                0
            ))
        }

        self.outputPositions.send(positions)
    }

    private static func isNormalized(_ coordinate: Float) -> Bool
    {
        coordinate.isFinite && (0...1).contains(coordinate)
    }

    private func clearPositionsAndMakeError(_ message: String) -> FabricError
    {
        self.outputPositions.send(ContiguousArray<SIMD3<Float>>())
        return FabricError(.execution(.failed), severity: .recoverable, message: message)
    }
}
