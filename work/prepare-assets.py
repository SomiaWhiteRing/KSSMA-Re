from __future__ import annotations

import hashlib
import shutil
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE_APK = ROOT / "base" / "com.square_enix.million_cn-1.0.0.100.0712.M330.apk"
RESOURCE_ZIP = ROOT / "base" / "com.square_enix.million_cn-140330.zip"
APKTOOL_OUT = ROOT / "work" / "million_cn" / "apktool"
SDCARD_OUT = ROOT / "work" / "million_cn" / "sdcard_dump"
ACCEPTED_ASSETS = ROOT / "work" / "accepted-assets"

EXPECTED = {
    BASE_APK: "4F6A854C49D1AF59BB5500828D2BDDA0767F4D6A9FCFA8D4D6E46EA9257C58A7",
    RESOURCE_ZIP: "D311C8FC3152BE328FA36638F2075F01B95A8AAB2DEA47F918DB3101F18D69F5",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def verify_inputs() -> None:
    for path, expected in EXPECTED.items():
        if not path.is_file():
            raise SystemExit(f"missing required file: {path}")
        actual = sha256_file(path)
        if actual != expected:
            raise SystemExit(f"SHA-256 mismatch for {path.name}: got {actual}, expected {expected}")


def extract_apk_inputs() -> None:
    APKTOOL_OUT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(BASE_APK) as apk:
        members = [
            info
            for info in apk.infolist()
            if info.filename.startswith("assets/") or info.filename == "lib/armeabi/librooneyj.so"
        ]
        for info in members:
            apk.extract(info, APKTOOL_OUT)
    for source in ACCEPTED_ASSETS.rglob("*"):
        if source.is_file():
            target = APKTOOL_OUT / "assets" / source.relative_to(ACCEPTED_ASSETS)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)


def extract_resource_dump() -> None:
    # ponytail: the archive is immutable; replacing the generated dump is simpler than auditing stale files.
    if SDCARD_OUT.exists():
        shutil.rmtree(SDCARD_OUT)
    SDCARD_OUT.mkdir(parents=True)
    with zipfile.ZipFile(RESOURCE_ZIP) as resources:
        resources.extractall(SDCARD_OUT)


def main() -> None:
    verify_inputs()
    extract_apk_inputs()
    extract_resource_dump()
    required = [
        APKTOOL_OUT / "assets" / "bundle" / "local_battle_player.xml",
        APKTOOL_OUT / "lib" / "armeabi" / "librooneyj.so",
        SDCARD_OUT
        / "sdcard"
        / "Android"
        / "data"
        / "com.square_enix.million_cn"
        / "files"
        / "save"
        / "appdata"
        / "save_version",
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise SystemExit(f"prepared assets are incomplete: {missing}")
    print(f"apkAssets={APKTOOL_OUT}")
    print(f"sdcardDump={SDCARD_OUT}")
    print("prepare-assets passed")


if __name__ == "__main__":
    main()
