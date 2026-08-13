from __future__ import annotations

from io import BytesIO
from pathlib import Path

from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad
from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = (
    ROOT
    / "work"
    / "million_cn"
    / "sdcard_dump"
    / "sdcard"
    / "Android"
    / "data"
    / "com.square_enix.million_cn"
    / "files"
    / "save"
    / "download"
    / "pack"
    / "gacha"
)
OUT_DIR = ROOT / "work" / "gacha-image-preview"
KEY = b"A1dPUcrvur2CRQyl"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def decrypt_resource(path: Path) -> bytes:
    raw = AES.new(KEY, AES.MODE_ECB).decrypt(path.read_bytes())
    return unpad(raw, 16)


def main() -> None:
    if not SOURCE_DIR.exists():
        raise SystemExit(f"missing gacha image source dir: {SOURCE_DIR}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    decoded_dir = OUT_DIR / "decoded"
    decoded_dir.mkdir(parents=True, exist_ok=True)

    entries = []
    for source in sorted(SOURCE_DIR.iterdir(), key=lambda p: p.name):
        if not source.is_file():
            continue
        decoded = decrypt_resource(source)
        if not decoded.startswith(PNG_MAGIC):
            continue
        with Image.open(BytesIO(decoded)) as image:
            width, height = image.size
        out_path = decoded_dir / f"{source.name}.png"
        out_path.write_bytes(decoded)
        entries.append((source.name, out_path, width, height, source.stat().st_size, len(decoded)))

    font = ImageFont.load_default()
    thumb_w = 300
    thumb_h = 140
    pad = 12
    label_h = 42
    cols = 3
    rows = max(1, (len(entries) + cols - 1) // cols)
    sheet = Image.new("RGB", ((thumb_w + pad * 2) * cols, (thumb_h + label_h + pad * 2) * rows), "white")
    draw = ImageDraw.Draw(sheet)
    for index, (name, out_path, width, height, encrypted_bytes, png_bytes) in enumerate(entries):
        col = index % cols
        row = index // cols
        x = col * (thumb_w + pad * 2) + pad
        y = row * (thumb_h + label_h + pad * 2) + pad
        with Image.open(out_path) as image:
            image = image.convert("RGB")
            thumb = ImageOps.contain(image, (thumb_w, thumb_h), method=Image.Resampling.LANCZOS)
        frame = Image.new("RGB", (thumb_w, thumb_h), (238, 238, 238))
        frame.paste(thumb, ((thumb_w - thumb.width) // 2, (thumb_h - thumb.height) // 2))
        sheet.paste(frame, (x, y))
        draw.text((x, y + thumb_h + 4), f"{index + 1}. {name}", fill=(0, 0, 0), font=font)
        draw.text((x, y + thumb_h + 20), f"{width}x{height} enc={encrypted_bytes} png={png_bytes}", fill=(80, 80, 80), font=font)

    sheet_path = OUT_DIR / "gacha-pack-sheet.png"
    sheet.save(sheet_path)

    lines = ["name\twidth\theight\tencrypted_bytes\tpng_bytes\toutput"]
    for name, out_path, width, height, encrypted_bytes, png_bytes in entries:
        lines.append(
            "\t".join(
                [
                    name,
                    str(width),
                    str(height),
                    str(encrypted_bytes),
                    str(png_bytes),
                    out_path.relative_to(ROOT).as_posix(),
                ]
            )
        )
    (OUT_DIR / "manifest.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"decoded={len(entries)}")
    print(f"sheet={sheet_path.relative_to(ROOT).as_posix()}")
    print(f"manifest={(OUT_DIR / 'manifest.tsv').relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
