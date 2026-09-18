import CoreML
import Foundation

public enum MLSDDecoderConfigurationError: Error, Sendable, Equatable
{
    case invalidMinimumConfidence
    case invalidMinimumMapLength
    case invalidMaximumEdges
}

public struct MLSDDecoderConfiguration: Sendable, Equatable
{
    public static let standard = MLSDDecoderConfiguration(
        uncheckedMinimumConfidence: 0.05,
        minimumMapLength: 20,
        maximumEdges: StructuralLineLimits.mlsd512Tiny.maximumEdges
    )

    public let minimumConfidence: Float
    public let minimumMapLength: Float
    public let maximumEdges: Int

    public init(
        minimumConfidence: Float = 0.05,
        minimumMapLength: Float = 20,
        maximumEdges: Int = 200
    ) throws
    {
        guard minimumConfidence.isFinite,
              (0 ... 1).contains(minimumConfidence)
        else
        {
            throw MLSDDecoderConfigurationError.invalidMinimumConfidence
        }
        guard minimumMapLength.isFinite, minimumMapLength >= 0 else
        {
            throw MLSDDecoderConfigurationError.invalidMinimumMapLength
        }
        guard maximumEdges > 0,
              maximumEdges <= StructuralLineLimits.mlsd512Tiny.maximumEdges
        else
        {
            throw MLSDDecoderConfigurationError.invalidMaximumEdges
        }
        self.minimumConfidence = minimumConfidence
        self.minimumMapLength = minimumMapLength
        self.maximumEdges = maximumEdges
    }

    private init(
        uncheckedMinimumConfidence: Float,
        minimumMapLength: Float,
        maximumEdges: Int
    )
    {
        self.minimumConfidence = uncheckedMinimumConfidence
        self.minimumMapLength = minimumMapLength
        self.maximumEdges = maximumEdges
    }
}

/// Decodes M-LSD's top-200 centers into independent segment endpoint pairs.
/// Endpoints outside the image are clamped only when forming the package's
/// normalized bottom-left coordinate contract.
final class MLSDDecoder
{
    func decode(
        _ output: MLSDBackboneOutput,
        sourceSize: StructuralLineImageSize,
        configuration: MLSDDecoderConfiguration = .standard
    ) throws -> StructuralLineFrame
    {
        try self.decode(
            centerPoints: output.centerPoints,
            centerScores: output.centerScores,
            displacementMap: output.displacementMap,
            sourceSize: sourceSize,
            configuration: configuration
        )
    }

    func decode(
        centerPoints: MLMultiArray,
        centerScores: MLMultiArray,
        displacementMap: MLMultiArray,
        sourceSize: StructuralLineImageSize,
        configuration: MLSDDecoderConfiguration = .standard
    ) throws -> StructuralLineFrame
    {
        try MLSDModelMetadata.validate(array: centerPoints, named: "center_points")
        try MLSDModelMetadata.validate(array: centerScores, named: "center_scores")
        try MLSDModelMetadata.validate(array: displacementMap, named: "displacement_map")

        var candidates = [Candidate]()
        candidates.reserveCapacity(200)
        for index in 0 ..< 200
        {
            let score = centerScores[[0, NSNumber(value: index)]].floatValue
            guard score.isFinite, (0 ... 1).contains(score) else
            {
                throw MLSDStructuralLineError.invalidScore(index: index)
            }
            guard score > configuration.minimumConfidence else
            {
                continue
            }

            let centerYValue = centerPoints[
                [0, NSNumber(value: index), 0]
            ].floatValue
            let centerXValue = centerPoints[
                [0, NSNumber(value: index), 1]
            ].floatValue
            guard centerYValue.isFinite, centerXValue.isFinite else
            {
                throw MLSDStructuralLineError.invalidCenter(index: index)
            }
            let centerY = Int(centerYValue)
            let centerX = Int(centerXValue)
            guard (0 ..< 256).contains(centerY), (0 ..< 256).contains(centerX) else
            {
                throw MLSDStructuralLineError.invalidCenter(index: index)
            }

            var displacement = SIMD4<Float>()
            for component in 0 ..< 4
            {
                displacement[component] = displacementMap[
                    [0, NSNumber(value: centerY), NSNumber(value: centerX), NSNumber(value: component)]
                ].floatValue
            }
            guard displacement.x.isFinite,
                  displacement.y.isFinite,
                  displacement.z.isFinite,
                  displacement.w.isFinite
            else
            {
                throw MLSDStructuralLineError.invalidDisplacement(candidateIndex: index)
            }
            let delta = SIMD2(
                displacement.x - displacement.z,
                displacement.y - displacement.w
            )
            let length = sqrt(delta.x * delta.x + delta.y * delta.y)
            guard length > configuration.minimumMapLength else
            {
                continue
            }

            candidates.append(Candidate(
                sourceIndex: index,
                score: score,
                start: Self.normalizedBottomLeft(
                    centerX: centerX,
                    centerY: centerY,
                    displacementX: displacement.x,
                    displacementY: displacement.y
                ),
                end: Self.normalizedBottomLeft(
                    centerX: centerX,
                    centerY: centerY,
                    displacementX: displacement.z,
                    displacementY: displacement.w
                )
            ))
        }

        candidates.sort
        { lhs, rhs in
            lhs.score == rhs.score
                ? lhs.sourceIndex < rhs.sourceIndex
                : lhs.score > rhs.score
        }
        if candidates.count > configuration.maximumEdges
        {
            candidates.removeSubrange(configuration.maximumEdges...)
        }

        var junctions = [StructuralLineJunction]()
        var edges = [StructuralLineEdge]()
        junctions.reserveCapacity(candidates.count * 2)
        edges.reserveCapacity(candidates.count)
        for candidate in candidates
        {
            let startIndex = junctions.count
            junctions.append(StructuralLineJunction(
                position: candidate.start,
                confidence: candidate.score
            ))
            junctions.append(StructuralLineJunction(
                position: candidate.end,
                confidence: candidate.score
            ))
            edges.append(StructuralLineEdge(
                startJunctionIndex: startIndex,
                endJunctionIndex: startIndex + 1,
                confidence: candidate.score
            ))
        }
        return try StructuralLineFrame(
            sourceSize: sourceSize,
            junctions: junctions,
            edges: edges,
            limits: .mlsd512Tiny
        )
    }

    private static func normalizedBottomLeft(
        centerX: Int,
        centerY: Int,
        displacementX: Float,
        displacementY: Float
    ) -> SIMD2<Float>
    {
        let x = 2 * (Float(centerX) + displacementX) / 512
        let topY = 2 * (Float(centerY) + displacementY) / 512
        return SIMD2(
            min(1, max(0, x)),
            min(1, max(0, 1 - topY))
        )
    }

    private struct Candidate
    {
        let sourceIndex: Int
        let score: Float
        let start: SIMD2<Float>
        let end: SIMD2<Float>
    }
}
