import CryptoKit
import Foundation

enum MLSDModelResource
{
    private static let modelName = "mlsd_512_tiny"
    private static let expectedHash =
        "e23a999f4d3ba993a667afacb399d8193ce1bb0d4853087153287fa2780234cd"
    private static let expectedLicenseHash =
        "b8a6637c19443e6792ce93c37fe1faac3c745e319ffcd90ac8be0a170a9a1900"

    static func modelURL(bundle: Bundle = .module) throws -> URL
    {
        guard let url = bundle.url(
            forResource: self.modelName,
            withExtension: "mlmodel",
            subdirectory: "Models"
        ) else
        {
            throw MLSDStructuralLineError.missingModelResource
        }
        return url
    }

    static func validatePinnedArtifact(bundle: Bundle = .module) throws
    {
        let url = try self.modelURL(bundle: bundle)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let actualHash = SHA256.hash(data: data).map
        {
            String(format: "%02x", $0)
        }.joined()
        guard actualHash == self.expectedHash else
        {
            throw MLSDStructuralLineError.modelArtifactHashMismatch(
                expected: self.expectedHash,
                actual: actualHash
            )
        }

        guard let licenseURL = bundle.url(
            forResource: "LICENSE-MLSD",
            withExtension: "txt",
            subdirectory: "Models"
        ) else
        {
            throw MLSDStructuralLineError.missingModelLicense
        }
        let licenseData = try Data(contentsOf: licenseURL, options: .mappedIfSafe)
        let actualLicenseHash = SHA256.hash(data: licenseData).map
        {
            String(format: "%02x", $0)
        }.joined()
        guard actualLicenseHash == self.expectedLicenseHash else
        {
            throw MLSDStructuralLineError.modelLicenseHashMismatch(
                expected: self.expectedLicenseHash,
                actual: actualLicenseHash
            )
        }
    }
}
