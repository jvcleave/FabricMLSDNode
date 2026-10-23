#!/usr/bin/env python3
"""Derive a larger TopK export without changing the accepted learned graph.

Requires coremltools 9.0, not TensorFlow. The research top-200 artifact remains
the reproducible baseline; only TopK.K and descriptive metadata may change.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path

import coremltools as ct

BASE_SHA256 = "3394446fabb834545a11f7445965ed31ffc43e3d1a5d4c19a00bbeeca7c804f3"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-model", type=Path,
        default=Path(__file__).resolve().parents[1] / "Models/mlsd_512_tiny.mlmodel",
    )
    parser.add_argument("--candidates", type=int, choices=[500, 1000], default=1000)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    if arguments.base_model.resolve() == arguments.output.resolve():
        raise SystemExit("The research baseline must not be overwritten.")
    if hashlib.sha256(arguments.base_model.read_bytes()).hexdigest() != BASE_SHA256:
        raise SystemExit("Expected the pinned, accepted 200-candidate Core ML artifact.")

    baseline = ct.utils.load_spec(str(arguments.base_model))
    if baseline.WhichOneof("Type") != "neuralNetwork":
        raise SystemExit("Expected the accepted neuralNetwork representation.")
    model = copy.deepcopy(baseline)
    selection_layers = [
        layer for layer in model.neuralNetwork.layers
        if layer.WhichOneof("layer") == "topK"
    ]
    if (len(selection_layers) != 1 or selection_layers[0].topK.K != 200
            or selection_layers[0].topK.axis != -1):
        raise SystemExit("Unexpected TopK graph contract.")
    selection_layers[0].topK.K = arguments.candidates
    model.description.metadata.shortDescription = (
        f"M-LSD 512 tiny line-segment detector with in-graph top-{arguments.candidates} selection."
    )
    model.description.metadata.userDefined["mlsd.base_sha256"] = BASE_SHA256
    model.description.metadata.userDefined["mlsd.candidates"] = str(arguments.candidates)
    for output in model.description.output:
        output.shortDescription = output.shortDescription.replace("Top-200", f"Top-{arguments.candidates}")

    restored = copy.deepcopy(model)
    next(layer for layer in restored.neuralNetwork.layers
         if layer.WhichOneof("layer") == "topK").topK.K = 200
    restored.description.CopyFrom(baseline.description)
    if restored.SerializeToString(deterministic=True) != baseline.SerializeToString(deterministic=True):
        raise SystemExit("Export unexpectedly modified weights or another graph operation.")

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(model.SerializeToString(deterministic=True))
    print(json.dumps({
        "candidates": arguments.candidates,
        "base_sha256": BASE_SHA256,
        "sha256": hashlib.sha256(arguments.output.read_bytes()).hexdigest(),
        "representation": "neuralNetwork",
        "specification_version": model.specificationVersion,
        "only_topk_and_metadata_changed": True,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
