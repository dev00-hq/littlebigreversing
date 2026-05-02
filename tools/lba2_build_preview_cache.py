from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from lba2_save_loader import (
    DEFAULT_PROFILE_MANIFESTS,
    DEFAULT_SAVE_DIR,
    DEFAULT_SCENE_ROOT,
    LBA2_PALETTE,
    discover_saves,
    load_profile_lookup,
    parse_scene_table,
    scale_to_fit,
)


DEFAULT_OUTPUT_DIR = Path("work") / "lba2_save_loader_previews"
PREVIEW_SIZE = (400, 300)


def render_preview(embedded_image: bytes, size: tuple[int, int]) -> Image.Image:
    image = Image.frombytes("P", (160, 120), embedded_image)
    if LBA2_PALETTE is not None:
        image.putpalette(LBA2_PALETTE)
        image = image.convert("RGB")
    else:
        image = image.convert("L").convert("RGB")
    scaled = scale_to_fit(image, size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", size, "#eee9df")
    canvas.paste(scaled, ((size[0] - scaled.width) // 2, (size[1] - scaled.height) // 2))
    return canvas


def build_preview_cache(save_dir: Path, scene_root: Path, output_dir: Path, size: tuple[int, int]) -> int:
    output_dir.mkdir(parents=True, exist_ok=True)
    entries = discover_saves(save_dir, parse_scene_table(scene_root), load_profile_lookup(DEFAULT_PROFILE_MANIFESTS))
    written = 0
    for entry in entries:
        if entry.embedded_image is None:
            continue
        output_path = output_dir / f"{entry.path.stem}.png"
        render_preview(entry.embedded_image, size).save(output_path)
        written += 1
    return written


def parse_size(value: str) -> tuple[int, int]:
    parts = value.lower().split("x", 1)
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("size must be WIDTHxHEIGHT")
    try:
        width = int(parts[0])
        height = int(parts[1])
    except ValueError as error:
        raise argparse.ArgumentTypeError("size must be WIDTHxHEIGHT") from error
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("width and height must be positive")
    return width, height


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build enlarged PNG previews from LBA2 save embedded thumbnails.")
    parser.add_argument("--save-dir", type=Path, default=DEFAULT_SAVE_DIR, help="LBA2 SAVE folder.")
    parser.add_argument("--scene-root", type=Path, default=DEFAULT_SCENE_ROOT, help="IdaJS scene TypeScript root.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT_DIR, help="Output folder for generated PNG previews.")
    parser.add_argument("--size", type=parse_size, default=PREVIEW_SIZE, help="Preview size as WIDTHxHEIGHT.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    written = build_preview_cache(args.save_dir, args.scene_root, args.out, args.size)
    print(f"wrote {written} preview(s) to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
