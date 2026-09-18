import Foundation
import Testing
@testable import MLSDStructuralLineKit

@Suite("Structural-line value contracts")
struct StructuralLineTypesTests
{
    @Test("Accepts a bounded canonical graph in normalized bottom-left space")
    func acceptsCanonicalGraph() throws
    {
        let frame = try StructuralLineFrame(
            sourceSize: StructuralLineImageSize(width: 1_280, height: 720),
            junctions: [
                StructuralLineJunction(position: SIMD2(0.1, 0.2), confidence: 0.9),
                StructuralLineJunction(position: SIMD2(0.8, 0.7), confidence: 0.8),
            ],
            edges: [
                StructuralLineEdge(
                    startJunctionIndex: 0,
                    endJunctionIndex: 1,
                    confidence: 0.75
                ),
            ]
        )

        #expect(frame.coordinateSpace == .normalizedImageBottomLeft)
        #expect(frame.sourceSize == StructuralLineImageSize(width: 1_280, height: 720))
        #expect(frame.junctions.count == 2)
        #expect(frame.edges.count == 1)
    }

    @Test("Rejects invalid geometry and topology centrally")
    func rejectsInvalidGraph() throws
    {
        let validJunctions = [
            StructuralLineJunction(position: SIMD2(0.1, 0.2), confidence: 0.9),
            StructuralLineJunction(position: SIMD2(0.8, 0.7), confidence: 0.8),
        ]

        #expect(throws: StructuralLineValidationError.invalidSourceSize) {
            try StructuralLineFrame(
                sourceSize: StructuralLineImageSize(width: 0, height: 720),
                junctions: [],
                edges: []
            )
        }
        #expect(throws: StructuralLineValidationError.invalidJunctionPosition(index: 0)) {
            try StructuralLineFrame(
                sourceSize: StructuralLineImageSize(width: 10, height: 10),
                junctions: [
                    StructuralLineJunction(position: SIMD2(.nan, 0.5), confidence: 1),
                ],
                edges: []
            )
        }
        #expect(throws: StructuralLineValidationError.nonCanonicalEdge(index: 0)) {
            try StructuralLineFrame(
                sourceSize: StructuralLineImageSize(width: 10, height: 10),
                junctions: validJunctions,
                edges: [
                    StructuralLineEdge(
                        startJunctionIndex: 1,
                        endJunctionIndex: 0,
                        confidence: 1
                    ),
                ]
            )
        }
        #expect(throws: StructuralLineValidationError.duplicateEdge(index: 1, firstIndex: 0)) {
            try StructuralLineFrame(
                sourceSize: StructuralLineImageSize(width: 10, height: 10),
                junctions: validJunctions,
                edges: [
                    StructuralLineEdge(startJunctionIndex: 0, endJunctionIndex: 1, confidence: 1),
                    StructuralLineEdge(startJunctionIndex: 0, endJunctionIndex: 1, confidence: 0.5),
                ]
            )
        }
    }

    @Test("Enforces caller-selected graph bounds")
    func enforcesBounds() throws
    {
        let limits = try StructuralLineLimits(maximumJunctions: 1, maximumEdges: 1)
        #expect(throws: StructuralLineValidationError.tooManyJunctions(actual: 2, maximum: 1)) {
            try StructuralLineFrame(
                sourceSize: StructuralLineImageSize(width: 10, height: 10),
                junctions: [
                    StructuralLineJunction(position: .zero, confidence: 1),
                    StructuralLineJunction(position: SIMD2(1, 1), confidence: 1),
                ],
                edges: [],
                limits: limits
            )
        }
    }
}
