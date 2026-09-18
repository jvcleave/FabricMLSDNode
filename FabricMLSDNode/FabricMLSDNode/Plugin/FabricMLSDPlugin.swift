import Fabric
import Foundation
import MLSDStructuralLineKit

/// Entry point discovered when Fabric loads the plug-in bundle.
public final class FabricMLSDPlugin: NSObject, FabricPlugin
{
    public static func pluginDidLoad(bundle: Bundle)
    {
        // Link the core value contract without loading or compiling the model
        // during plug-in discovery.
        _ = StructuralLineLimits.mlsd512Tiny
    }

    public static func pluginWillUnload() {}

    public static func additionalNodeClasses() -> [Node.Type]
    {
        [MLSDStructuralLineAnalysisNode.self]
    }
}
