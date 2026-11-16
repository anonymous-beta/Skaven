
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets"
LOGO = ASSET_DIR / "logo.png"

ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"

ASSET_DIR.mkdir(parents=True, exist_ok=True)


def create_placeholder():
    size = 1024
    image = Image.new("RGBA", (size, size), (9, 9, 9, 255))
    draw = ImageDraw.Draw(image)

    draw.rounded_rectangle(
        (65, 65, 959, 959),
        radius=220,
        fill=(21, 21, 21, 255),
        outline=(255, 87, 34, 255),
        width=28,
    )

    draw.polygon(
        [
            (512, 170),
            (740, 350),
            (690, 710),
            (512, 850),
            (334, 710),
            (284, 350),
        ],
        fill=(229, 28, 35, 255),
    )

    draw.polygon(
        [
            (365, 430),
            (455, 465),
            (512, 410),
            (569, 465),
            (659, 430),
            (610, 590),
            (512, 660),
            (414, 590),
        ],
        fill=(9, 9, 9, 255),
    )

    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 160)
    except OSError:
        font = ImageFont.load_default()

    text = "S"
    bounds = draw.textbbox((0, 0), text, font=font)
    width = bounds[2] - bounds[0]
    draw.text(
        ((size - width) / 2, 690),
        text,
        font=font,
        fill=(255, 255, 255, 255),
    )

    image.save(LOGO)


def load_logo():
    if not LOGO.exists():
        print("No assets/logo.png supplied. Creating temporary SKAVEN icon.")
        create_placeholder()

    return Image.open(LOGO).convert("RGBA")


def generate():
    logo = load_logo()

    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }

    for folder, pixels in densities.items():
        destination = ANDROID_RES / folder
        destination.mkdir(parents=True, exist_ok=True)

        resized = ImageOps.fit(
            logo,
            (pixels, pixels),
            method=Image.Resampling.LANCZOS,
        )

        resized.save(destination / "ic_launcher.png")

    print("SKAVEN launcher icons generated.")


if __name__ == "__main__":
    generate()
