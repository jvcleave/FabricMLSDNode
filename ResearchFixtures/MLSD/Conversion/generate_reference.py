#!/usr/bin/env python3
"""Generate deterministic M-LSD fixture summaries and a city preview."""

import argparse
import hashlib
import json
from pathlib import Path

import coremltools as ct
import cv2
import numpy as np
import tensorflow as tf
from PIL import Image

from mlsd_variants import DEFAULT_VARIANT_NAME, variant_named, variant_names


THRESHOLDS = (0.01, 0.025, 0.05, 0.1, 0.2, 0.5)
DISTANCE_THRESHOLD = 20.0


def fingerprint(array: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(array).tobytes()).hexdigest()


def extract_segments(
    points: np.ndarray,
    scores: np.ndarray,
    displacement_map: np.ndarray,
    source_width: int,
    source_height: int,
    score_threshold: float,
    map_size: int,
):
    segments = []
    for point, score in zip(points, scores):
        y, x = [int(value) for value in point]
        displacement = displacement_map[y, x]
        length = float(
            np.linalg.norm(displacement[:2] - displacement[2:])
        )
        if float(score) <= score_threshold or length <= DISTANCE_THRESHOLD:
            continue
        endpoints = [
            (x + float(displacement[0])) * source_width / map_size,
            (y + float(displacement[1])) * source_height / map_size,
            (x + float(displacement[2])) * source_width / map_size,
            (y + float(displacement[3])) * source_height / map_size,
        ]
        segments.append({
            "endpoints": [round(value, 6) for value in endpoints],
            "score": round(float(score), 8),
        })
    return segments


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tflite", required=True, type=Path)
    parser.add_argument("--coreml", required=True, type=Path)
    parser.add_argument("--city", required=True, type=Path)
    parser.add_argument("--sky", required=True, type=Path)
    parser.add_argument("--reference-output", required=True, type=Path)
    parser.add_argument("--preview-output", required=True, type=Path)
    parser.add_argument(
        "--variant",
        choices=variant_names(),
        default=DEFAULT_VARIANT_NAME,
        help="official model variant (default: %(default)s)",
    )
    arguments = parser.parse_args()
    variant = variant_named(arguments.variant)

    interpreter = tf.lite.Interpreter(
        model_path=str(arguments.tflite),
        num_threads=4,
    )
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()
    expected_tflite_input_shape = [
        1,
        variant.input_size,
        variant.input_size,
        4,
    ]
    if input_details["shape"].tolist() != expected_tflite_input_shape:
        raise ValueError(
            f"{variant.upstream_name} expected TFLite input shape "
            f"{expected_tflite_input_shape}, got "
            f"{input_details['shape'].tolist()}"
        )
    expected_tflite_output_shapes = [
        [1, 200, 2],
        [1, 200],
        [1, variant.map_size, variant.map_size, 4],
    ]
    actual_tflite_output_shapes = [
        details["shape"].tolist() for details in output_details
    ]
    if actual_tflite_output_shapes != expected_tflite_output_shapes:
        raise ValueError(
            f"{variant.upstream_name} expected TFLite output shapes "
            f"{expected_tflite_output_shapes}, got "
            f"{actual_tflite_output_shapes}"
        )
    coreml_model = ct.models.MLModel(
        str(arguments.coreml),
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )

    fixtures = {}
    city_segments = []
    city_bgr = None
    for fixture_path in (arguments.city, arguments.sky):
        source_bgr = cv2.imread(str(fixture_path), cv2.IMREAD_COLOR)
        if source_bgr is None:
            raise FileNotFoundError(f"Could not read {fixture_path}")
        source_height, source_width = source_bgr.shape[:2]
        resized_rgb = cv2.resize(
            source_bgr[:, :, ::-1],
            (variant.input_size, variant.input_size),
            interpolation=cv2.INTER_AREA,
        )
        alpha = np.ones(
            (variant.input_size, variant.input_size, 1),
            dtype=resized_rgb.dtype,
        )
        tflite_input = np.concatenate([resized_rgb, alpha], axis=-1)
        tflite_input = np.expand_dims(tflite_input, 0).astype(np.float32)
        interpreter.set_tensor(input_details["index"], tflite_input)
        interpreter.invoke()
        tflite_outputs = [
            interpreter.get_tensor(details["index"])
            for details in output_details
        ]
        tflite_points = tflite_outputs[0][0]
        tflite_scores = tflite_outputs[1][0]
        tflite_displacements = tflite_outputs[2][0]

        coreml_prediction = coreml_model.predict({
            "image": Image.fromarray(resized_rgb)
        })
        coreml_points = np.asarray(coreml_prediction["center_points"])[0]
        coreml_scores = np.asarray(coreml_prediction["center_scores"])[0]
        coreml_displacements = np.asarray(
            coreml_prediction["displacement_map"]
        )[0]

        tflite_counts = {}
        coreml_counts = {}
        for threshold in THRESHOLDS:
            key = f"{threshold:.3f}"
            tflite_counts[key] = len(extract_segments(
                tflite_points,
                tflite_scores,
                tflite_displacements,
                source_width,
                source_height,
                threshold,
                variant.map_size,
            ))
            coreml_counts[key] = len(extract_segments(
                coreml_points,
                coreml_scores,
                coreml_displacements,
                source_width,
                source_height,
                threshold,
                variant.map_size,
            ))

        selected_segments = extract_segments(
            tflite_points,
            tflite_scores,
            tflite_displacements,
            source_width,
            source_height,
            0.05,
            variant.map_size,
        )
        fixtures[fixture_path.name] = {
            "source_size": [source_width, source_height],
            "official_tflite_fp32": {
                "output_sha256": {
                    "center_points": fingerprint(tflite_outputs[0]),
                    "center_scores": fingerprint(tflite_outputs[1]),
                    "displacement_map": fingerprint(tflite_outputs[2]),
                },
                "segment_counts": tflite_counts,
                "segments_at_0_05": selected_segments,
            },
            "coreml_cpu_parity": {
                "center_points_exact": bool(np.array_equal(
                    tflite_points,
                    coreml_points,
                )),
                "maximum_score_absolute_error": float(np.max(np.abs(
                    tflite_scores - coreml_scores
                ))),
                "maximum_displacement_absolute_error": float(np.max(np.abs(
                    tflite_displacements - coreml_displacements
                ))),
                "segment_counts": coreml_counts,
            },
        }
        if fixture_path == arguments.city:
            city_segments = selected_segments
            city_bgr = source_bgr

    reference = {
        "schema_version": 1,
        "model": variant.upstream_name,
        "input": (
            f"{variant.input_size} x {variant.input_size} raw RGB values "
            "in [0, 255]"
        ),
        "map_size": [variant.map_size, variant.map_size],
        "maximum_candidates": 200,
        "center_order": ["y", "x"],
        "displacement_order": ["dx0", "dy0", "dx1", "dy1"],
        "distance_threshold_map_pixels": DISTANCE_THRESHOLD,
        "selected_score_threshold": 0.05,
        "coordinate_space": "source-image pixels, top-left origin",
        "fixtures": fixtures,
    }
    arguments.reference_output.parent.mkdir(parents=True, exist_ok=True)
    arguments.reference_output.write_text(
        json.dumps(reference, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    if city_bgr is None:
        raise RuntimeError("City fixture was not processed")
    preview = city_bgr.copy()
    for segment in city_segments:
        x0, y0, x1, y1 = segment["endpoints"]
        cv2.line(
            preview,
            (round(x0), round(y0)),
            (round(x1), round(y1)),
            (0, 255, 255),
            2,
            cv2.LINE_AA,
        )
    arguments.preview_output.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(arguments.preview_output), preview):
        raise RuntimeError(f"Could not write {arguments.preview_output}")


if __name__ == "__main__":
    main()
