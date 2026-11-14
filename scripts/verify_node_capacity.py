#!/usr/bin/env python3
"""Run M-LSD node fixtures against an already-built native Fabric module."""

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fabric-build", type=Path, required=True,
                        help="native SwiftPM configuration directory containing description.json")
    parser.add_argument("--plugin", type=Path, required=True)
    parser.add_argument("--framework-path", type=Path, action="append", default=[],
                        help="additional runtime frameworks, e.g. Fabric Editor.app/Contents/Frameworks")
    parser.add_argument("--fixture", choices=("capacity", "analysis"), default="capacity")
    arguments = parser.parse_args()
    build = arguments.fabric_build.resolve()
    description = json.loads((build / "description.json").read_text())
    command = next(value for value in description["swiftCommands"].values()
                   if value.get("moduleName") == "Fabric")
    # Import the same transitive C modules and frameworks as Fabric. Avoid
    # copying source-compilation, optimization, macro, and output arguments.
    import_arguments = []
    native_arguments = iter(command["otherArguments"])
    for argument in native_arguments:
        if argument in ("-Xcc", "-I", "-F", "-sdk", "-target", "-swift-version"):
            import_arguments.extend((argument, next(native_arguments)))
    fixture = {"capacity": "verify_node_capacity", "analysis": "verify_analysis_delivery"}
    source = Path(__file__).resolve().with_name(fixture[arguments.fixture] + ".swift")
    with tempfile.TemporaryDirectory(prefix="fabric-mlsd-verification-") as directory:
        executable = Path(directory) / source.stem
        if arguments.fixture == "analysis":
            # Use Fabric's embedded plug-in search path so the fixture discovers
            # the requested bundle even when other copies are installed.
            contents = Path(directory) / "MLSDVerification.app" / "Contents"
            plugins = contents / "PlugIns"
            plugins.mkdir(parents=True)
            plugin = arguments.plugin.resolve()
            (plugins / plugin.name).symlink_to(plugin, target_is_directory=True)
            executable = contents / "MacOS" / source.stem
            executable.parent.mkdir()
        subprocess.run([
            "xcrun", "swiftc", str(source), "-o", str(executable),
            "-I", command["importPath"], "-L", str(build), "-F", str(build),
            "-lFabric", "-Xlinker", "-rpath", "-Xlinker", str(build),
            *import_arguments,
        ], check=True)
        environment = os.environ.copy()
        environment["PACKAGE_RESOURCE_BUNDLE_PATH"] = str(build)
        environment["DYLD_FRAMEWORK_PATH"] = os.pathsep.join([
            str(build), *(str(path.resolve()) for path in arguments.framework_path),
            environment.get("DYLD_FRAMEWORK_PATH", ""),
        ])
        subprocess.run([str(executable), str(arguments.plugin.resolve())],
                       env=environment, check=True)


if __name__ == "__main__":
    main()
