from __future__ import annotations

import shutil
import subprocess
import zipfile
import hashlib
import os
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent
if os.environ.get("KSSMA_ALLOW_LEGACY_APK_BUILDER", "").strip() != "1":
    raise SystemExit(
        "Legacy APK builder disabled. Use work/build-client-baseline.py; "
        "set KSSMA_ALLOW_LEGACY_APK_BUILDER=1 only for archived archaeology."
    )

BASE_APK = ROOT.parent / "base" / "com.square_enix.million_cn-1.0.0.100.0712.M330.apk"
LIB_PATH = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
LIB_ENTRY = "lib/armeabi/librooneyj.so"
DEX_ENTRY = "classes.dex"
EXPLORATION_AREA_LAYOUT_ENTRY = "assets/bundle/layout_exploration_area.xml"
DIAGNOSTIC_CREATEFLOOR_SIGILL = (
    os.environ.get("KSSMA_DIAG_CREATEFLOOR_SIGILL", "").strip() == "1"
)
FIX_EXPLORATION_FLOOR_LIST_XML = (
    os.environ.get("KSSMA_FIX_EXPLORATION_FLOOR_LIST_XML", "").strip() == "1"
)
OUTPUT_APK = ROOT / (
    "million-cn-explore-createfloor-sigill-signed.apk"
    if DIAGNOSTIC_CREATEFLOOR_SIGILL
    else "million-cn-exploration-floorlist-xmlfix-signed.apk"
    if FIX_EXPLORATION_FLOOR_LIST_XML
    else "million-cn-animationguard-signed.apk"
)
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
        "offset": 0x0038D478,
        "patched": bytes.fromhex("f6d0"),
        "allowed": (
            bytes.fromhex("00d0"),
            bytes.fromhex("f6d0"),
        ),
        "reason": (
            "ponytail: a missing layout event node should skip to the next "
            "entry; branching into the callback call leaves r3 as 0x98 and "
            "crashes on real ARM."
        ),
    },
    {
        "offset": 0x0038D47C,
        "patched": bytes.fromhex("00bf"),
        "allowed": (
            bytes.fromhex("9847"),
            bytes.fromhex("00bf"),
        ),
        "reason": (
            "ponytail: the earlier layout guard left a stale callback call; "
            "the preceding movs r0,#1 is already the minimal non-null success "
            "path, so no-op the bogus blx r3."
        ),
    },
    {
        "offset": 0x0034204E,
        "patched": bytes.fromhex("21d0"),
        "allowed": (
            bytes.fromhex("21d0"),
            bytes.fromhex("21e0"),
        ),
        "reason": (
            "ponytail: restore the failed exploration error-gate diagnostic; "
            "state forcing plus no-error forcing still left the UI on the area "
            "map, so this path is not sufficient."
        ),
    },
    {
        "offset": 0x00340A9C,
        "patched": bytes.fromhex("01a894f68ffb"),
        "allowed": (
            bytes.fromhex("01a894f68ffb"),
            bytes.fromhex("0323eb63c046"),
        ),
        "reason": (
            "ponytail: restore the destructor-skipping floor-command diagnostic; "
            "it was not sufficient, so keep the command path stock while testing "
            "the state-4 branch exit."
        ),
    },
    {
        "offset": 0x0034149A,
        "patched": bytes.fromhex("0023"),
        "allowed": (
            bytes.fromhex("0023"),
            bytes.fromhex("0323"),
        ),
        "reason": (
            "ponytail: restore the failed state-4 exit diagnostic; writing "
            "state=3 here did not produce a floor-list observable, so keep the "
            "stock state machine while inspecting floor data/model population."
        ),
    },
    {
        "offset": 0x003420CE,
        "patched": (
            bytes.fromhex("00de00de")
            if DIAGNOSTIC_CREATEFLOOR_SIGILL
            else bytes.fromhex("fff77dfc")
        ),
        "allowed": (
            bytes.fromhex("fff77dfc"),
            bytes.fromhex("00de00de"),
        ),
        "reason": (
            "ponytail: keep the stock createFloorList call by default; when "
            "KSSMA_DIAG_CREATEFLOOR_SIGILL=1, replace it with a SIGILL probe "
            "to prove whether floor-list rebuild is naturally reached."
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
            # ponytail: clean base already differs here; skip until a runtime crash proves this dex guard is still needed.
            continue

        updated = updated[:offset] + replacement + updated[offset + len(original) :]

        if replacement not in updated:
            raise SystemExit(f"DEX patch verification failed: {patch['name']}")

    return fix_dex_header(updated)


def patch_exploration_area_layout(blob: bytes) -> bytes:
    if not FIX_EXPLORATION_FLOOR_LIST_XML:
        return blob

    original = b'<v_list type="avairable"name="floor_list"'
    replacement = b'<v_list type="avairable" name="floor_list"'
    if original not in blob:
        if replacement in blob:
            return blob
        raise SystemExit("Unexpected exploration layout: floor_list v_list marker not found")

    # ponytail: only fix the malformed attribute separator; if this is not the blocker,
    # the APK remains otherwise identical to the current clean-base rebuild.
    return blob.replace(original, replacement, 1)


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
    if BASE_APK.exists():
        return BASE_APK
    raise SystemExit(f"Missing clean base APK: {BASE_APK}")


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
    if temp_apk.exists():
        temp_apk.unlink()
    if OUTPUT_APK.exists():
        OUTPUT_APK.unlink()

    # ponytail: rebuild from the clean base APK; inheriting older signed APKs can carry bad resource experiments forward.
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

            if src_info.filename == EXPLORATION_AREA_LAYOUT_ENTRY:
                copy_entry(
                    src_zip,
                    src_info,
                    dst_zip,
                    patch_exploration_area_layout(src_zip.read(src_info)),
                )
                continue

            copy_entry(src_zip, src_info, dst_zip, None)

    return temp_apk


def verify_output_apk(apk_path: Path) -> None:
    with zipfile.ZipFile(apk_path, "r") as apk:
        payload = apk.read(LIB_ENTRY)
        layout = apk.read(EXPLORATION_AREA_LAYOUT_ENTRY)

    expected_create_floor = (
        bytes.fromhex("00de00de")
        if DIAGNOSTIC_CREATEFLOOR_SIGILL
        else bytes.fromhex("fff77dfc")
    )
    if read_patch_window(payload, 0x003420CE, 4) != expected_create_floor:
        raise SystemExit(
            f"Unexpected createFloorList diagnostic bytes in {apk_path}"
        )
    if read_patch_window(payload, 0x0034204E, 2) != bytes.fromhex("21d0"):
        raise SystemExit(
            f"Exploration error-gate diagnostic was not restored: {apk_path}"
        )
    if read_patch_window(payload, 0x00340A9C, 6) != bytes.fromhex("01a894f68ffb"):
        raise SystemExit(
            f"Exploration floor-command destructor diagnostic was not restored: {apk_path}"
        )
    if read_patch_window(payload, 0x0034149A, 2) != bytes.fromhex("0023"):
        raise SystemExit(
            f"Exploration state-4 exit diagnostic was not restored: {apk_path}"
        )
    has_xml_fix = b'<v_list type="avairable" name="floor_list"' in layout
    if FIX_EXPLORATION_FLOOR_LIST_XML and not has_xml_fix:
        raise SystemExit(f"Exploration floor_list XML fix missing: {apk_path}")
    if not FIX_EXPLORATION_FLOOR_LIST_XML and has_xml_fix:
        raise SystemExit(f"Unexpected exploration floor_list XML fix in baseline APK: {apk_path}")


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
    verify_output_apk(OUTPUT_APK)
    unsigned_apk.unlink(missing_ok=True)
    print(f"input={input_apk}")
    print(f"output={OUTPUT_APK}")
    print(f"lib={LIB_PATH}")


if __name__ == "__main__":
    main()
