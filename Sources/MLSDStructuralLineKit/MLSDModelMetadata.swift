import CoreML

enum MLSDModelMetadata
{
    static let inputName = "image"
    static let inputWidth = 512
    static let inputHeight = 512
    static let outputShapes: [String: [Int]] = [
        "center_points": [1, 200, 2],
        "center_scores": [1, 200],
        "displacement_map": [1, 256, 256, 4],
    ]

    static func validate(modelDescription: MLModelDescription) throws
    {
        guard let input = modelDescription.inputDescriptionsByName[self.inputName]
        else
        {
            throw MLSDStructuralLineError.missingInput(self.inputName)
        }
        guard input.type == .image, let constraint = input.imageConstraint else
        {
            throw MLSDStructuralLineError.invalidInputType(self.inputName)
        }
        guard constraint.pixelsWide == self.inputWidth,
              constraint.pixelsHigh == self.inputHeight
        else
        {
            throw MLSDStructuralLineError.invalidInputSize(
                width: constraint.pixelsWide,
                height: constraint.pixelsHigh
            )
        }

        let expectedNames = Set(self.outputShapes.keys)
        let actualNames = Set(modelDescription.outputDescriptionsByName.keys)
        guard actualNames == expectedNames else
        {
            throw MLSDStructuralLineError.invalidOutputNames(
                expected: expectedNames.sorted(),
                actual: actualNames.sorted()
            )
        }
        for name in expectedNames
        {
            guard let output = modelDescription.outputDescriptionsByName[name],
                  output.type == .multiArray
            else
            {
                throw MLSDStructuralLineError.invalidOutputType(name)
            }
        }
    }

    static func validate(array: MLMultiArray, named name: String) throws
    {
        guard let expectedShape = self.outputShapes[name] else
        {
            throw MLSDStructuralLineError.missingPredictionOutput(name)
        }
        let shape = array.shape.map(\.intValue)
        guard shape == expectedShape else
        {
            throw MLSDStructuralLineError.invalidOutputShape(
                name: name,
                expected: expectedShape,
                actual: shape
            )
        }
        guard array.dataType == .float32 else
        {
            throw MLSDStructuralLineError.invalidOutputElementType(
                name: name,
                actual: array.dataType
            )
        }
    }
}
