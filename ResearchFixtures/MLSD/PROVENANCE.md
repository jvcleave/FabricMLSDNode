# M-LSD Artifact Provenance and Apple Runtime Trial

## Source pin and license

| Item | Pin |
| --- | --- |
| Official implementation | `navervision/mlsd` commit `453cafa09467d0272760578d35c1fda38e8895a5` (2023-07-11) |
| Architecture | `M-LSD_512_tiny`, MobileNetV2-based tiny backbone |
| Official checkpoint | `ckpt_models/M-LSD_512_tiny/ckpt-151` |
| Official comparison model | `tflite_models/M-LSD_512_tiny_fp32.tflite` |
| License | Apache License 2.0, copyright 2021-present NAVER Corp. |

The official repository includes its source, checkpoints, and TFLite models
under one Apache-2.0 license and has no separate `NOTICE` file or model-weight
terms. Redistribution requires retaining the license and applicable attribution.
This is a source review, not legal advice.

Pinned upstream hashes:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `M-LSD_512_tiny_fp32.tflite` | 2,491,732 | `9eea1c32aa599a74d60b74fa62a17993da2ee5eb7666aad27e9795fe8bd08293` |
| `ckpt-151.data-00000-of-00001` | 7,554,850 | `999800e9e6d8d5e90e2269ff892a4b2a82e8bb15517f529d49ced7f963c9240d` |
| `ckpt-151.index` | 31,494 | `3f3b23c158643e820d49f7de7965727675a1fa6385ab9dd92629462083a83364` |
| `checkpoint` | 170 | `fea33320e453ef13be3361f675b130a4f37f27511fb6f01400283257930612ab` |
| `LICENSE` | 11,348 | `b8a6637c19443e6792ce93c37fe1faac3c745e319ffcd90ac8be0a170a9a1900` |

## Model and post-processing contract

The selected model accepts one 512 x 512 RGB image containing raw channel
values in `[0, 255]`. MobileNetV2 normalization is inside the model. The
official TFLite artifact adds an unused alpha channel whose convolution weights
are zero; the Core ML conversion removes that channel without changing RGB
results.

NMS and top-200 selection are already inside the model. Outputs are:

| Output | Runtime shape | Meaning |
| --- | --- | --- |
| `center_points` | `1 x 200 x 2` | integer-valued `[y, x]` centers on a 256 x 256 map |
| `center_scores` | `1 x 200` | sigmoid center confidence, descending |
| `displacement_map` | `1 x 256 x 256 x 4` | `[dx0, dy0, dx1, dy1]` at every map cell |

The remaining line decoder is small: for each selected center, read its four
displacements, reject confidence at or below the selected threshold, reject
endpoint distance at or below 20 map pixels, add each displacement to the
center, multiply map coordinates by two, and scale x/y independently back to
the source dimensions. The official path stretches every source image to a
square rather than letterboxing it. Endpoints are not clipped by the reference.

M-LSD emits disconnected scored segments. It does not provide shared junction
indices or a connected graph; any endpoint merging must be a separate,
explicit geometry step.

## Variant selection

All eight shipped TFLite variants were run with four XNNPACK CPU threads on the
same M1 Max and the exact `city-28s.png` fixture. Counts use score `> 0.05` and
the official displacement-distance threshold `> 20`:

| Variant | Warm inference | City lines |
| --- | ---: | ---: |
| 320 tiny FP16 / FP32 | about 14.4 ms | 5 |
| 320 large FP16 / FP32 | about 77 ms | 10-11 |
| 512 tiny FP16 / FP32 | about 35 ms | 45-46 |
| 512 large FP16 / FP32 | about 193 ms | 45-46 |

The 512 tiny model is the only sensible first runtime candidate: 320 loses most
of the city structure, while 512 large adds no useful lines at roughly five
times the CPU cost. The FP32 source artifact was retained to give conversion
parity an unambiguous reference.

## Core ML conversion

`Conversion/convert_mlsd_to_coreml.py` reconstructs the official graph from the
pinned checkpoint under TensorFlow 2.12.0 and converts it with Core ML Tools
9.0. It disables ImageNet initialization downloads, freezes the custom batch
normalization layer for inference, trims unused training outputs, uses a native
512 x 512 RGB image input, and renames the three production outputs.

The accepted artifact uses Core ML's `neuralNetwork` representation. On the
city fixture with CPU-only execution it exactly preserves all selected center
coordinates and segment counts; maximum score error is `3.94e-6` and maximum
displacement error is `0.01477` map pixels. Its warm local timings were about:

- 37.7 ms with CPU only;
- 4.5 ms with CPU and GPU; and
- 7.3 ms with CPU and Neural Engine.

Hardware execution uses reduced precision internally, so a few candidates near
a threshold can differ. At score `0.05`, the city fixture produced 46 reference
segments, 47 with CPU/GPU, and 48 with CPU/Neural Engine. The prominent lines
and high-confidence ordering remained visually consistent. Deterministic parity
checks therefore use CPU-only execution; production may select GPU or Neural
Engine after loaded MESS evaluation.

An ML Program conversion was also attempted because it would be eligible for
`mpsgraphtool`. Although conversion completed, its outputs were numerically
invalid on the same fixture and produced no accepted lines at score `0.05`.
Apple's current graph converter accepts MIL `.mlpackage` input, not the verified
legacy neural-network `.mlmodel`, so there is no accepted MPSGraph package from
this trial. A direct MPSGraph port remains possible but is not required to meet
the current performance target.

## City fixture result

`Reference/city-reference.json` records official TFLite output fingerprints,
selected endpoints, score-threshold counts, and Core ML CPU parity for the
existing city and sky-control images. At score `0.05`, 46 city segments and
three sky-control segments remain. Lowering the city threshold to `0.025`
retains 76 segments; `0.01` retains 104. The preview uses the 46-line setting.
