from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
BASE_APK = REPO / "base" / "com.square_enix.million_cn-1.0.0.100.0712.M330.apk"
ACCEPTED_LIB = ROOT / "librooneyj-exploration-area-return-rerequest.so"
OUT_DIR = ROOT / "client-baseline"
OUT_APK = OUT_DIR / "KSSMA-Re-client-baseline.apk"
MANIFEST = OUT_DIR / "client-baseline.json"
TEMP_UNSIGNED_APK = OUT_DIR / f"KSSMA-Re-client-baseline.{os.getpid()}.unsigned.apk"
TEMP_SIGNED_APK = OUT_DIR / f"KSSMA-Re-client-baseline.{os.getpid()}.signed.apk"
TEMP_MANIFEST = OUT_DIR / f"client-baseline.{os.getpid()}.json"
LIB_ENTRY = "lib/armeabi/librooneyj.so"
DEBUG_KEYSTORE = Path.home() / ".android" / "debug.keystore"
DEBUG_ALIAS = "androiddebugkey"
DEBUG_PASSWORD = "android"

EXPECTED_BASE_SHA256 = "4F6A854C49D1AF59BB5500828D2BDDA0767F4D6A9FCFA8D4D6E46EA9257C58A7"
EXPECTED_LIB_SHA256 = "8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def require_hash(path: Path, expected: str, label: str) -> None:
    actual = sha256_file(path)
    if actual != expected:
        raise SystemExit(f"{label} hash mismatch: got {actual}, expected {expected}")


def should_strip_signature(name: str) -> bool:
    upper = name.upper()
    return upper.startswith("META-INF/") and upper.endswith((".MF", ".SF", ".RSA", ".DSA"))


def copy_entry(src_zip: zipfile.ZipFile, src_info: zipfile.ZipInfo, dst_zip: zipfile.ZipFile, payload: bytes | None) -> None:
    dst_info = zipfile.ZipInfo(src_info.filename, date_time=src_info.date_time)
    dst_info.compress_type = src_info.compress_type
    dst_info.comment = src_info.comment
    dst_info.extra = src_info.extra
    dst_info.create_system = src_info.create_system
    dst_info.external_attr = src_info.external_attr
    dst_info.internal_attr = src_info.internal_attr

    with dst_zip.open(dst_info, "w", force_zip64=True) as dst:
        if payload is not None:
            dst.write(payload)
            return
        with src_zip.open(src_info, "r") as src:
            shutil.copyfileobj(src, dst, length=1024 * 1024)


def build_unsigned(accepted_lib: bytes) -> None:
    TEMP_UNSIGNED_APK.unlink(missing_ok=True)
    TEMP_SIGNED_APK.unlink(missing_ok=True)

    with zipfile.ZipFile(BASE_APK, "r") as src_zip, zipfile.ZipFile(TEMP_UNSIGNED_APK, "w") as dst_zip:
        for src_info in src_zip.infolist():
            if should_strip_signature(src_info.filename):
                continue
            payload = accepted_lib if src_info.filename == LIB_ENTRY else None
            copy_entry(src_zip, src_info, dst_zip, payload)


def sign_apk() -> None:
    jarsigner = shutil.which("jarsigner")
    if not jarsigner:
        raise SystemExit("jarsigner was not found in PATH")
    if not DEBUG_KEYSTORE.exists():
        raise SystemExit(f"Missing debug keystore: {DEBUG_KEYSTORE}")

    subprocess.run(
        [
            jarsigner,
            "-keystore",
            str(DEBUG_KEYSTORE),
            "-storepass",
            DEBUG_PASSWORD,
            "-keypass",
            DEBUG_PASSWORD,
            "-sigalg",
            "SHA256withRSA",
            "-digestalg",
            "SHA-256",
            "-signedjar",
            str(TEMP_SIGNED_APK),
            str(TEMP_UNSIGNED_APK),
            DEBUG_ALIAS,
        ],
        check=True,
    )
    subprocess.run([jarsigner, "-verify", "-certs", str(TEMP_SIGNED_APK)], check=True, stdout=subprocess.DEVNULL)


def verify_apk(apk_path: Path) -> None:
    with zipfile.ZipFile(apk_path, "r") as apk:
        lib_hash = sha256_bytes(apk.read(LIB_ENTRY))
    if lib_hash != EXPECTED_LIB_SHA256:
        raise SystemExit(f"baseline APK lib hash mismatch: got {lib_hash}, expected {EXPECTED_LIB_SHA256}")


def write_manifest() -> dict:
    baseline_hash = sha256_file(OUT_APK)
    manifest = {
        "schema": 1,
        "purpose": "Unique installable KSSMA-Re client baseline. Normal startup/install entries only accept this APK.",
        "baseApk": {
            "path": str(BASE_APK.relative_to(REPO)).replace("/", "\\"),
            "sha256": EXPECTED_BASE_SHA256,
            "bytes": BASE_APK.stat().st_size,
        },
        "nativeLib": {
            "path": str(ACCEPTED_LIB.relative_to(REPO)).replace("/", "\\"),
            "entry": LIB_ENTRY,
            "sha256": EXPECTED_LIB_SHA256,
            "bytes": ACCEPTED_LIB.stat().st_size,
        },
        "baselineApk": {
            "path": str(OUT_APK.relative_to(REPO)).replace("/", "\\"),
            "sha256": baseline_hash,
            "bytes": OUT_APK.stat().st_size,
        },
        "signing": {
            "tool": "jarsigner",
            "debugKeystoreSha256": sha256_file(DEBUG_KEYSTORE),
            "alias": DEBUG_ALIAS,
        },
    }
    TEMP_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    TEMP_MANIFEST.replace(MANIFEST)
    return manifest


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    try:
        require_hash(BASE_APK, EXPECTED_BASE_SHA256, "base APK")
        require_hash(ACCEPTED_LIB, EXPECTED_LIB_SHA256, "accepted librooneyj.so")
        accepted_lib = ACCEPTED_LIB.read_bytes()
        build_unsigned(accepted_lib)
        sign_apk()
        verify_apk(TEMP_SIGNED_APK)
        TEMP_SIGNED_APK.replace(OUT_APK)
        manifest = write_manifest()
        print(f"base={BASE_APK}")
        print(f"acceptedLib={ACCEPTED_LIB}")
        print(f"baselineApk={OUT_APK}")
        print(f"manifest={MANIFEST}")
        print(f"baselineSha256={manifest['baselineApk']['sha256']}")
    finally:
        TEMP_UNSIGNED_APK.unlink(missing_ok=True)
        TEMP_SIGNED_APK.unlink(missing_ok=True)
        TEMP_MANIFEST.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
