# Building M-LSD model variants

This guide covers conversion and validation of the four official M-LSD
checkpoint families at the repository's pinned upstream revision. The shipped
Fabric plug-in still supports only the verified 512-tiny model. Successfully
producing a Core ML file does not make another variant runtime-compatible;
complete the integration and acceptance checklists below before describing one
as supported.

## Pinned inputs and variant matrix

Use `navervision/mlsd` commit
`453cafa09467d0272760578d35c1fda38e8895a5`. The converter defaults to
`512-tiny`, preserving the accepted production path.

| `--variant` | Official checkpoint | Backbone | RGB input | Output map |
| --- | --- | --- | ---: | ---: |
| `320-tiny` | `M-LSD_320_tiny` | `MLSD` | 320 × 320 | 160 × 160 |
| `320-large` | `M-LSD_320_large` | `MLSD_large` | 320 × 320 | 160 × 160 |
| `512-tiny` | `M-LSD_512_tiny` | `MLSD` | 512 × 512 | 256 × 256 |
| `512-large` | `M-LSD_512_large` | `MLSD_large` | 512 × 512 | 256 × 256 |

The official TFLite models return 200 `[y, x]` center points, 200 center scores,
and one four-channel displacement map. The shipping Fabric 512-tiny export
now selects 1,000 candidates from the same learned graph, producing
`[1,1000,2]` centers and `[1,1000]` scores with the displacement map unchanged.
The official TFLite files accept RGBA, but the
alpha-channel convolution weights are zero. This repository's converter emits
an equivalent native RGB Core ML input.

The pinned upstream README mistakenly shows `input_size=512` and
`map_size=256` in its 320-tiny conversion example. Inspection of the shipped
`M-LSD_320_tiny_fp16.tflite` and `M-LSD_320_tiny_fp32.tflite` artifacts confirms
the actual input is `1 × 320 × 320 × 4` and the displacement output is
`1 × 160 × 160 × 4`. The table above records the artifact contract.

## Create the research environment

Python dependencies are conversion tools only. They must not become plug-in or
Swift package dependencies. Python 3.10 is the reproducible baseline used by
these instructions.

From the `FabricMLSDNode` repository root:

```sh
python3.10 -m venv .venv-model-conversion
source .venv-model-conversion/bin/activate
python -m pip install --upgrade pip
python -m pip install \
  -r ResearchFixtures/MLSD/Conversion/requirements-model-conversion.txt
python -c 'import coremltools, tensorflow; print(coremltools.__version__, tensorflow.__version__)'
```

The expected versions are Core ML Tools 9.0 and TensorFlow 2.12.0. The pinned
requirements select `tensorflow-macos` on Apple silicon and the standard
TensorFlow package elsewhere. Core ML prediction and parity verification must
run on macOS even if conversion is performed elsewhere.

Clone and verify the exact upstream source:

```sh
mlsd_upstream=/tmp/navervision-mlsd-453cafa
git clone https://github.com/navervision/mlsd.git "$mlsd_upstream"
git -C "$mlsd_upstream" checkout 453cafa09467d0272760578d35c1fda38e8895a5
test "$(git -C "$mlsd_upstream" rev-parse HEAD)" = \
  453cafa09467d0272760578d35c1fda38e8895a5
```

Retain the upstream Apache License 2.0 file with every redistributed model.
Review upstream licensing again if the source revision or model origin changes.

## Derive the shipping 1,000-candidate artifact

For the verified 512-tiny model, a checkpoint download or TensorFlow conversion
is unnecessary. This graph-only path preserves the accepted backbone exactly:

```sh
python3.10 -m venv .venv-model-conversion
source .venv-model-conversion/bin/activate
python -m pip install coremltools==9.0 numpy==1.23.5 \
  Pillow==10.4.0 opencv-python-headless==4.8.1.78
python ResearchFixtures/MLSD/Conversion/export_candidate_variant.py \
  --candidates 1000 \
  --output /tmp/mlsd-coreml-candidates/mlsd_512_tiny_top1000.mlmodel
python ResearchFixtures/MLSD/Conversion/verify_candidate_variant.py \
  --baseline ResearchFixtures/MLSD/Models/mlsd_512_tiny.mlmodel \
  --candidate /tmp/mlsd-coreml-candidates/mlsd_512_tiny_top1000.mlmodel \
  --fixtures ResearchFixtures/MLSD/Sources/city-28s.png \
    ResearchFixtures/MLSD/Sources/city-sky-control-18s.png \
  --output /tmp/mlsd-coreml-candidates/top1000-parity.json
```

The exporter pins the top-200 baseline hash, changes the single TopK operator's
`K` plus descriptive metadata, and proves the rest of the serialized graph is
identical. It refuses to overwrite the research baseline. Deterministic
protobuf serialization makes the top-1,000 artifact reproducible. The verifier
checks actual 1,000-candidate tensor shapes, exact CPU preservation of the first
200 centers/scores and the whole displacement map, accepted counts at multiple
thresholds, and CPU/GPU warm prediction timings on both fixtures. Timing values
depend on hardware and load; they do not include preprocessing, decoding, or
Fabric rendering. This verifier is specific to the shipping 512-tiny contract.

The shipping resource is `Sources/MLSDStructuralLineKit/Models/mlsd_512_tiny.mlmodel`;
its bytes match the research `Models/mlsd_512_tiny_top1000.mlmodel`. Research
`Models/mlsd_512_tiny.mlmodel` remains the original top-200 baseline.

## Convert a checkpoint

Choose an output outside the production resource directory until validation is
complete:

```sh
mkdir -p /tmp/mlsd-coreml-candidates
python ResearchFixtures/MLSD/Conversion/convert_mlsd_to_coreml.py \
  --mlsd-repository "$mlsd_upstream" \
  --variant 512-tiny \
  --topk 200 \
  --output /tmp/mlsd-coreml-candidates/mlsd_512_tiny.mlmodel
```

Replace `512-tiny` with `320-tiny`, `320-large`, or `512-large` as needed. Use
the `coreml_filename` convention shown by
`ResearchFixtures/MLSD/Conversion/mlsd_variants.py`. Omitting `--variant`
selects `512-tiny`. `--topk` accepts 200, 500, or 1000 and defaults to 1000.
This example explicitly selects 200 to compare against the official TFLite
files below. A fresh TensorFlow conversion is numerically verifiable but is
not expected to have the same artifact hash as the graph-only derivation.

The converter deliberately emits Core ML's legacy `neuralNetwork`
representation. The previous ML Program trial produced invalid numerical
outputs, so changing `convert_to` is a new research task and requires fresh
parity evidence.

The conversion must finish without missing or unmatched checkpoint objects.
Compile the candidate once before parity work:

```sh
xcrun coremlcompiler compile \
  /tmp/mlsd-coreml-candidates/mlsd_512_tiny.mlmodel \
  /tmp/mlsd-coreml-candidates/compiled
```

## Generate independent parity evidence

Use the matching official FP32 TFLite model from the same pinned checkout. Do
not validate against FP16 when deciding whether conversion preserved the source
checkpoint.

```sh
mkdir -p /tmp/mlsd-variant-validation
python ResearchFixtures/MLSD/Conversion/generate_reference.py \
  --variant 512-tiny \
  --tflite "$mlsd_upstream/tflite_models/M-LSD_512_tiny_fp32.tflite" \
  --coreml /tmp/mlsd-coreml-candidates/mlsd_512_tiny.mlmodel \
  --city ResearchFixtures/MLSD/Sources/city-28s.png \
  --sky ResearchFixtures/MLSD/Sources/city-sky-control-18s.png \
  --reference-output /tmp/mlsd-variant-validation/512-tiny.json \
  --preview-output /tmp/mlsd-variant-validation/512-tiny.png
```

Change the variant, TFLite filename, candidate filename, and output filenames
together. The reference tool rejects a TFLite input shape that does not match
the selected variant.

Use CPU-only Core ML results for deterministic acceptance. At minimum, require:

- exact center coordinates on the high-signal city fixture;
- maximum center-score absolute error no greater than `0.0001`;
- maximum whole-map displacement absolute error no greater than `0.1` map
  pixels;
- identical accepted segment counts at every recorded threshold for both
  fixtures; and
- a visual inspection of the generated TFLite preview for preprocessing,
  coordinate, or decoder errors, followed by a Core ML visual check after the
  candidate is integrated into the Swift test path.

Low-information controls can contain nearly tied, unused candidates. For
example, the verified 320-large conversion reordered raw sky-control centers
while retaining identical segment counts at every threshold. Treat such a raw
center mismatch as a required investigation, not an automatic failure, when
score error, displacement error, selected counts, and meaningful geometry
remain within the other gates.

The whole-map displacement limit includes locations that no selected center
uses. The accepted 512-tiny city baseline has `3.94e-6` score error and
`0.01477` map-pixel displacement error; its low-information sky control reaches
about `0.04647` map pixels without changing any selected count. A candidate
outside a limit needs an explicit investigation and newly recorded acceptance
decision; do not relax the limit merely to make a conversion pass.

## Verified conversion-tool coverage

The parameterized converter and reference generator were exercised in a clean
Python 3.10 environment against all four checkpoint families at the pinned
upstream commit. These are CPU results for `city-28s.png` at score `0.05`:

| Variant | Exact centers | Maximum score error | Maximum displacement error | TFLite/Core ML lines |
| --- | --- | ---: | ---: | ---: |
| `320-tiny` | yes | `1.09e-6` | `0.00219` map pixels | 5 / 5 |
| `320-large` | yes | `4.20e-6` | `0.01236` map pixels | 10 / 10 |
| `512-tiny` | yes | `3.93e-6` | `0.01477` map pixels | 46 / 46 |
| `512-large` | yes | `5.33e-6` | `0.01942` map pixels | 45 / 45 |

Both city and sky-control fixtures had identical TFLite/Core ML segment counts
at every recorded threshold for every variant. This validates conversion-tool
coverage; it does not promote the alternate models to supported Swift runtime
artifacts.

## Integrate a validated production artifact

The runtime is intentionally specialized for one model. Replacing it requires
one coherent change rather than copying a new `.mlmodel` over the existing
file.

1. Copy the candidate into `Sources/MLSDStructuralLineKit/Models/` and retain
   a named research copy under `ResearchFixtures/MLSD/Models/`. Keep
   `LICENSE-MLSD.txt` beside the production model and preserve the original
   top-200 research artifact for comparison.
2. Update `ResearchFixtures/MLSD/SHA256SUMS` and record the upstream revision,
   checkpoint, source TFLite hash, converted-model hash, tool versions, parity
   results, and timings in `ResearchFixtures/MLSD/PROVENANCE.md`.
3. Update the model name and expected model hash in
   `MLSDModelResource.swift`. Change the license hash only when the reviewed
   license bytes actually change.
4. Update `MLSDModelMetadata.swift`: input dimensions and the displacement-map
   shape must match the selected variant. Output names and the selected TopK
   shapes must still be verified, not assumed. The current runtime expects
   1,000 candidates.
5. Replace the hard-coded dispatch dimensions and diagnostic label in
   `MLSDTexturePreprocessor.swift` with the selected input dimensions.
6. Update `MLSDDecoder.swift`: center bounds, displacement-map indexing, and
   normalized coordinate scaling depend on map size. The official distance
   threshold remains 20 map pixels, which represents a different fraction of a
   160 map than of a 256 map and therefore needs an explicit product decision.
7. Rename or generalize `StructuralLineLimits.mlsd512Tiny` and every caller.
   The official artifacts retain top-200 selection; custom exports can change
   it without retraining. Keep the runtime's frame, decoder, and node limits
   coherent with the actual produced model.
8. Regenerate the reference JSON and preview, then update decoder fixtures and
   end-to-end expectations in `MLSDStructuralLineAnalyzerTests.swift`.
9. Update public README language so the documented production variant matches
   the bundle.

Supporting multiple selectable models simultaneously is a separate runtime API
and resource-design task. This checklist describes deliberate replacement of
the single production model.

## Performance and final verification

Measure cold loading separately from repeated inference. Record CPU-only for
deterministic parity, then measure `.cpuAndGPU` and `.cpuAndNeuralEngine` on the
same hardware and fixtures. Record segment-count differences near the chosen
confidence threshold because reduced-precision execution can change marginal
candidates.

Before accepting a production replacement, run:

```sh
swift test

xcodebuild \
  -project FabricMLSDNode/FabricMLSDNode.xcodeproj \
  -scheme FabricMLSDNode \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

xcodebuild \
  -project FabricMLSDNode/FabricMLSDNode.xcodeproj \
  -scheme FabricMLSDNode \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

Finally inspect the built `.fabricplugin`, confirm the expected model and
license are embedded, verify their SHA-256 values, and run strict deep code-sign
verification on both the build product and installed plug-in. Preserve the old
artifact and reference data until the replacement has passed every check and
the migration has been reviewed.

After a native plug-in build, exercise the larger arrays and GPU draw with:

```sh
swift scripts/verify_overlay_shader.swift \
  "$HOME/Library/Application Support/Fabric/Plugins/FabricMLSDNode.fabricplugin"
python3 scripts/verify_node_capacity.py \
  --fabric-build .fabric-spm/arm64-apple-macosx/debug \
  --plugin "$HOME/Library/Application Support/Fabric/Plugins/FabricMLSDNode.fabricplugin" \
  --framework-path "/path/to/Fabric Editor.app/Contents/Frameworks"
```

Use the scratch configuration/architecture matching the bundle. The capacity
helper reads that completed native build's description to compile against the
same Fabric module and transitive imports. Supply the Editor framework folder
when its existing runtime dependencies (such as Sparkle via HapInAVFoundation)
are needed by Fabric's dynamic library. It loads only the selected plug-in,
checks Analyze's declared range/default, executes Positions with 1,000 lines
and empty/over-limit transitions, and executes Overlay's full 16 KB GPU upload.
The shader fixture checks that the 1,000th instance actually draws in each
supported presentation orientation.
