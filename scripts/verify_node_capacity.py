#!/usr/bin/env python3
"""Compile the capacity fixture against an already-built native Fabric module."""

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
    source = Path(__file__).with_suffix(".swift").resolve()
    with tempfile.TemporaryDirectory(prefix="fabric-mlsd-capacity-") as directory:
        executable = Path(directory) / "verify_node_capacity"
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
