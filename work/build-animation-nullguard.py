from __future__ import annotations

import shutil
import subprocess
import zipfile
import hashlib
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent
LIB_PATH = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
LIB_ENTRY = "lib/armeabi/librooneyj.so"
DEX_ENTRY = "classes.dex"
ROUTE_XML_PATH = (
    ROOT / "million_cn" / "apktool" / "assets" / "bundle" / "rule_resource_route.xml"
)
ROUTE_XML_ENTRY = "assets/bundle/rule_resource_route.xml"
OUTPUT_APK = ROOT / "million-cn-animationguard-signed.apk"
DEBUG_KEYSTORE = Path.home() / ".android" / "debug.keystore"
DEBUG_ALIAS = "androiddebugkey"
DEBUG_PASSWORD = "android"

PATCHES = (
    {
        "offset": 0x00380260,
        "patched": bytes.fromhex("c1b18b69202b15d9196899b1"),
        "allowed": (
            bytes.fromhex("8b69002b16d01968002913d0"),
            bytes.fromhex("c1b18b69b3b11968002913d0"),
            bytes.fromhex("c1b18b69202b15d9196899b1"),
        ),
        "reason": (
            "ponytail: if the clip table is missing or a bogus low pointer leaks "
            "through, reuse the existing empty return path instead of walking "
            "corrupt animation metadata."
        ),
    },
    {
        "offset": 0x00385418,
        "patched": bytes.fromhex("039b202b1dd9186820281ad9"),
        "allowed": (
            bytes.fromhex("039b002b1dd0186800281ad0"),
            bytes.fromhex("039b202b1dd9186820281ad9"),
        ),
        "reason": (
            "ponytail: a low movie-clip wrapper/object pointer is still just "
            "\"missing clip\"; skip the draw path here before it reaches the next "
            "vtable dereference."
        ),
    },
    {
        "offset": 0x00384F56,
        "patched": bytes.fromhex("eb68202b0bd918680368"),
        "allowed": (
            bytes.fromhex("eb68002b00d018680368"),
            bytes.fromhex("eb68202b0bd918680368"),
        ),
        "reason": (
            "ponytail: some script entries carry a bogus low object pointer; "
            "treat that like a missing script object and skip to the next entry."
        ),
    },
    {
        "offset": 0x00384F9A,
        "patched": bytes.fromhex("db68202be9d918680368"),
        "allowed": (
            bytes.fromhex("db68002b00d018680368"),
            bytes.fromhex("db68202be9d918680368"),
        ),
        "reason": (
            "ponytail: same low-pointer guard for the alternate script action "
            "path so all checkScript cases share the same bailout."
        ),
    },
    {
        "offset": 0x00384FBC,
        "patched": bytes.fromhex("eb68202bd8d918680368"),
        "allowed": (
            bytes.fromhex("eb68002b00d018680368"),
            bytes.fromhex("eb68202bd8d918680368"),
        ),
        "reason": (
            "ponytail: same bailout for the third script callback variant; "
            "missing script data should skip, not dereference address 0x8."
        ),
    },
    {
        "offset": 0x0038544E,
        "patched": bytes.fromhex("fff785ff"),
        "allowed": (
            bytes.fromhex("fff785ff"),
            bytes.fromhex("00bf00bf"),
        ),
        "reason": (
            "ponytail: restore the movie-clip draw call; skipping it did not "
            "change the Houdini crash signature, so keep the runtime behavior "
            "closer to stock while testing the texture path."
        ),
    },
    {
        "offset": 0x001B0078,
        "patched": bytes.fromhex("70b586b0"),
        "allowed": (
            bytes.fromhex("70b586b0"),
            bytes.fromhex("704700bf"),
        ),
        "reason": (
            "ponytail: restore the async texture handoff; the early-return "
            "diagnostic did not move the crash, so keep stock behavior while "
            "patching the actual main-loop fault."
        ),
    },
    {
        "offset": 0x002A1EA0,
        "patched": bytes.fromhex("b8d0"),
        "allowed": (
            bytes.fromhex("00d0"),
            bytes.fromhex("b8d0"),
        ),
        "reason": (
            "ponytail: XmlContentViewer::setPropertyValues can receive an "
            "empty map value from the incomplete local protocol; treat that "
            "as no properties instead of dereferencing 0+8 under Houdini."
        ),
    },
    {
        "offset": 0x00375518,
        "patched": bytes.fromhex("00f6f0ee"),
        "allowed": (
            bytes.fromhex("00f6f0ee"),
            bytes.fromhex("c046c046"),
        ),
        "reason": (
            "ponytail: restore the GL teardown calls; skipping them did not move "
            "the 0x98 Houdini crash, so keep native graphics cleanup stock."
        ),
    },
    {
        "offset": 0x00375528,
        "patched": bytes.fromhex("00f6e8ee"),
        "allowed": (
            bytes.fromhex("00f6e8ee"),
            bytes.fromhex("c046c046"),
        ),
        "reason": (
            "ponytail: restore the secondary renderbuffer delete after the "
            "diagnostic no-op proved unrelated."
        ),
    },
    {
        "offset": 0x00375538,
        "patched": bytes.fromhex("00f60aef"),
        "allowed": (
            bytes.fromhex("00f60aef"),
            bytes.fromhex("c046c046"),
        ),
        "reason": (
            "ponytail: restore framebuffer delete; the active blocker is XML "
            "content parsing, not GL teardown."
        ),
    },
    {
        "offset": 0x003750FA,
        "patched": bytes.fromhex("01f68eeb"),
        "allowed": (
            bytes.fromhex("01f68eeb"),
            bytes.fromhex("c046c046"),
        ),
        "reason": (
            "ponytail: restore CMtGraphics glRotatef; the no-op diagnostic did "
            "not move the active Houdini 0x98 crash."
        ),
    },
    {
        "offset": 0x00375FCA,
        "patched": bytes.fromhex("00f626ec"),
        "allowed": (
            bytes.fromhex("00f626ec"),
            bytes.fromhex("c046c046"),
        ),
        "reason": (
            "ponytail: restore the shared drawImage rotation call; the crash "
            "evidence points at resource routing, not this GL call."
        ),
    },
)

DEX_PATCHES = (
    {
        "name": "loadBitmap-null-placeholder",
        "original": bytes.fromhex(
            "7110570806000c0039000a001a028d1112032333a5027120cd073200"
        ),
        "patched": bytes.fromhex(
            "121062020a007130880000020c000000000000000000000000000000"
        ),
        "reason": (
            "ponytail: bad or not-yet-reconstructed save textures should become "
            "a 1x1 transparent bitmap, not a null handed to native texture code."
        ),
    },
)


def read_patch_window(blob: bytes, offset: int, size: int) -> bytes:
    return blob[offset : offset + size]


def patch_library() -> bytes:
    blob = LIB_PATH.read_bytes()
    updated = bytearray(blob)
    changed = False

    for patch in PATCHES:
        offset = patch["offset"]
        replacement = patch["patched"]
        window = read_patch_window(blob, offset, len(replacement))

        if window == replacement:
            continue

        if window not in patch["allowed"]:
            raise SystemExit(
                "Unexpected librooneyj.so bytes at 0x%08x: %s"
                % (offset, window.hex())
            )

        updated[offset : offset + len(replacement)] = replacement
        changed = True

    if not changed:
        return blob

    patched = bytes(updated)

    for patch in PATCHES:
        offset = patch["offset"]
        replacement = patch["patched"]
        if read_patch_window(patched, offset, len(replacement)) != replacement:
            raise SystemExit(
                "Patch verification failed for librooneyj.so at 0x%08x" % offset
            )

    LIB_PATH.write_bytes(patched)
    return patched


def patch_dex(blob: bytes) -> bytes:
    updated = blob

    for patch in DEX_PATCHES:
        original = patch["original"]
        replacement = patch["patched"]
        if len(original) != len(replacement):
            raise SystemExit(f"Bad DEX patch length: {patch['name']}")

        if replacement in updated:
            continue

        offset = updated.find(original)
        if offset < 0:
            raise SystemExit(f"DEX patch target not found: {patch['name']}")

        updated = updated[:offset] + replacement + updated[offset + len(original) :]

        if replacement not in updated:
            raise SystemExit(f"DEX patch verification failed: {patch['name']}")

    return fix_dex_header(updated)


def fix_dex_header(blob: bytes) -> bytes:
    updated = bytearray(blob)
    updated[12:32] = hashlib.sha1(updated[32:]).digest()
    updated[8:12] = zlib.adler32(updated[12:]).to_bytes(4, "little")
    return bytes(updated)


def should_strip_signature(name: str) -> bool:
    upper = name.upper()
    return upper.startswith("META-INF/") and upper.endswith(
        (".MF", ".SF", ".RSA", ".DSA")
    )


def resolve_input_apk() -> Path:
    candidates = sorted(
        (
            path
            for path in ROOT.glob("*signed.apk")
            if path.resolve() != OUTPUT_APK.resolve()
        ),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )

    if not candidates:
        raise SystemExit(f"No signed APK found under {ROOT}")

    return candidates[0]


def copy_entry(
    src_zip: zipfile.ZipFile,
    src_info: zipfile.ZipInfo,
    dst_zip: zipfile.ZipFile,
    payload: bytes | None,
) -> None:
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


def rebuild_apk(input_apk: Path, lib_blob: bytes) -> Path:
    temp_apk = OUTPUT_APK.with_suffix(".unsigned.apk")
    route_xml = ROUTE_XML_PATH.read_bytes()
    if temp_apk.exists():
        temp_apk.unlink()
    if OUTPUT_APK.exists():
        OUTPUT_APK.unlink()

    # ponytail: rebuild from the latest signed APK to keep the existing smali/resource patches without dragging apktool back into the loop.
    with zipfile.ZipFile(input_apk, "r") as src_zip, zipfile.ZipFile(
        temp_apk, "w"
    ) as dst_zip:
        for src_info in src_zip.infolist():
            if should_strip_signature(src_info.filename):
                continue

            if src_info.filename == LIB_ENTRY:
                copy_entry(src_zip, src_info, dst_zip, lib_blob)
                continue

            if src_info.filename == DEX_ENTRY:
                copy_entry(src_zip, src_info, dst_zip, patch_dex(src_zip.read(src_info)))
                continue

            if src_info.filename == ROUTE_XML_ENTRY:
                copy_entry(src_zip, src_info, dst_zip, route_xml)
                continue

            copy_entry(src_zip, src_info, dst_zip, None)

    return temp_apk


def sign_apk(unsigned_apk: Path) -> None:
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
            str(OUTPUT_APK),
            str(unsigned_apk),
            DEBUG_ALIAS,
        ],
        check=True,
    )

    subprocess.run(
        [jarsigner, "-verify", "-certs", str(OUTPUT_APK)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main() -> None:
    input_apk = resolve_input_apk()
    lib_blob = patch_library()
    unsigned_apk = rebuild_apk(input_apk, lib_blob)
    sign_apk(unsigned_apk)
    unsigned_apk.unlink(missing_ok=True)
    print(f"input={input_apk}")
    print(f"output={OUTPUT_APK}")
    print(f"lib={LIB_PATH}")


if __name__ == "__main__":
    main()
