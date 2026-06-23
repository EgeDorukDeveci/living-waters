from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
FISH_DIR = ROOT / "assets" / "sprites" / "fish"
SCAPE_DIR = ROOT / "assets" / "sprites" / "scape"
SCALE = 4


def rgba(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def lighten(color: tuple[int, int, int, int], amount: float) -> tuple[int, int, int, int]:
    r, g, b, a = color
    return (
        min(255, int(r + (255 - r) * amount)),
        min(255, int(g + (255 - g) * amount)),
        min(255, int(b + (255 - b) * amount)),
        a,
    )


def darken(color: tuple[int, int, int, int], amount: float) -> tuple[int, int, int, int]:
    r, g, b, a = color
    return (max(0, int(r * (1 - amount))), max(0, int(g * (1 - amount))), max(0, int(b * (1 - amount))), a)


def canvas(size: tuple[int, int]) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (size[0] * SCALE, size[1] * SCALE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = image.resize((image.width // SCALE, image.height // SCALE), Image.Resampling.LANCZOS)
    image.save(path)


def pts(items: list[tuple[float, float]]) -> list[tuple[int, int]]:
    return [(int(x * SCALE), int(y * SCALE)) for x, y in items]


def ellipse(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], fill, outline=None, width: int = 1) -> None:
    scaled = tuple(int(v * SCALE) for v in box)
    draw.ellipse(scaled, fill=fill, outline=outline, width=width * SCALE)


def polygon(draw: ImageDraw.ImageDraw, points: list[tuple[float, float]], fill, outline=None) -> None:
    draw.polygon(pts(points), fill=fill, outline=outline)


def line(draw: ImageDraw.ImageDraw, points: list[tuple[float, float]], fill, width: int = 1) -> None:
    draw.line(pts(points), fill=fill, width=width * SCALE, joint="curve")


def eye(draw: ImageDraw.ImageDraw, x: float, y: float) -> None:
    ellipse(draw, (x - 3, y - 3, x + 3, y + 3), rgba("#f8faf7"))
    ellipse(draw, (x - 0.5, y - 0.5, x + 1.5, y + 1.5), rgba("#11191b"))


def fish_base(draw: ImageDraw.ImageDraw, body: tuple[int, int, int, int], accent: tuple[int, int, int, int]) -> None:
    polygon(draw, [(56, 64), (42, 42), (22, 34), (33, 64), (22, 94), (42, 86)], accent)
    ellipse(draw, (42, 42, 202, 88), body, outline=darken(body, 0.22), width=2)
    polygon(draw, [(144, 46), (103, 28), (78, 44)], lighten(body, 0.08))
    polygon(draw, [(112, 82), (76, 103), (140, 88)], darken(body, 0.08))
    eye(draw, 180, 58)


def make_neon_tetra() -> Image.Image:
    image, draw = canvas((256, 128))
    fish_base(draw, rgba("#3ba8c9"), rgba("#d95755"))
    line(draw, [(67, 55), (175, 51)], rgba("#8ceeff"), 5)
    line(draw, [(64, 69), (132, 72)], rgba("#e45b5b"), 5)
    return image


def make_betta() -> Image.Image:
    image, draw = canvas((256, 128))
    body = rgba("#2f62bf")
    accent = rgba("#e14c61")
    polygon(draw, [(66, 64), (17, 22), (35, 64), (17, 108)], lighten(accent, 0.08))
    polygon(draw, [(69, 62), (31, 39), (38, 64), (31, 91)], accent)
    ellipse(draw, (62, 39, 199, 91), body, outline=darken(body, 0.18), width=2)
    line(draw, [(91, 82), (119, 106), (150, 89)], lighten(accent, 0.15), 5)
    line(draw, [(93, 45), (132, 25), (165, 42)], lighten(accent, 0.1), 4)
    eye(draw, 178, 56)
    return image


def make_danio() -> Image.Image:
    image, draw = canvas((256, 128))
    body = rgba("#cdd5c8")
    accent = rgba("#29364a")
    fish_base(draw, body, accent)
    for y in (50, 57, 64, 71):
        line(draw, [(62, y), (178, y + 2)], accent, 3)
    return image


def make_cory() -> Image.Image:
    image, draw = canvas((256, 128))
    body = rgba("#aaa58c")
    accent = rgba("#484d46")
    polygon(draw, [(57, 70), (27, 51), (28, 93)], accent)
    ellipse(draw, (42, 47, 206, 96), body, outline=darken(body, 0.25), width=2)
    polygon(draw, [(110, 48), (134, 26), (151, 51)], lighten(body, 0.08))
    for index, x in enumerate((78, 94, 112, 132, 151, 168)):
        ellipse(draw, (x - 4, 58 + math.sin(index) * 8 - 4, x + 4, 58 + math.sin(index) * 8 + 4), accent)
    line(draw, [(186, 71), (219, 82)], accent, 2)
    line(draw, [(186, 73), (219, 62)], accent, 2)
    eye(draw, 182, 59)
    return image


def make_shrimp() -> Image.Image:
    image, draw = canvas((256, 128))
    body = rgba("#d94d42")
    accent = rgba("#ff907c")
    for offset in range(5):
        ellipse(draw, (66 + offset * 16, 49 - offset * 3, 102 + offset * 16, 79 - offset * 2), lighten(body, offset * 0.04), outline=darken(body, 0.18), width=1)
    ellipse(draw, (142, 43, 169, 67), lighten(body, 0.09))
    for x in (80, 96, 112, 128, 144):
        line(draw, [(x, 77), (x + 8, 96)], darken(body, 0.12), 2)
    line(draw, [(163, 49), (204, 31)], accent, 2)
    line(draw, [(163, 53), (205, 52)], accent, 2)
    ellipse(draw, (157, 49, 161, 53), rgba("#171d1e"))
    return image


def make_rasbora() -> Image.Image:
    image, draw = canvas((256, 128))
    body = rgba("#ed9146")
    accent = rgba("#171b21")
    fish_base(draw, body, darken(body, 0.18))
    polygon(draw, [(96, 52), (174, 59), (139, 81), (78, 72)], accent)
    return image


def make_guppy() -> Image.Image:
    image, draw = canvas((256, 128))
    body = rgba("#50bed5")
    accent = rgba("#f5b14d")
    polygon(draw, [(69, 64), (18, 28), (31, 64), (18, 100)], accent)
    ellipse(draw, (65, 47, 186, 82), body, outline=darken(body, 0.2), width=2)
    for spot in ((91, 59), (118, 68), (146, 55)):
        ellipse(draw, (spot[0] - 4, spot[1] - 4, spot[0] + 4, spot[1] + 4), lighten(accent, 0.08))
    eye(draw, 166, 57)
    return image


def make_gourami() -> Image.Image:
    image, draw = canvas((256, 128))
    body = rgba("#efad48")
    accent = rgba("#6b3d1f")
    fish_base(draw, body, accent)
    line(draw, [(139, 82), (149, 117)], accent, 2)
    line(draw, [(152, 81), (169, 111)], accent, 2)
    line(draw, [(82, 52), (155, 56)], lighten(body, 0.18), 3)
    return image


def make_loach() -> Image.Image:
    image, draw = canvas((256, 128))
    body = rgba("#c99a52")
    accent = rgba("#332018")
    top = []
    bottom = []
    for i in range(18):
        ratio = i / 17
        x = 35 + ratio * 184
        wave = math.sin(ratio * math.tau * 1.4) * 8
        thick = 8 + math.sin(ratio * math.pi) * 12
        top.append((x, 64 + wave - thick))
        bottom.insert(0, (x, 64 + wave + thick))
    polygon(draw, top + bottom, body, outline=darken(body, 0.22))
    for x in (62, 87, 113, 141, 168, 194):
        line(draw, [(x, 48), (x - 6, 79)], accent, 6)
    eye(draw, 204, 56)
    return image


def make_rock(kind: str, color: str) -> Image.Image:
    image, draw = canvas((256, 256))
    base = rgba(color)
    polygon(draw, [(52, 176), (82, 102), (134, 62), (196, 94), (219, 171), (174, 209), (89, 212)], base, darken(base, 0.25))
    polygon(draw, [(82, 102), (134, 62), (130, 145), (52, 176)], lighten(base, 0.12))
    polygon(draw, [(130, 145), (196, 94), (219, 171), (174, 209)], darken(base, 0.12))
    if kind == "moss":
        for x, y in [(92, 107), (117, 83), (161, 101), (78, 155)]:
            ellipse(draw, (x - 14, y - 8, x + 18, y + 11), rgba("#5f9b55", 210))
    return image


def make_driftwood(root: bool = False) -> Image.Image:
    image, draw = canvas((256, 256))
    color = rgba("#6a422d")
    lines = [
        [(32, 179), (89, 139), (152, 113), (225, 83)],
        [(72, 160), (107, 105), (126, 57)],
        [(112, 132), (170, 157), (221, 188)],
    ]
    if root:
        lines.extend([[(79, 171), (44, 213), (24, 236)], [(120, 145), (97, 204), (83, 238)]])
    for branch in lines:
        line(draw, branch, darken(color, 0.25), 15)
        line(draw, branch, color, 9)
        line(draw, branch, lighten(color, 0.16), 2)
    return image


def make_plant(kind: str) -> Image.Image:
    image, draw = canvas((256, 256))
    if kind == "hairgrass":
        for i in range(42):
            x = 34 + (i * 13) % 188
            h = 32 + (i * 17) % 62
            line(draw, [(x, 215), (x + math.sin(i) * 8, 215 - h)], rgba("#62bd72"), 3)
    elif kind == "vallisneria":
        for i in range(22):
            x = 44 + i * 8
            h = 92 + (i * 19) % 94
            line(draw, [(x, 224), (x + math.sin(i) * 18, 224 - h)], rgba("#76c878"), 5)
    elif kind == "floaters":
        for i in range(16):
            x = 45 + (i * 33) % 164
            y = 48 + (i * 17) % 82
            ellipse(draw, (x - 13, y - 7, x + 13, y + 7), rgba("#7abf68"))
            line(draw, [(x, y + 6), (x + math.sin(i) * 9, y + 47)], rgba("#c5686a"), 2)
    else:
        center = (128, 205)
        color = rgba("#4d9b5e") if kind == "fern" else rgba("#3f8758")
        for i in range(12):
            angle = -math.pi * 0.92 + i * math.pi / 11
            length = 62 if kind == "fern" else 44
            tip = (center[0] + math.cos(angle) * length, center[1] + math.sin(angle) * length * 1.4)
            line(draw, [center, tip], darken(color, 0.1), 4)
            ellipse(draw, (tip[0] - 13, tip[1] - 8, tip[0] + 13, tip[1] + 8), lighten(color, 0.08))
    return image


def main() -> int:
    fish = {
        "neon_tetra": make_neon_tetra,
        "betta_splendens": make_betta,
        "zebra_danio": make_danio,
        "peppered_cory": make_cory,
        "cherry_shrimp": make_shrimp,
        "harlequin_rasbora": make_rasbora,
        "fancy_guppy": make_guppy,
        "honey_gourami": make_gourami,
        "kuhli_loach": make_loach,
    }
    for name, maker in fish.items():
        save(maker().filter(ImageFilter.UnsharpMask(radius=0.8, percent=80, threshold=2)), FISH_DIR / f"{name}.png")

    save(make_rock("river", "#52625c"), SCAPE_DIR / "river_stone.png")
    save(make_rock("moss", "#566a56"), SCAPE_DIR / "moss_stone.png")
    save(make_rock("dragon", "#786d58"), SCAPE_DIR / "dragon_stone.png")
    save(make_driftwood(False), SCAPE_DIR / "branch_driftwood.png")
    save(make_driftwood(True), SCAPE_DIR / "root_driftwood.png")
    save(make_plant("hairgrass"), SCAPE_DIR / "dwarf_hairgrass.png")
    save(make_plant("fern"), SCAPE_DIR / "java_fern.png")
    save(make_plant("anubias"), SCAPE_DIR / "anubias.png")
    save(make_plant("vallisneria"), SCAPE_DIR / "vallisneria.png")
    save(make_plant("floaters"), SCAPE_DIR / "red_root_floaters.png")
    print(f"Wrote sprites to {FISH_DIR} and {SCAPE_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
