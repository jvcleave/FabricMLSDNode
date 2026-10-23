#!/usr/bin/env python3
"""Compare a larger candidate export against the independently verified baseline."""

import argparse
import hashlib
import json
import statistics
import time
from pathlib import Path

import coremltools as ct
import cv2
import numpy as np
from PIL import Image


def segment_counts(prediction):
    points = prediction["center_points"][0].astype(np.int32)
    scores = prediction["center_scores"][0]
    displacement_map = prediction["displacement_map"][0]
    displacements = displacement_map[points[:, 0], points[:, 1]]
    lengths = np.linalg.norm(displacements[:, :2] - displacements[:, 2:], axis=1)
    return {
        str(threshold): int(np.count_nonzero((scores > threshold) & (lengths > 20)))
        for threshold in (0, 0.001, 0.01, 0.025, 0.05, 0.1, 0.2, 0.5)
    }


def timed_prediction(model, image):
    durations = []
    for _ in range(5):
        start = time.perf_counter()
        prediction = model.predict({"image": image})
        durations.append((time.perf_counter() - start) * 1000)
    return prediction, statistics.median(durations[1:])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    baseline = ct.models.MLModel(str(arguments.baseline), compute_units=ct.ComputeUnit.CPU_ONLY)
    candidate = ct.models.MLModel(str(arguments.candidate), compute_units=ct.ComputeUnit.CPU_ONLY)
    candidate_gpu = ct.models.MLModel(str(arguments.candidate), compute_units=ct.ComputeUnit.CPU_AND_GPU)
    report = {
        "baseline_sha256": hashlib.sha256(arguments.baseline.read_bytes()).hexdigest(),
        "candidate_sha256": hashlib.sha256(arguments.candidate.read_bytes()).hexdigest(),
        "preprocessing": "OpenCV INTER_AREA RGB 512x512, matching the official reference generator",
        "timings": "Median of four warm predictions after one first prediction; model loading excluded",
        "fixtures": {},
    }
    for fixture in arguments.fixtures:
        source = cv2.imread(str(fixture), cv2.IMREAD_COLOR)
        if source is None:
            raise FileNotFoundError(fixture)
        image = Image.fromarray(cv2.resize(source[:, :, ::-1], (512, 512), interpolation=cv2.INTER_AREA))
        original, baseline_ms = timed_prediction(baseline, image)
        extended, candidate_ms = timed_prediction(candidate, image)
        accelerated, gpu_ms = timed_prediction(candidate_gpu, image)
        assert extended["center_points"].shape == (1, 1000, 2)
        assert extended["center_scores"].shape == (1, 1000)
        assert extended["displacement_map"].shape == (1, 256, 256, 4)
        assert np.array_equal(original["center_points"], extended["center_points"][:, :200])
        assert np.array_equal(original["center_scores"], extended["center_scores"][:, :200])
        assert np.array_equal(original["displacement_map"], extended["displacement_map"])
        assert all(np.isfinite(value).all() for value in accelerated.values())
        report["fixtures"][fixture.name] = {
            "first_200_centers_and_scores_exact": True,
            "whole_displacement_map_exact": True,
            "baseline_counts": segment_counts(original),
            "candidate_cpu_counts": segment_counts(extended),
            "candidate_gpu_counts": segment_counts(accelerated),
            "baseline_cpu_warm_ms": baseline_ms,
            "candidate_cpu_warm_ms": candidate_ms,
            "candidate_cpu_and_gpu_warm_ms": gpu_ms,
        }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
