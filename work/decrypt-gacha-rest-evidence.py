from __future__ import annotations

import binascii
import json
import zlib
from io import BytesIO
from pathlib import Path

from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
REST_DIR = (
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
    / "rest"
)
OUT_DIR = ROOT / "work" / "gacha-rest-decrypt"
K1 = b"A1dPUcrvur2CRQyl"
K2 = b"rBwj1MIAivVN222b"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

# gacha select scene evidence family + one known-good comparison file (main menu gacha button)
TARGETS = [
    "ae_gacha",
    "ae_gacha02",
    "rja_ae_gacha.load",
    "rja_ae_gacha",
    "rja_ae_gacha_slot.load",
    "rja_ae_gacha_slot",
    "11_gacha_banner",
    "11_gacha_banner_event",
    "rja_1000_main_menu_gacha.load",
    "rja_1000_main_menu_gacha",
    "rja_gac_gauge.load",
    "rja_gac_gauge",
]


def parse_load_table(data: bytes) -> list[str] | None:
    if len(data) < 4:
        return None
    count = int.from_bytes(data[:4], "big")
    if count > 256:
        return None
    pos = 4
    names: list[str] = []
    for _ in range(count):
        if pos >= len(data):
            return None
        size = data[pos]
        pos += 1
        if size == 0 or pos + size > len(data):
            return None
        try:
            names.append(data[pos : pos + size].decode("ascii"))
        except UnicodeDecodeError:
            return None
        pos += size
    if pos != len(data):
        return None
    return names


def classify(data: bytes) -> str:
    if data.startswith(PNG_MAGIC):
        return "png"
    if data.startswith(b"\x00AE\x00"):
        return "ae-anm"
    if data[:2] == b"RJ":
        return "rj-pack"
    if data.startswith(b"OggS"):
        return "ogg"
    if parse_load_table(data) is not None:
        return "load-table"
    head = data[:256]
    if head.lstrip()[:1] == b"<":
        return "xml/text"
    printable = sum(1 for b in head if 32 <= b < 127 or b in (9, 10, 13))
    if head and printable / len(head) > 0.85:
        return "ascii-ish"
    if data[:1] == b"\x78":
        try:
            zlib.decompress(data)
            return "zlib"
        except zlib.error:
            pass
    return "unknown"


def try_decrypt(raw: bytes, key: bytes) -> tuple[bytes | None, str]:
    if len(raw) % 16 != 0:
        return None, "size-not-block-aligned"
    plain = AES.new(key, AES.MODE_ECB).decrypt(raw)
    try:
        return unpad(plain, 16), "unpad-ok"
    except ValueError:
        return plain, "no-padding"


def png_size(data: bytes) -> str:
    try:
        from PIL import Image

        with Image.open(BytesIO(data)) as im:
            return f"{im.size[0]}x{im.size[1]}"
    except Exception:
        return "?"


def read_png_size(path: Path) -> tuple[int, int] | None:
    if not path.exists():
        return None
    try:
        with Image.open(path) as image:
            return image.size
    except Exception:
        return None


def parse_ae_records(data: bytes, dependencies: list[str]) -> list[dict[str, object]]:
    if not data.startswith(b"\x00AE\x00"):
        return []
    records: list[dict[str, object]] = []
    off = 8
    ordinal = 0
    while off < len(data):
        if off + 8 > len(data):
            raise ValueError(f"truncated record header at 0x{off:x}")
        size = int.from_bytes(data[off : off + 4], "big")
        if size < 8 or off + size > len(data):
            raise ValueError(f"bad record size {size} at 0x{off:x}")
        record = data[off : off + size]
        rec_id = int.from_bytes(record[4:6], "big")
        rec_type = int.from_bytes(record[6:8], "big")
        entry: dict[str, object] = {
            "ordinal": ordinal,
            "offset": off,
            "size": size,
            "id": rec_id,
            "type": rec_type,
        }
        if size >= 12:
            image_marker = int.from_bytes(record[-12:-10], "big")
            image_index = int.from_bytes(record[-10:-8], "big")
            atlas_x = int.from_bytes(record[-8:-6], "big", signed=True)
            atlas_y = int.from_bytes(record[-6:-4], "big", signed=True)
            atlas_w = int.from_bytes(record[-4:-2], "big", signed=True)
            atlas_h = int.from_bytes(record[-2:], "big", signed=True)
            if image_marker == 2 and atlas_w > 0 and atlas_h > 0:
                dependency = dependencies[image_index] if image_index < len(dependencies) else ""
                entry.update(
                    {
                        "imageIndex": image_index,
                        "dependency": dependency,
                        "atlasX": atlas_x,
                        "atlasY": atlas_y,
                        "atlasW": atlas_w,
                        "atlasH": atlas_h,
                    }
                )
        records.append(entry)
        off += size
        ordinal += 1
    expected_count = int.from_bytes(data[6:8], "big")
    if expected_count != len(records):
        raise ValueError(f"record count mismatch header={expected_count} parsed={len(records)}")
    return records


def dependency_png_path(name: str, output_by_name: dict[str, Path]) -> Path | None:
    if not name.endswith(".png"):
        return None
    stem = name[:-4]
    if stem in output_by_name:
        return output_by_name[stem]
    bundled = ROOT / "work" / "million_cn" / "apktool" / "assets" / "bundle" / name
    if bundled.exists():
        return bundled
    return None


def write_sprite_outputs(
    source_name: str,
    records: list[dict[str, object]],
    output_by_name: dict[str, Path],
) -> list[dict[str, object]]:
    sprite_rows: list[dict[str, object]] = []
    sprite_dir = OUT_DIR / f"{source_name.replace('.', '_')}_sprites"
    sprite_dir.mkdir(exist_ok=True)
    for record in records:
        if "dependency" not in record:
            continue
        dependency = str(record["dependency"])
        source_png = dependency_png_path(dependency, output_by_name)
        row = dict(record)
        if source_png and source_png.exists():
            with Image.open(source_png) as image:
                box = (
                    int(record["atlasX"]),
                    int(record["atlasY"]),
                    int(record["atlasX"]) + int(record["atlasW"]),
                    int(record["atlasY"]) + int(record["atlasH"]),
                )
                crop = image.crop(box)
                out = sprite_dir / f"{int(record['ordinal']):02d}_id{int(record['id']):02d}_{Path(dependency).stem}.png"
                crop.save(out)
                row["sprite"] = out.relative_to(ROOT).as_posix()
        sprite_rows.append(row)
    if sprite_rows:
        build_sprite_sheet(source_name, sprite_rows)
    return sprite_rows


def build_sprite_sheet(source_name: str, sprite_rows: list[dict[str, object]]) -> None:
    rows_with_images = [row for row in sprite_rows if "sprite" in row]
    if not rows_with_images:
        return
    font = ImageFont.load_default()
    thumb_w = 180
    thumb_h = 100
    label_h = 48
    pad = 10
    cols = 4
    rows = (len(rows_with_images) + cols - 1) // cols
    sheet = Image.new("RGB", ((thumb_w + pad * 2) * cols, (thumb_h + label_h + pad * 2) * rows), "white")
    draw = ImageDraw.Draw(sheet)
    for index, row in enumerate(rows_with_images):
        col = index % cols
        grid_row = index // cols
        x = col * (thumb_w + pad * 2) + pad
        y = grid_row * (thumb_h + label_h + pad * 2) + pad
        sprite_path = ROOT / str(row["sprite"])
        with Image.open(sprite_path) as image:
            thumb = ImageOps.contain(image.convert("RGBA"), (thumb_w, thumb_h), method=Image.Resampling.LANCZOS)
        frame = Image.new("RGB", (thumb_w, thumb_h), (238, 238, 238))
        frame.paste(Image.new("RGB", thumb.size, "white"), ((thumb_w - thumb.width) // 2, (thumb_h - thumb.height) // 2))
        frame.paste(thumb.convert("RGB"), ((thumb_w - thumb.width) // 2, (thumb_h - thumb.height) // 2), thumb)
        sheet.paste(frame, (x, y))
        label1 = f"#{row['ordinal']} id={row['id']} img={row['imageIndex']}"
        label2 = f"{row['atlasX']},{row['atlasY']} {row['atlasW']}x{row['atlasH']}"
        draw.text((x, y + thumb_h + 4), label1, fill=(0, 0, 0), font=font)
        draw.text((x, y + thumb_h + 20), label2, fill=(80, 80, 80), font=font)
    sheet.save(OUT_DIR / f"{source_name.replace('.', '_')}_sprites_sheet.png")


def read_rj_pack(raw: bytes) -> list[tuple[str, bytes]]:
    count = int.from_bytes(raw[14:18], "big")
    pos = 18
    entries: list[tuple[str, int]] = []
    for _ in range(count):
        name_len = int.from_bytes(raw[pos : pos + 4], "big")
        pos += 4
        name = raw[pos : pos + name_len].decode("ascii", errors="replace")
        pos += name_len
        size = int.from_bytes(raw[pos : pos + 4], "big")
        pos += 4
        entries.append((name, size))
    chunks: list[tuple[str, bytes]] = []
    for name, size in entries:
        marker = raw[pos]
        pos += 1
        if marker != 0x02:
            raise ValueError(f"unexpected chunk marker for {name}: 0x{marker:02x}")
        chunks.append((name, raw[pos : pos + size]))
        pos += size
    if pos != len(raw):
        raise ValueError(f"trailing bytes in pack: {len(raw) - pos}")
    return chunks


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    report_lines = ["file\tsize\tkey\tpad\ttype\tdetail\toutput"]
    outputs: dict[str, dict[str, object]] = {}
    output_by_name: dict[str, Path] = {}
    load_tables: dict[str, list[str]] = {}

    for name in TARGETS:
        src = REST_DIR / name
        if not src.exists():
            report_lines.append(f"{name}\t-\t-\t-\tmissing\t-\t-")
            continue
        raw = src.read_bytes()

        # raw file may already be plaintext
        best = ("none", "-", raw, classify(raw))
        for key_name, key in (("k1", K1), ("k2", K2)):
            plain, pad_state = try_decrypt(raw, key)
            if plain is None:
                continue
            kind = classify(plain)
            if kind != "unknown":
                best = (key_name, pad_state, plain, kind)
                break

        key_name, pad_state, plain, kind = best
        safe = name.replace(".", "_")
        detail = ""
        out_rel = "-"

        if kind == "png":
            out = OUT_DIR / f"{safe}.png"
            out.write_bytes(plain)
            detail = png_size(plain)
            out_rel = out.relative_to(ROOT).as_posix()
            output_by_name[name] = out
            outputs[name] = {"type": kind, "output": out_rel, "detail": detail}
        elif kind == "load-table":
            table = parse_load_table(plain) or []
            out = OUT_DIR / f"{safe}.load.txt"
            out.write_text("\n".join(table) + "\n", encoding="utf-8")
            bin_out = OUT_DIR / f"{safe}.bin"
            bin_out.write_bytes(plain)
            detail = ",".join(table)
            out_rel = out.relative_to(ROOT).as_posix()
            base_name = name[:-5] if name.endswith(".load") else name
            load_tables[base_name] = table
            outputs[name] = {"type": kind, "output": out_rel, "detail": table, "binary": bin_out.relative_to(ROOT).as_posix()}
        elif kind == "ae-anm":
            out = OUT_DIR / f"{safe}.anm.bin"
            out.write_bytes(plain)
            dependencies = load_tables.get(name, [])
            try:
                records = parse_ae_records(plain, dependencies)
                records_out = OUT_DIR / f"{safe}.records.json"
                records_out.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                sprite_rows = write_sprite_outputs(name, records, output_by_name)
                sprites_out = OUT_DIR / f"{safe}.sprites.json"
                sprites_out.write_text(json.dumps(sprite_rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                sprite_count = len(sprite_rows)
                detail = f"records={len(records)},sprites={sprite_count}"
                out_rel = records_out.relative_to(ROOT).as_posix()
            except ValueError as err:
                detail = f"parse-error:{err}"
                out_rel = out.relative_to(ROOT).as_posix()
            outputs[name] = {"type": kind, "output": out_rel, "detail": detail, "binary": out.relative_to(ROOT).as_posix()}
        elif kind == "rj-pack":
            detail_parts = []
            try:
                chunks = read_rj_pack(plain)
                pack_dir = OUT_DIR / safe
                pack_dir.mkdir(exist_ok=True)
                for chunk_name, chunk in chunks:
                    chunk_plain, _ = try_decrypt(chunk, K1)
                    if chunk_plain is not None and chunk_plain.startswith(PNG_MAGIC):
                        (pack_dir / f"{chunk_name}.png").write_bytes(chunk_plain)
                        detail_parts.append(f"{chunk_name}:png:{png_size(chunk_plain)}")
                    else:
                        (pack_dir / f"{chunk_name}.bin").write_bytes(
                            chunk_plain if chunk_plain is not None else chunk
                        )
                        chunk_kind = classify(chunk_plain) if chunk_plain is not None else "raw"
                        detail_parts.append(f"{chunk_name}:{chunk_kind}:{len(chunk)}b")
                out_rel = pack_dir.relative_to(ROOT).as_posix()
            except ValueError as err:
                detail_parts.append(f"pack-parse-error:{err}")
                out = OUT_DIR / f"{safe}.rj.bin"
                out.write_bytes(plain)
                out_rel = out.relative_to(ROOT).as_posix()
            detail = ";".join(detail_parts)
        else:
            out = OUT_DIR / f"{safe}.bin"
            out.write_bytes(plain)
            out_rel = out.relative_to(ROOT).as_posix()
            detail = binascii.hexlify(plain[:32]).decode()
            outputs[name] = {"type": kind, "output": out_rel, "detail": detail}

        report_lines.append(
            f"{name}\t{len(raw)}\t{key_name}\t{pad_state}\t{kind}\t{detail}\t{out_rel}"
        )
        print(report_lines[-1])

    (OUT_DIR / "report.tsv").write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    (OUT_DIR / "manifest.json").write_text(json.dumps(outputs, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"report={(OUT_DIR / 'report.tsv').relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
