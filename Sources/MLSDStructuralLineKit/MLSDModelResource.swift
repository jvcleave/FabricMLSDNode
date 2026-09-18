import CryptoKit
import Foundation

enum MLSDModelResource
{
    private static let modelName = "mlsd_512_tiny"
    private static let expectedHash =
        "3394446fabb834545a11f7445965ed31ffc43e3d1a5d4c19a00bbeeca7c804f3"
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
