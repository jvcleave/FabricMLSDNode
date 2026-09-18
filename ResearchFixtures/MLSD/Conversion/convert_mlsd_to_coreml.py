#!/usr/bin/env python3
"""Convert the pinned official M-LSD 512 tiny checkpoint to Core ML."""

import argparse
import sys
from pathlib import Path
from types import SimpleNamespace

import coremltools as ct
import tensorflow as tf


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mlsd-repository", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    repository = arguments.mlsd_repository.resolve()
    sys.path.insert(0, str(repository))
    from modules import models  # pylint: disable=import-outside-toplevel

    # The shipped checkpoint completely replaces the ImageNet initialization.
    # Avoid a network download while preserving the official layer topology.
    original_backbone = models.Backbone

    def checkpoint_backbone(
        backbone_type="ResNet50",
        use_pretrain=True,
        post_name="_extractor",
    ):
        del use_pretrain
        return original_backbone(
            backbone_type=backbone_type,
            use_pretrain=False,
            post_name=post_name,
        )

    models.Backbone = checkpoint_backbone

    # The official custom layer builds training-assignment control flow even
    # when conversion requests inference. Freeze it explicitly before tracing.
    def inference_batch_normalization(self, inputs, training=False):
        del training
        return tf.keras.layers.BatchNormalization.call(
            self,
            inputs,
            training=False,
        )

    models.BatchNormalization.call = inference_batch_normalization

    configuration = SimpleNamespace(
        input_size=512,
        backbone_type="MLSD",
        post_name="_extractor",
        out_channel=256,
        dilate=5,
        final_last=False,
        final_act=True,
        final_res1=False,
        final_res2=False,
        residual_type=0,
        type_a_ksize=1,
        map_size=256,
        topk=200,
        final_padding_same=True,
        batch_size=1,
        center_thr=0.001,
        wd=0.0001,
    )
    model = models.WireFrameModel(configuration, training=False)
    checkpoint = tf.train.Checkpoint(
        step=tf.Variable(0, name="step"),
        model=model,
    )
    checkpoint_directory = repository / "ckpt_models" / "M-LSD_512_tiny"
    manager = tf.train.CheckpointManager(
        checkpoint,
        str(checkpoint_directory),
        max_to_keep=3,
    )
    if manager.latest_checkpoint is None:
        raise FileNotFoundError(
            f"Missing M-LSD 512 tiny checkpoint under {checkpoint_directory}"
        )
    status = checkpoint.restore(manager.latest_checkpoint)
    status.expect_partial()
    status.assert_existing_objects_matched()

    inference_model = tf.keras.Model(
        model.input,
        [model.output[-6], model.output[-5], model.output[-7]],
        name="MLSD512TinyRGB",
    )

    @tf.function(
        input_signature=[
            tf.TensorSpec([1, 512, 512, 3], tf.float32, name="image")
        ]
    )
    def infer(image):
        output = inference_model(image, training=False)
        return {
            "center_points": output[0],
            "center_scores": output[1],
            "displacement_map": output[2],
        }

    converted = ct.convert(
        [infer.get_concrete_function()],
        source="tensorflow",
        convert_to="neuralnetwork",
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 512, 512, 3),
                color_layout=ct.colorlayout.RGB,
            )
        ],
        minimum_deployment_target=ct.target.macOS11,
    )
    specification = converted.get_spec()
    ct.utils.rename_feature(specification, "Identity", "center_points")
    ct.utils.rename_feature(specification, "Identity_1", "center_scores")
    ct.utils.rename_feature(specification, "Identity_2", "displacement_map")

    converted = ct.models.MLModel(specification)
    converted.author = "NAVER/LINE Vision; Core ML conversion for MESS"
    converted.license = "Apache-2.0"
    converted.short_description = (
        "M-LSD 512 tiny line-segment detector with in-graph top-200 selection."
    )
    converted.input_description["image"] = "512 x 512 RGB image"
    converted.output_description["center_points"] = (
        "Top-200 center coordinates in [y, x] order on the 256 x 256 map"
    )
    converted.output_description["center_scores"] = "Top-200 center confidences"
    converted.output_description["displacement_map"] = (
        "Endpoint displacements [dx0, dy0, dx1, dy1] on the 256 x 256 map"
    )

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    converted.save(str(arguments.output))


if __name__ == "__main__":
    main()
