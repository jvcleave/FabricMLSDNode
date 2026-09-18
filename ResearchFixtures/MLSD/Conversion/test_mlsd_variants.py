import unittest

from mlsd_variants import (
    DEFAULT_VARIANT_NAME,
    variant_named,
    variant_names,
)


class MLSDVariantTests(unittest.TestCase):
    def test_default_preserves_verified_production_variant(self):
        self.assertEqual(DEFAULT_VARIANT_NAME, "512-tiny")
        variant = variant_named(DEFAULT_VARIANT_NAME)
        self.assertEqual(variant.coreml_filename, "mlsd_512_tiny.mlmodel")
        self.assertEqual(variant.checkpoint_directory_name, "M-LSD_512_tiny")

    def test_official_variant_tensor_contracts(self):
        expected = {
            "320-tiny": (320, 160, "MLSD"),
            "320-large": (320, 160, "MLSD_large"),
            "512-tiny": (512, 256, "MLSD"),
            "512-large": (512, 256, "MLSD_large"),
        }
        self.assertEqual(set(variant_names()), set(expected))
        for name, contract in expected.items():
            variant = variant_named(name)
            self.assertEqual(
                (variant.input_size, variant.map_size, variant.backbone_type),
                contract,
            )
            self.assertEqual(
                variant.tflite_filename,
                f"{variant.upstream_name}_fp32.tflite",
            )


if __name__ == "__main__":
    unittest.main()
