# M-LSD Research Fixtures

This directory pins the M-LSD Apple-runtime research inputs and independent
reference. The verified Core ML conversion and upstream Apache-2.0 license are
also copied into the `MLSDStructuralLineKit` runtime target.

- `PROVENANCE.md` records the official source/checkpoint pins, model contract,
  license review, variant comparison, conversion decision, parity, and timing.
- `Models/M-LSD_512_tiny_fp32.tflite` is the official comparison artifact.
- `Models/mlsd_512_tiny.mlmodel` is the verified Core ML conversion with an RGB
  image input and named production outputs.
- `Reference/city-reference.json` contains deterministic official-output hashes,
  selected segments, threshold counts, and Core ML CPU parity.
- `Previews/city-28s-lines.png` visualizes the retained `0.05` city segments.
- `Conversion/` contains the conversion and reference-generation scripts.

The scripts require a separate research Python environment with TensorFlow
2.12.0, Core ML Tools 9.0, OpenCV, NumPy, and Pillow. Runtime MESS code must not
depend on Python, TensorFlow, or TFLite.

`Sources/` contains the two city stills used by the pinned reference and the
package's end-to-end analyzer test.
