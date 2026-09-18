"""Canonical conversion settings for the official M-LSD checkpoint variants."""

from dataclasses import dataclass


@dataclass(frozen=True)
class MLSDVariant:
    """Architecture and tensor dimensions shared by the research tools."""

    name: str
    input_size: int
    map_size: int
    backbone_type: str

    @property
    def family(self) -> str:
        return self.name.split("-", maxsplit=1)[1]

    @property
    def upstream_name(self) -> str:
        return f"M-LSD_{self.input_size}_{self.family}"

    @property
    def checkpoint_directory_name(self) -> str:
        return self.upstream_name

    @property
    def tflite_filename(self) -> str:
        return f"{self.upstream_name}_fp32.tflite"

    @property
    def coreml_filename(self) -> str:
        return f"mlsd_{self.input_size}_{self.family}.mlmodel"

    @property
    def coreml_model_name(self) -> str:
        return f"MLSD{self.input_size}{self.family.title()}RGB"


DEFAULT_VARIANT_NAME = "512-tiny"

VARIANTS = {
    "320-tiny": MLSDVariant(
        name="320-tiny",
        input_size=320,
        map_size=160,
        backbone_type="MLSD",
    ),
    "320-large": MLSDVariant(
        name="320-large",
        input_size=320,
        map_size=160,
        backbone_type="MLSD_large",
    ),
    "512-tiny": MLSDVariant(
        name="512-tiny",
        input_size=512,
        map_size=256,
        backbone_type="MLSD",
    ),
    "512-large": MLSDVariant(
        name="512-large",
        input_size=512,
        map_size=256,
        backbone_type="MLSD_large",
    ),
}


def variant_names() -> tuple[str, ...]:
    return tuple(VARIANTS)


def variant_named(name: str) -> MLSDVariant:
    return VARIANTS[name]
