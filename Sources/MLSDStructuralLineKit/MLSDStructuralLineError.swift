import CoreML
import CoreVideo
import Foundation

public enum MLSDStructuralLineError: Error
{
    case missingModelResource
    case missingModelLicense
    case modelArtifactHashMismatch(expected: String, actual: String)
    case modelLicenseHashMismatch(expected: String, actual: String)
    case missingPreprocessingResource
    case missingPreprocessingFunction
    case pixelBufferPoolCreationFailed(CVReturn)
    case pixelBufferCreationFailed(CVReturn)
    case textureCacheCreationFailed(CVReturn)
    case destinationTextureCreationFailed(CVReturn)
    case commandEncodingFailed
    case gpuExecutionFailed(String?)
    case invalidSourceTexture
    case deviceMismatch
    case missingInput(String)
    case invalidInputType(String)
    case invalidInputSize(width: Int, height: Int)
    case invalidOutputNames(expected: [String], actual: [String])
    case invalidOutputType(String)
    case invalidOutputShape(name: String, expected: [Int], actual: [Int])
    case invalidOutputElementType(name: String, actual: MLMultiArrayDataType)
    case missingPredictionOutput(String)
    case sourceTextureCreationFailed
    case invalidCenter(index: Int)
    case invalidScore(index: Int)
    case invalidDisplacement(candidateIndex: Int)
}

extension MLSDStructuralLineError: LocalizedError
{
    public var errorDescription: String?
    {
        switch self
        {
            case .missingModelResource:
                "The bundled M-LSD Core ML model could not be found."
            case .missingModelLicense:
                "The bundled M-LSD Apache-2.0 license could not be found."
            case let .modelArtifactHashMismatch(expected, actual):
                "M-LSD artifact hash mismatch: expected \(expected), got \(actual)."
            case let .modelLicenseHashMismatch(expected, actual):
                "M-LSD license hash mismatch: expected \(expected), got \(actual)."
            case .missingPreprocessingResource:
                "The M-LSD Metal preprocessing source could not be found."
            case .missingPreprocessingFunction:
                "The M-LSD Metal preprocessing function could not be created."
            case let .pixelBufferPoolCreationFailed(status):
                "Could not create M-LSD pixel-buffer pool (\(status))."
            case let .pixelBufferCreationFailed(status):
                "Could not allocate an M-LSD input pixel buffer (\(status))."
            case let .textureCacheCreationFailed(status):
                "Could not create the M-LSD Metal texture cache (\(status))."
            case let .destinationTextureCreationFailed(status):
                "Could not create the M-LSD destination texture (\(status))."
            case .commandEncodingFailed:
                "Could not encode M-LSD Metal preprocessing."
            case let .gpuExecutionFailed(message):
                "M-LSD Metal preprocessing failed\(message.map { ": \($0)" } ?? ".")."
            case .invalidSourceTexture:
                "M-LSD source texture dimensions must both be positive."
            case .deviceMismatch:
                "M-LSD textures and command queue must use the analyzer's Metal device."
            case let .missingInput(name):
                "M-LSD model is missing input \(name)."
            case let .invalidInputType(name):
                "M-LSD model input \(name) is not an image."
            case let .invalidInputSize(width, height):
                "M-LSD model input is \(width)x\(height), expected 512x512."
            case let .invalidOutputNames(expected, actual):
                "M-LSD outputs are \(actual), expected \(expected)."
            case let .invalidOutputType(name):
                "M-LSD output \(name) is not an MLMultiArray."
            case let .invalidOutputShape(name, expected, actual):
                "M-LSD output \(name) shape is \(actual), expected \(expected)."
            case let .invalidOutputElementType(name, actual):
                "M-LSD output \(name) has element type \(actual), expected float32."
            case let .missingPredictionOutput(name):
                "M-LSD prediction did not return \(name)."
            case .sourceTextureCreationFailed:
                "Could not create the deterministic M-LSD warm-up texture."
            case let .invalidCenter(index):
                "M-LSD candidate \(index) has a non-finite or out-of-range center."
            case let .invalidScore(index):
                "M-LSD candidate \(index) has a non-finite or out-of-range score."
            case let .invalidDisplacement(candidateIndex):
                "M-LSD candidate \(candidateIndex) has a non-finite displacement."
        }
    }
}
