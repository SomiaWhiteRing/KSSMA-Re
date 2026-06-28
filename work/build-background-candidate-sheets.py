from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad
from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SAVE_DOWNLOAD = (
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
)
OUT_DIR = ROOT / "work" / "background-candidates"
KEY = b"A1dPUcrvur2CRQyl"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


@dataclass
class PngEntry:
    index: int
    rel: str
    key: str
    basename: str
    directory: str
    width: int
    height: int
    encrypted_bytes: int
    png_bytes: int
    background_like: bool


def decrypt_resource(path: Path) -> bytes:
    data = path.read_bytes()
    raw = AES.new(KEY, AES.MODE_ECB).decrypt(data)
    return unpad(raw, 16)


def natural_key(text: str) -> list[object]:
    return [int(chunk) if chunk.isdigit() else chunk.lower() for chunk in re.split(r"(\d+)", text)]


def resource_key(rel: str) -> str:
    parts = rel.split("/")
    if parts[0] == "rest" and len(parts) == 2:
        return parts[1]
    return rel


def short_label(entry: PngEntry) -> str:
    label = entry.key
    return label if len(label) <= 31 else f"...{label[-28:]}"


def text_width(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> int:
    left, _, right, _ = draw.textbbox((0, 0), text, font=font)
    return right - left


def write_tsv(path: Path, entries: list[PngEntry]) -> None:
    lines = [
        "index\trel\tkey\tbasename\tdirectory\twidth\theight\tencrypted_bytes\tpng_bytes\tbackground_like"
    ]
    for entry in entries:
        lines.append(
            "\t".join(
                [
                    str(entry.index),
                    entry.rel,
                    entry.key,
                    entry.basename,
                    entry.directory,
                    str(entry.width),
                    str(entry.height),
                    str(entry.encrypted_bytes),
                    str(entry.png_bytes),
                    "1" if entry.background_like else "0",
                ]
            )
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_sheet(
    *,
    entries: list[PngEntry],
    decoded_by_rel: dict[str, bytes],
    out_dir: Path,
    prefix: str,
    page_size: int,
    thumb_w: int,
    thumb_h: int,
    cols: int,
) -> list[str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default()
    label_h = 34
    pad = 10
    cell_w = thumb_w + pad * 2
    cell_h = thumb_h + label_h + pad * 2
    rows = (page_size + cols - 1) // cols
    written: list[str] = []

    for page, start in enumerate(range(0, len(entries), page_size), 1):
        page_entries = entries[start : start + page_size]
        sheet = Image.new("RGB", (cell_w * cols, cell_h * rows), "white")
        draw = ImageDraw.Draw(sheet)
        for slot, entry in enumerate(page_entries):
            x = (slot % cols) * cell_w + pad
            y = (slot // cols) * cell_h + pad
            with Image.open(BytesIO(decoded_by_rel[entry.rel])) as image:
                image = image.convert("RGB")
                thumb = ImageOps.contain(image, (thumb_w, thumb_h), method=Image.Resampling.LANCZOS)
            frame = Image.new("RGB", (thumb_w, thumb_h), (238, 238, 238))
            frame.paste(thumb, ((thumb_w - thumb.width) // 2, (thumb_h - thumb.height) // 2))
            sheet.paste(frame, (x, y))

            first = f"{entry.index}: {short_label(entry)}"
            second = f"{entry.width}x{entry.height}"
            if text_width(draw, first, font) > thumb_w:
                first = first[:42]
            draw.text((x, y + thumb_h + 3), first, fill=(0, 0, 0), font=font)
            draw.text((x, y + thumb_h + 17), second, fill=(80, 80, 80), font=font)

        out_path = out_dir / f"{prefix}-{page:03d}.png"
        sheet.save(out_path)
        written.append(out_path.relative_to(ROOT).as_posix())
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description="Build candidate background manifests and contact sheets.")
    parser.add_argument("--out", type=Path, default=OUT_DIR)
    parser.add_argument("--min-width", type=int, default=600)
    parser.add_argument("--min-height", type=int, default=400)
    parser.add_argument("--page-size", type=int, default=48)
    args = parser.parse_args()

    if not SAVE_DOWNLOAD.exists():
        raise SystemExit(f"missing save/download dump: {SAVE_DOWNLOAD}")

    known_encrypted = SAVE_DOWNLOAD / "pack" / "mainbg" / "mainbg_an_0_0"
    known_decoded = ROOT / "work" / "decrypted-mainbg" / "mainbg_an_0_0.png"
    if known_encrypted.exists() and known_decoded.exists():
        if decrypt_resource(known_encrypted) != known_decoded.read_bytes():
            raise SystemExit("decode self-check failed for mainbg_an_0_0")

    args.out.mkdir(parents=True, exist_ok=True)
    png_entries: list[PngEntry] = []
    decoded_by_rel: dict[str, bytes] = {}
    failures: list[dict[str, str]] = []

    for path in sorted((p for p in SAVE_DOWNLOAD.rglob("*") if p.is_file()), key=lambda p: natural_key(p.relative_to(SAVE_DOWNLOAD).as_posix())):
        rel = path.relative_to(SAVE_DOWNLOAD).as_posix()
        try:
            decoded = decrypt_resource(path)
            if not decoded.startswith(PNG_MAGIC):
                continue
            with Image.open(BytesIO(decoded)) as image:
                width, height = image.size
        except Exception as exc:  # ponytail: diagnostics only; invalid/non-PNG resources are not actionable here.
            failures.append({"rel": rel, "error": f"{type(exc).__name__}: {exc}"})
            continue

        entry = PngEntry(
            index=len(png_entries) + 1,
            rel=rel,
            key=resource_key(rel),
            basename=path.name,
            directory=str(path.relative_to(SAVE_DOWNLOAD).parent).replace("\\", "/"),
            width=width,
            height=height,
            encrypted_bytes=path.stat().st_size,
            png_bytes=len(decoded),
            background_like=width >= args.min_width and height >= args.min_height,
        )
        png_entries.append(entry)
        if entry.background_like:
            decoded_by_rel[entry.rel] = decoded

    background_entries = [entry for entry in png_entries if entry.background_like]
    adv_bg_entries = [entry for entry in background_entries if entry.rel.startswith("image/adv/adv_bg")]
    rest_background_entries = [entry for entry in background_entries if entry.rel.startswith("rest/")]

    write_tsv(args.out / "all-png.tsv", png_entries)
    write_tsv(args.out / "background-like.tsv", background_entries)
    write_tsv(args.out / "adv-bg.tsv", adv_bg_entries)
    write_tsv(args.out / "rest-background-like.tsv", rest_background_entries)

    sheets_dir = args.out / "sheets"
    background_sheets = make_sheet(
        entries=background_entries,
        decoded_by_rel=decoded_by_rel,
        out_dir=sheets_dir,
        prefix="background-like",
        page_size=args.page_size,
        thumb_w=180,
        thumb_h=120,
        cols=8,
    )
    adv_sheets = make_sheet(
        entries=adv_bg_entries,
        decoded_by_rel=decoded_by_rel,
        out_dir=sheets_dir,
        prefix="adv-bg",
        page_size=args.page_size,
        thumb_w=180,
        thumb_h=120,
        cols=8,
    )

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "save_download": SAVE_DOWNLOAD.relative_to(ROOT).as_posix(),
        "min_width": args.min_width,
        "min_height": args.min_height,
        "png_count": len(png_entries),
        "background_like_count": len(background_entries),
        "adv_bg_count": len(adv_bg_entries),
        "rest_background_like_count": len(rest_background_entries),
        "failures_count": len(failures),
        "background_sheets": background_sheets,
        "adv_sheets": adv_sheets,
        "entries": [asdict(entry) for entry in png_entries],
        "failures": failures,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"png={len(png_entries)}")
    print(f"background_like={len(background_entries)}")
    print(f"adv_bg={len(adv_bg_entries)}")
    print(f"rest_background_like={len(rest_background_entries)}")
    print(f"background_tsv={(args.out / 'background-like.tsv').relative_to(ROOT).as_posix()}")
    print(f"adv_tsv={(args.out / 'adv-bg.tsv').relative_to(ROOT).as_posix()}")
    print(f"sheet_dir={sheets_dir.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
