from __future__ import annotations

import hashlib
import json
import os
import shutil
import struct
import subprocess
import zipfile
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
BASE_APK = REPO / "base" / "com.square_enix.million_cn-1.0.0.100.0712.M330.apk"
ACCEPTED_LIB = ROOT / "librooneyj-gacha-cardget-inner-touch-nullguard.so"
OUT_DIR = ROOT / "client-baseline"
OUT_APK = OUT_DIR / "KSSMA-Re-client-baseline.apk"
MANIFEST = OUT_DIR / "client-baseline.json"
TEMP_UNSIGNED_APK = OUT_DIR / f"KSSMA-Re-client-baseline.{os.getpid()}.unsigned.apk"
TEMP_SIGNED_APK = OUT_DIR / f"KSSMA-Re-client-baseline.{os.getpid()}.signed.apk"
TEMP_MANIFEST = OUT_DIR / f"client-baseline.{os.getpid()}.json"
LIB_ENTRY = "lib/armeabi/librooneyj.so"
CLASSES_ENTRY = "classes.dex"
DEBUG_KEYSTORE = Path.home() / ".android" / "debug.keystore"
DEBUG_ALIAS = "androiddebugkey"
DEBUG_PASSWORD = "android"

EXPECTED_BASE_SHA256 = "4F6A854C49D1AF59BB5500828D2BDDA0767F4D6A9FCFA8D4D6E46EA9257C58A7"
EXPECTED_LIB_SHA256 = "DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F"
EXPECTED_CLASSES_SHA256 = "985D4105968A95EC9DFE9BCC3711597A324A90F472700DF7435CA7D25A2087C6"

# Diagnostic-only DEX method-reference substitutions. Both call sites already have
# the exact (String, Object[]) descriptor; redirecting them to Debug.err activates
# the otherwise compiled-out texture-path log without changing control flow.
TEXTURE_PATH_DIAGNOSTIC_PATCHES = (
    (273780, bytes.fromhex("D007"), bytes.fromhex("CC07"), "TextureLoader.loadTexture path"),
    (273902, bytes.fromhex("CB07"), bytes.fromhex("CC07"), "TextureLoader.loadTextureWithRect path"),
)


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


def build_texture_path_diagnostic(classes_dex: bytes) -> bytes:
    if sha256_bytes(classes_dex) != EXPECTED_CLASSES_SHA256:
        raise SystemExit("classes.dex hash mismatch; refusing offset-based diagnostic patch")

    patched = bytearray(classes_dex)
    for offset, expected, replacement, label in TEXTURE_PATH_DIAGNOSTIC_PATCHES:
        actual = bytes(patched[offset : offset + len(expected)])
        if actual != expected:
            raise SystemExit(
                f"{label} bytes mismatch at {offset}: got {actual.hex().upper()}, "
                f"expected {expected.hex().upper()}"
            )
        patched[offset : offset + len(expected)] = replacement

    # DEX header signature covers bytes 32..EOF; checksum covers bytes 12..EOF.
    patched[12:32] = hashlib.sha1(patched[32:]).digest()
    patched[8:12] = struct.pack("<I", zlib.adler32(patched[12:]) & 0xFFFFFFFF)
    return bytes(patched)


def build_unsigned(accepted_lib: bytes, classes_dex: bytes | None = None) -> None:
    TEMP_UNSIGNED_APK.unlink(missing_ok=True)
    TEMP_SIGNED_APK.unlink(missing_ok=True)

    with zipfile.ZipFile(BASE_APK, "r") as src_zip, zipfile.ZipFile(TEMP_UNSIGNED_APK, "w") as dst_zip:
        for src_info in src_zip.infolist():
            if should_strip_signature(src_info.filename):
                continue
            payload = accepted_lib if src_info.filename == LIB_ENTRY else None
            if src_info.filename == CLASSES_ENTRY and classes_dex is not None:
                payload = classes_dex
            copy_entry(src_zip, src_info, dst_zip, payload)


def sign_apk() -> None:
    jarsigner = shutil.which("jarsigner")
    if not jarsigner:
        raise SystemExit("jarsigner was not found in PATH")
    if not DEBUG_KEYSTORE.exists():
        keytool = shutil.which("keytool")
        if not keytool:
            raise SystemExit("keytool was not found in PATH")
        DEBUG_KEYSTORE.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                keytool,
                "-genkeypair",
                "-keystore",
                str(DEBUG_KEYSTORE),
                "-storepass",
                DEBUG_PASSWORD,
                "-keypass",
                DEBUG_PASSWORD,
                "-alias",
                DEBUG_ALIAS,
                "-keyalg",
                "RSA",
                "-keysize",
                "2048",
                "-validity",
                "10000",
                "-dname",
                "CN=Android Debug,O=Android,C=US",
                "-noprompt",
            ],
            check=True,
        )

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


def verify_apk(apk_path: Path, expected_classes_sha256: str) -> None:
    with zipfile.ZipFile(apk_path, "r") as apk:
        lib_hash = sha256_bytes(apk.read(LIB_ENTRY))
        classes_hash = sha256_bytes(apk.read(CLASSES_ENTRY))
    if lib_hash != EXPECTED_LIB_SHA256:
        raise SystemExit(f"baseline APK lib hash mismatch: got {lib_hash}, expected {EXPECTED_LIB_SHA256}")
    if classes_hash != expected_classes_sha256:
        raise SystemExit(
            f"baseline APK classes.dex hash mismatch: got {classes_hash}, expected {expected_classes_sha256}"
        )


def write_manifest(*, classes_sha256: str, texture_path_diagnostic: bool) -> dict:
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
        "classesDex": {
            "entry": CLASSES_ENTRY,
            "sourceSha256": EXPECTED_CLASSES_SHA256,
            "sha256": classes_sha256,
            "texturePathDiagnostic": texture_path_diagnostic,
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
        texture_path_diagnostic = os.environ.get("KSSMA_TEXTURE_PATH_DIAGNOSTIC", "") == "1"
        with zipfile.ZipFile(BASE_APK, "r") as base_apk:
            source_classes = base_apk.read(CLASSES_ENTRY)
        if sha256_bytes(source_classes) != EXPECTED_CLASSES_SHA256:
            raise SystemExit("base APK classes.dex hash mismatch")
        classes_dex = build_texture_path_diagnostic(source_classes) if texture_path_diagnostic else source_classes
        classes_sha256 = sha256_bytes(classes_dex)
        build_unsigned(accepted_lib, classes_dex)
        sign_apk()
        verify_apk(TEMP_SIGNED_APK, classes_sha256)
        TEMP_SIGNED_APK.replace(OUT_APK)
        manifest = write_manifest(
            classes_sha256=classes_sha256,
            texture_path_diagnostic=texture_path_diagnostic,
        )
        print(f"base={BASE_APK}")
        print(f"acceptedLib={ACCEPTED_LIB}")
        print(f"baselineApk={OUT_APK}")
        print(f"manifest={MANIFEST}")
        print(f"classesSha256={classes_sha256}")
        print(f"texturePathDiagnostic={texture_path_diagnostic}")
        print(f"baselineSha256={manifest['baselineApk']['sha256']}")
    finally:
        TEMP_UNSIGNED_APK.unlink(missing_ok=True)
        TEMP_SIGNED_APK.unlink(missing_ok=True)
        TEMP_MANIFEST.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
