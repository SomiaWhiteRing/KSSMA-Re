from __future__ import annotations

from io import BytesIO
from pathlib import Path

from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PACK = ROOT / "work" / "million_cn" / "apktool" / "assets" / "pack" / "161" / "gacha" / "gacha0_1.pack"
OUT_DIR = ROOT / "work" / "gacha-pack-original"
DECODED_DIR = OUT_DIR / "decoded"
SAVE_DOWNLOAD_PACK_GACHA = (
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
KEY = b"A1dPUcrvur2CRQyl"


def decrypt_resource(data: bytes) -> bytes:
    return unpad(AES.new(KEY, AES.MODE_ECB).decrypt(data), 16)


def encrypt_resource(data: bytes) -> bytes:
    return AES.new(KEY, AES.MODE_ECB).encrypt(pad(data, 16))


def read_gacha_pack(path: Path) -> list[tuple[str, bytes]]:
    raw = path.read_bytes()
    if raw[:2] != b"RJ":
        raise SystemExit(f"unexpected pack header: {path}")

    count = int.from_bytes(raw[14:18], "big")
    pos = 18
    entries: list[tuple[str, int]] = []
    for _ in range(count):
        name_len = int.from_bytes(raw[pos : pos + 4], "big")
        pos += 4
        name = raw[pos : pos + name_len].decode("ascii")
        pos += name_len
        size = int.from_bytes(raw[pos : pos + 4], "big")
        pos += 4
        entries.append((name, size))

    unpacked: list[tuple[str, bytes]] = []
    for name, size in entries:
        marker = raw[pos]
        pos += 1
        if marker != 0x02:
            raise SystemExit(f"unexpected chunk marker for {name}: 0x{marker:02x}")
        chunk = raw[pos : pos + size]
        pos += size
        png = decrypt_resource(chunk)
        if not png.startswith(b"\x89PNG\r\n\x1a\n"):
            raise SystemExit(f"decoded resource is not PNG: {name}")
        unpacked.append((name, png))

    if pos != len(raw):
        raise SystemExit(f"trailing bytes in pack: {len(raw) - pos}")
    return unpacked


def build_preview(resources: list[tuple[str, bytes]], manifest_rows: list[tuple[str, int, int, int, int]]) -> None:
    font = ImageFont.load_default()
    thumb_w = 300
    thumb_h = 170
    pad_px = 12
    label_h = 42
    cols = 2
    rows = max(1, (len(resources) + cols - 1) // cols)
    sheet = Image.new("RGB", ((thumb_w + pad_px * 2) * cols, (thumb_h + label_h + pad_px * 2) * rows), "white")
    draw = ImageDraw.Draw(sheet)

    for index, (name, png) in enumerate(resources):
        col = index % cols
        row = index // cols
        x = col * (thumb_w + pad_px * 2) + pad_px
        y = row * (thumb_h + label_h + pad_px * 2) + pad_px
        with Image.open(BytesIO(png)) as image:
            thumb = ImageOps.contain(image.convert("RGB"), (thumb_w, thumb_h), method=Image.Resampling.LANCZOS)
        frame = Image.new("RGB", (thumb_w, thumb_h), (238, 238, 238))
        frame.paste(thumb, ((thumb_w - thumb.width) // 2, (thumb_h - thumb.height) // 2))
        sheet.paste(frame, (x, y))
        _, width, height, encrypted_bytes, png_bytes = manifest_rows[index]
        draw.text((x, y + thumb_h + 4), f"{index + 1}. {name}", fill=(0, 0, 0), font=font)
        draw.text((x, y + thumb_h + 20), f"{width}x{height} enc={encrypted_bytes} png={png_bytes}", fill=(80, 80, 80), font=font)

    sheet.save(OUT_DIR / "sheet.png")


def main() -> None:
    resources = read_gacha_pack(SOURCE_PACK)
    DECODED_DIR.mkdir(parents=True, exist_ok=True)
    SAVE_DOWNLOAD_PACK_GACHA.mkdir(parents=True, exist_ok=True)

    manifest_rows: list[tuple[str, int, int, int, int]] = []
    for name, png in resources:
        with Image.open(BytesIO(png)) as image:
            width, height = image.size
        encrypted = encrypt_resource(png)
        (DECODED_DIR / f"{name}.png").write_bytes(png)
        (SAVE_DOWNLOAD_PACK_GACHA / name).write_bytes(encrypted)
        manifest_rows.append((name, width, height, len(encrypted), len(png)))
        print(f"{name}\t{width}x{height}\t{len(encrypted)} bytes")

    manifest = ["name\twidth\theight\tencrypted_bytes\tpng_bytes"]
    manifest.extend("\t".join(str(value) for value in row) for row in manifest_rows)
    (OUT_DIR / "manifest.tsv").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    build_preview(resources, manifest_rows)
    print(f"sheet={(OUT_DIR / 'sheet.png').relative_to(ROOT).as_posix()}")
    print(f"manifest={(OUT_DIR / 'manifest.tsv').relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
