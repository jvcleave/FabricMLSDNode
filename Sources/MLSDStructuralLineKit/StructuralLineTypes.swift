import Foundation
import simd

public enum StructuralLineCoordinateSpace: String, Sendable, Equatable
{
    case normalizedImageBottomLeft
}

public struct StructuralLineImageSize: Sendable, Equatable
{
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int)
    {
        self.width = width
        self.height = height
    }
}

public struct StructuralLineJunction: Sendable, Equatable
{
    public let position: SIMD2<Float>
    public let confidence: Float

    public init(position: SIMD2<Float>, confidence: Float)
    {
        self.position = position
        self.confidence = confidence
    }
}

/// An undirected edge between two entries in `StructuralLineFrame.junctions`.
/// Indices are canonicalized by contract: `startJunctionIndex` must be smaller
/// than `endJunctionIndex`.
public struct StructuralLineEdge: Sendable, Equatable
{
    public let startJunctionIndex: Int
    public let endJunctionIndex: Int
    public let confidence: Float

    public init(
        startJunctionIndex: Int,
        endJunctionIndex: Int,
        confidence: Float
    )
    {
        self.startJunctionIndex = startJunctionIndex
        self.endJunctionIndex = endJunctionIndex
        self.confidence = confidence
    }
}

public struct StructuralLineLimits: Sendable, Equatable
{
    /// M-LSD emits at most 200 independent segments. Each segment deliberately
    /// owns two junctions because the model does not infer shared topology.
    public static let mlsd512Tiny = StructuralLineLimits(
        uncheckedMaximumJunctions: 400,
        maximumEdges: 200
    )

    public let maximumJunctions: Int
    public let maximumEdges: Int

    public init(maximumJunctions: Int, maximumEdges: Int) throws
    {
        guard maximumJunctions > 0, maximumEdges > 0 else
        {
            throw StructuralLineValidationError.invalidLimits
        }
        self.maximumJunctions = maximumJunctions
        self.maximumEdges = maximumEdges
    }

    private init(uncheckedMaximumJunctions: Int, maximumEdges: Int)
    {
        self.maximumJunctions = uncheckedMaximumJunctions
        self.maximumEdges = maximumEdges
    }
}

public enum StructuralLineValidationError: Error, Sendable, Equatable
{
    case invalidLimits
    case invalidSourceSize
    case tooManyJunctions(actual: Int, maximum: Int)
    case tooManyEdges(actual: Int, maximum: Int)
    case invalidJunctionPosition(index: Int)
    case invalidJunctionConfidence(index: Int)
    case invalidEdgeConfidence(index: Int)
    case invalidEdgeJunctionIndex(edgeIndex: Int, junctionIndex: Int)
    case nonCanonicalEdge(index: Int)
    case duplicateEdge(index: Int, firstIndex: Int)
}

extension StructuralLineValidationError: LocalizedError
{
    public var errorDescription: String?
    {
        switch self
        {
            case .invalidLimits:
                "Structural-line limits must both be positive."
            case .invalidSourceSize:
                "Structural-line source dimensions must both be positive."
            case let .tooManyJunctions(actual, maximum):
                "Structural-line frame has \(actual) junctions; maximum is \(maximum)."
            case let .tooManyEdges(actual, maximum):
                "Structural-line frame has \(actual) edges; maximum is \(maximum)."
            case let .invalidJunctionPosition(index):
                "Junction \(index) has a non-finite or out-of-range normalized position."
            case let .invalidJunctionConfidence(index):
                "Junction \(index) has a non-finite or out-of-range confidence."
            case let .invalidEdgeConfidence(index):
                "Edge \(index) has a non-finite or out-of-range confidence."
            case let .invalidEdgeJunctionIndex(edgeIndex, junctionIndex):
                "Edge \(edgeIndex) references missing junction \(junctionIndex)."
            case let .nonCanonicalEdge(index):
                "Edge \(index) must reference two distinct junctions in ascending index order."
            case let .duplicateEdge(index, firstIndex):
                "Edge \(index) duplicates edge \(firstIndex)."
        }
    }
}

public struct StructuralLineFrame: Sendable, Equatable
{
    public let sourceSize: StructuralLineImageSize
    public let coordinateSpace: StructuralLineCoordinateSpace
    public let junctions: [StructuralLineJunction]
    public let edges: [StructuralLineEdge]

    public init(
        sourceSize: StructuralLineImageSize,
        junctions: [StructuralLineJunction],
        edges: [StructuralLineEdge],
        limits: StructuralLineLimits = .mlsd512Tiny
    ) throws
    {
        guard sourceSize.width > 0, sourceSize.height > 0 else
        {
            throw StructuralLineValidationError.invalidSourceSize
        }
        guard junctions.count <= limits.maximumJunctions else
        {
            throw StructuralLineValidationError.tooManyJunctions(
                actual: junctions.count,
                maximum: limits.maximumJunctions
            )
        }
        guard edges.count <= limits.maximumEdges else
        {
            throw StructuralLineValidationError.tooManyEdges(
                actual: edges.count,
                maximum: limits.maximumEdges
            )
        }

        for (index, junction) in junctions.enumerated()
        {
            guard junction.position.x.isFinite,
                  junction.position.y.isFinite,
                  (0 ... 1).contains(junction.position.x),
                  (0 ... 1).contains(junction.position.y)
            else
            {
                throw StructuralLineValidationError.invalidJunctionPosition(index: index)
            }
            guard Self.isUnitValue(junction.confidence) else
            {
                throw StructuralLineValidationError.invalidJunctionConfidence(index: index)
            }
        }

        var firstEdgeIndexByPair: [EdgePair: Int] = [:]
        for (index, edge) in edges.enumerated()
        {
            guard Self.isUnitValue(edge.confidence) else
            {
                throw StructuralLineValidationError.invalidEdgeConfidence(index: index)
            }
            guard junctions.indices.contains(edge.startJunctionIndex) else
            {
                throw StructuralLineValidationError.invalidEdgeJunctionIndex(
                    edgeIndex: index,
                    junctionIndex: edge.startJunctionIndex
                )
            }
            guard junctions.indices.contains(edge.endJunctionIndex) else
            {
                throw StructuralLineValidationError.invalidEdgeJunctionIndex(
                    edgeIndex: index,
                    junctionIndex: edge.endJunctionIndex
                )
            }
            guard edge.startJunctionIndex < edge.endJunctionIndex else
            {
                throw StructuralLineValidationError.nonCanonicalEdge(index: index)
            }

            let pair = EdgePair(edge.startJunctionIndex, edge.endJunctionIndex)
            if let firstIndex = firstEdgeIndexByPair[pair]
            {
                throw StructuralLineValidationError.duplicateEdge(
                    index: index,
                    firstIndex: firstIndex
                )
            }
            firstEdgeIndexByPair[pair] = index
        }

        self.sourceSize = sourceSize
        self.coordinateSpace = .normalizedImageBottomLeft
        self.junctions = junctions
        self.edges = edges
    }

    private static func isUnitValue(_ value: Float) -> Bool
    {
        value.isFinite && (0 ... 1).contains(value)
    }

    private struct EdgePair: Hashable
    {
        let start: Int
        let end: Int

        init(_ start: Int, _ end: Int)
        {
            self.start = start
            self.end = end
        }
    }
}
