from __future__ import annotations

import hashlib
import json
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SAVE_ROOT = (
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
)
RESOURCE_ZIP = ROOT / "base" / "com.square_enix.million_cn-140330.zip"
OUT_DIR = ROOT / "work" / "mumu-a12-package"
OUT_TAR = OUT_DIR / "KSSMA-Re-static-resources.tar"
OUT_CHECKSUMS = OUT_DIR / "KSSMA-Re-static-resources.sha256"
OUT_MANIFEST = OUT_DIR / "resource-pack.json"

EXPECTED_RESOURCE_ZIP_SHA256 = "D311C8FC3152BE328FA36638F2075F01B95A8AAB2DEA47F918DB3101F18D69F5"
INCLUDED_ROOTS = (
    Path("appdata/save_version"),
    Path("database"),
    Path("download"),
)
EXCLUDED_MUTABLE = ("appdata/save_appdata",)
SENTINELS = (
    "appdata/save_version",
    "database/master_boss",
    "download/rest/treasurebox",
    "download/scenario/scsc_1010101",
    "download/pack/gacha/gacha_cp_button",
    "download/image/adv/adv_avalon_attack",
    "download/sound/bgm_battle1.ogg",
    "download/voice/203/vos_203_EA0301_0010.ogg",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def iter_payload_files() -> list[tuple[str, Path]]:
    rows: list[tuple[str, Path]] = []
    for relative_root in INCLUDED_ROOTS:
        source = SAVE_ROOT / relative_root
        if not source.exists():
            raise SystemExit(f"missing prepared resource input: {source}")
        candidates = [source] if source.is_file() else source.rglob("*")
        for path in candidates:
            if not path.is_file():
                continue
            relative = path.relative_to(SAVE_ROOT).as_posix()
            if relative in EXCLUDED_MUTABLE:
                continue
            if "\n" in relative or "\r" in relative:
                raise SystemExit(f"resource path contains a newline: {relative!r}")
            rows.append((relative, path))
    rows.sort(key=lambda item: item[0])
    if not rows:
        raise SystemExit(f"no static resources found under {SAVE_ROOT}")
    return rows


def require_prepared_inputs(rows: list[tuple[str, Path]]) -> None:
    if sha256_file(RESOURCE_ZIP) != EXPECTED_RESOURCE_ZIP_SHA256:
        raise SystemExit(f"resource ZIP hash mismatch: {RESOURCE_ZIP}")
    names = {relative for relative, _ in rows}
    missing = [relative for relative in SENTINELS if relative not in names]
    if missing:
        raise SystemExit(
            "prepared resources are incomplete; run prepare-assets.py and "
            f"extract-gacha-pack-resources.py first: {missing}"
        )


def build_pack(rows: list[tuple[str, Path]]) -> tuple[list[dict[str, object]], int]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    temporary_tar = OUT_TAR.with_suffix(f".{OUT_TAR.suffix.lstrip('.')}.tmp")
    temporary_sums = OUT_CHECKSUMS.with_suffix(f".{OUT_CHECKSUMS.suffix.lstrip('.')}.tmp")
    temporary_manifest = OUT_MANIFEST.with_suffix(f".{OUT_MANIFEST.suffix.lstrip('.')}.tmp")
    for temporary in (temporary_tar, temporary_sums, temporary_manifest):
        temporary.unlink(missing_ok=True)

    records: list[dict[str, object]] = []
    payload_bytes = 0
    try:
        with tarfile.open(temporary_tar, "w", format=tarfile.PAX_FORMAT) as archive:
            for relative, source in rows:
                size = source.stat().st_size
                digest = sha256_file(source)
                payload_bytes += size
                records.append({"path": relative, "bytes": size, "sha256": digest})

                info = tarfile.TarInfo(relative)
                info.size = size
                info.mode = 0o644
                info.mtime = 0
                info.uid = 0
                info.gid = 0
                info.uname = ""
                info.gname = ""
                with source.open("rb") as handle:
                    archive.addfile(info, handle)

        checksum_text = "".join(f"{record['sha256']}  {record['path']}\n" for record in records)
        temporary_sums.write_text(checksum_text, encoding="ascii", newline="\n")

        sentinel_records = [record for record in records if record["path"] in SENTINELS]
        manifest = {
            "schema": 1,
            "purpose": "Static external-storage payload for the MuMu Android 12 KSSMA-Re runtime.",
            "package": "com.square_enix.million_cn",
            "deviceSaveDir": "/storage/emulated/0/Android/data/com.square_enix.million_cn/files/save",
            "resourceZip": {
                "path": RESOURCE_ZIP.relative_to(ROOT).as_posix(),
                "sha256": EXPECTED_RESOURCE_ZIP_SHA256,
            },
            "resourcePack": {
                "path": OUT_TAR.relative_to(ROOT).as_posix(),
                "sha256": sha256_file(temporary_tar),
                "bytes": temporary_tar.stat().st_size,
                "fileCount": len(records),
                "payloadBytes": payload_bytes,
            },
            "checksums": {
                "path": OUT_CHECKSUMS.relative_to(ROOT).as_posix(),
                "sha256": sha256_file(temporary_sums),
                "bytes": temporary_sums.stat().st_size,
            },
            "includedRoots": [path.as_posix() for path in INCLUDED_ROOTS],
            "excludedMutable": list(EXCLUDED_MUTABLE),
            "sentinels": sentinel_records,
        }
        temporary_manifest.write_text(json.dumps(manifest, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")

        temporary_tar.replace(OUT_TAR)
        temporary_sums.replace(OUT_CHECKSUMS)
        temporary_manifest.replace(OUT_MANIFEST)
        return records, payload_bytes
    finally:
        for temporary in (temporary_tar, temporary_sums, temporary_manifest):
            temporary.unlink(missing_ok=True)


def main() -> None:
    rows = iter_payload_files()
    require_prepared_inputs(rows)
    records, payload_bytes = build_pack(rows)
    manifest = json.loads(OUT_MANIFEST.read_text(encoding="utf-8"))
    print(f"resourcePack={OUT_TAR}")
    print(f"checksums={OUT_CHECKSUMS}")
    print(f"manifest={OUT_MANIFEST}")
    print(f"fileCount={len(records)}")
    print(f"payloadBytes={payload_bytes}")
    print(f"packSha256={manifest['resourcePack']['sha256']}")


if __name__ == "__main__":
    main()
