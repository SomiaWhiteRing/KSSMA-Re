from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-area-return-rerequest.so"

STOCK_SHA256 = "CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27"

ENTRY_STICKY_PATCH = 0x00341F26
ENTRY_STICKY_RESUME = 0x00341F2A
FRESH_FLOOR_PATCH = 0x003420B6
FLOOR_LIST_ACTIVE2_PATH = 0x00342142

SET_RECORDS_POST_PATCH = 0x002D2ED8
SET_RECORDS_POST_RESUME = 0x002D2EDC
ACTION_84_PATCH = 0x002D332C
ACTION_84_RESUME = 0x002D3332
FLOOR_SELECT_PATCH = 0x003413CA
FLOOR_SELECT_RESUME = 0x003413CE
FLOOR_SELECT_NEGATIVE = 0x003413AA
STATE2_RESET_PATCH = 0x00341538
STATE2_RESET_RESUME = 0x0034153C

EXPLORATION_MODEL_AREA = 0x001D63C0
LAYOUT_SCENE_TRIGGER_MODEL = 0x001F3EB4
EXPLORATION_AREA_ROUTE_STRING = 0x003D98B4
MODEL_AREA_CONNECT_SITE = 0x001D63DE

ENTRY_CAVE = 0x003E7720
FRESH_CAVE = 0x003E7770
SAVE_PICKLIST_CAVE = 0x003E77A0
ACTION_84_CAVE = 0x003E7E60
FLOOR_SELECT_CAVE = 0x003E7EA0
STATE2_RESET_CAVE = 0x003E7EE0

STATE_ADDR = 0x004493AC
CAPTURE_FLAG_OFFSET = 0
PICKLIST_PTR_OFFSET = 4
LATCH_FLAG_OFFSET = 8


def asm(code: str, addr: int) -> bytes:
    ks = Ks(KS_ARCH_ARM, KS_MODE_THUMB | KS_MODE_LITTLE_ENDIAN)
    encoded, _ = ks.asm(code, addr=addr, as_bytes=True)
    if encoded is None:
        raise RuntimeError(f"keystone failed at {addr:#x}")
    return bytes(encoded)


def disasm(blob: bytes, addr: int) -> str:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    return "\n".join(
        f"{ins.address:08x}: {ins.bytes.hex():10} {ins.mnemonic:8} {ins.op_str}"
        for ins in md.disasm(blob, addr)
    )


def require(blob: bytes, offset: int, expected: bytes) -> None:
    actual = blob[offset : offset + len(expected)]
    if actual != expected:
        raise SystemExit(
            f"unexpected bytes at {offset:#x}: got {actual.hex()}, expected {expected.hex()}"
        )


def branch(blob: bytearray, offset: int, target: int) -> None:
    blob[offset : offset + 4] = asm(f"b.w 0x{target:x}", offset)


def load_addr(reg: str, addr: int, target: int) -> bytes:
    add_addr = addr + 8
    delta = (target - (add_addr + 4)) & 0xFFFFFFFF
    return asm(
        f"""
        movw {reg}, #{delta & 0xffff}
        movt {reg}, #{(delta >> 16) & 0xffff}
        add {reg}, pc
        """,
        addr,
    )


def entry_sticky_block(base: int) -> bytes:
    block = bytearray()
    block += asm(
        """
        adds r4, r0, #0
        movs r1, #0
        """,
        base + len(block),
    )
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        ldr r3, [r2, #{LATCH_FLAG_OFFSET}]
        cmp r3, #1
        bne resume
        ldr r3, [r4, #0x3c]
        cmp r3, #2
        beq resume
        ldr r3, [r4, #0x5c]
        cmp r3, #0
        beq resume
        ldr r3, [r3]
        cmp r3, #0
        beq resume
        ldr r0, [r3, #0x58]
        ldr r1, [r3, #0x5c]
        cmp r1, r0
        beq resume
        movs r3, #1
        str r3, [r2, #{CAPTURE_FLAG_OFFSET}]
        movs r3, #2
        str r3, [r4, #0x3c]
        b.w 0x{FLOOR_LIST_ACTIVE2_PATH:x}
    resume:
        movs r1, #0
        ldr r3, [r4, #0x5c]
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def fresh_floor_block(base: int) -> bytes:
    block = bytearray()
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        movs r3, #1
        str r3, [r2, #{CAPTURE_FLAG_OFFSET}]
        str r3, [r2, #{LATCH_FLAG_OFFSET}]
        movs r3, #0
        strb r3, [r4, r5]
        movs r3, #2
        str r3, [r4, #0x3c]
        b.w 0x{FLOOR_LIST_ACTIVE2_PATH:x}
        """,
        base + len(block),
    )
    return bytes(block)


def save_picklist_block(base: int) -> bytes:
    block = bytearray()
    block += asm("push {r2,r3}", base + len(block))
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        ldr r3, [r2, #{CAPTURE_FLAG_OFFSET}]
        cmp r3, #1
        bne replay
        mov r3, r8
        str r3, [r2, #{PICKLIST_PTR_OFFSET}]
        movs r3, #0
        str r3, [r2, #{CAPTURE_FLAG_OFFSET}]
        str r3, [r8, #0x84]
    replay:
        pop {{r2,r3}}
        mov r1, sb
        ldr r2, [r1, #4]
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def action84_block(base: int) -> bytes:
    block = bytearray()
    block += asm("push {r0,r1}", base + len(block))
    block += load_addr("r0", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        ldr r1, [r0, #{PICKLIST_PTR_OFFSET}]
        cmp r1, r6
        bne stock_500
        movs r2, #0
        b done
    stock_500:
        movs r2, #0xfa
        lsls r2, r2, #1
    done:
        movs r3, #0x84
        pop {{r0,r1}}
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def floor_select_block(base: int) -> bytes:
    block = bytearray()
    block += asm(
        f"""
        subs r6, r0, #0
        bge continue_select
        b.w 0x{FLOOR_SELECT_NEGATIVE:x}
    continue_select:
        """,
        base + len(block),
    )
    block += load_addr("r1", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        movs r2, #0
        str r2, [r1, #{LATCH_FLAG_OFFSET}]
        b.w 0x{FLOOR_SELECT_RESUME:x}
        """,
        base + len(block),
    )
    return bytes(block)


def state2_rerequest_block(base: int) -> bytes:
    block = bytearray()
    block += asm("push {r0,r1,r2,r3,r7,lr}", base + len(block))
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        movs r3, #0
        str r3, [r2, #{LATCH_FLAG_OFFSET}]
        str r3, [r2, #{CAPTURE_FLAG_OFFSET}]
        ldr r0, [r4, #0x5c]
        cmp r0, #0
        beq no_model
        ldr r0, [r0]
        cmp r0, #0
        beq no_model
        bl 0x{EXPLORATION_MODEL_AREA:x}
        mov r1, r0
        mov r0, r4
        bl 0x{LAYOUT_SCENE_TRIGGER_MODEL:x}
        movs r3, #1
        str r3, [r4, #0x3c]
        b done
    no_model:
        movs r3, #0
        str r3, [r4, #0x3c]
    done:
        pop {{r0,r1,r2,r3,r7,lr}}
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def write_block(blob: bytearray, name: str, base: int, block: bytes, limit: int) -> None:
    if len(block) > limit:
        raise SystemExit(f"{name} cave too large: {len(block)} > {limit}")
    if any(blob[base : base + len(block)]):
        raise SystemExit(f"{name} cave at {base:#x} overlaps nonzero bytes")
    blob[base : base + len(block)] = block


def assert_branch_target(blob: bytes, offset: int, target: int) -> None:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    ins = next(md.disasm(bytes(blob[offset : offset + 4]), offset), None)
    if ins is None:
        raise SystemExit(f"no instruction at {offset:#x}")
    if not ins.mnemonic.startswith("b"):
        raise SystemExit(f"expected branch at {offset:#x}, got {ins.mnemonic} {ins.op_str}")
    actual = int(ins.op_str.removeprefix("#"), 16)
    if actual != target:
        raise SystemExit(
            f"bad branch at {offset:#x}: got {actual:#x}, expected {target:#x}"
        )


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    digest = hashlib.sha256(blob).hexdigest().upper()
    if digest != STOCK_SHA256:
        raise SystemExit(f"unexpected stock sha256: got {digest}, expected {STOCK_SHA256}")

    require(blob, ENTRY_STICKY_PATCH, bytes.fromhex("041c0021"))
    require(blob, FRESH_FLOOR_PATCH, bytes.fromhex("3d482368"))
    require(blob, SET_RECORDS_POST_PATCH, bytes.fromhex("49464a68"))
    require(blob, ACTION_84_PATCH, bytes.fromhex("fa2284235200"))
    require(blob, FLOOR_SELECT_PATCH, bytes.fromhex("061eeddb"))
    require(blob, STATE2_RESET_PATCH, bytes.fromhex("0023e363"))
    require(blob, EXPLORATION_MODEL_AREA, bytes.fromhex("30b58db0"))
    require(blob, MODEL_AREA_CONNECT_SITE, bytes.fromhex("201c142106aa0bf07ef9"))
    require(blob, EXPLORATION_AREA_ROUTE_STRING, b"exploration/area\x00")
    require(blob, ENTRY_CAVE, b"\x00" * 0xC0)
    require(blob, ACTION_84_CAVE, b"\x00" * 0x180)

    entry_sticky = entry_sticky_block(ENTRY_CAVE)
    fresh_floor = fresh_floor_block(FRESH_CAVE)
    save_picklist = save_picklist_block(SAVE_PICKLIST_CAVE)
    action84 = action84_block(ACTION_84_CAVE)
    floor_select = floor_select_block(FLOOR_SELECT_CAVE)
    state2_rerequest = state2_rerequest_block(STATE2_RESET_CAVE)

    write_block(blob, "entry_sticky", ENTRY_CAVE, entry_sticky, FRESH_CAVE - ENTRY_CAVE)
    write_block(blob, "fresh_floor", FRESH_CAVE, fresh_floor, SAVE_PICKLIST_CAVE - FRESH_CAVE)
    write_block(
        blob,
        "save_picklist",
        SAVE_PICKLIST_CAVE,
        save_picklist,
        (ENTRY_CAVE + 0xC0) - SAVE_PICKLIST_CAVE,
    )
    write_block(blob, "action84", ACTION_84_CAVE, action84, FLOOR_SELECT_CAVE - ACTION_84_CAVE)
    write_block(blob, "floor_select", FLOOR_SELECT_CAVE, floor_select, STATE2_RESET_CAVE - FLOOR_SELECT_CAVE)
    write_block(blob, "state2_rerequest", STATE2_RESET_CAVE, state2_rerequest, 0x180 - (STATE2_RESET_CAVE - ACTION_84_CAVE))

    branch(blob, ENTRY_CAVE + len(entry_sticky) - 4, ENTRY_STICKY_RESUME)
    branch(blob, SAVE_PICKLIST_CAVE + len(save_picklist) - 4, SET_RECORDS_POST_RESUME)
    branch(blob, ACTION_84_CAVE + len(action84) - 4, ACTION_84_RESUME)
    branch(blob, STATE2_RESET_CAVE + len(state2_rerequest) - 4, STATE2_RESET_RESUME)

    branch(blob, ENTRY_STICKY_PATCH, ENTRY_CAVE)
    branch(blob, FRESH_FLOOR_PATCH, FRESH_CAVE)
    branch(blob, SET_RECORDS_POST_PATCH, SAVE_PICKLIST_CAVE)
    branch(blob, ACTION_84_PATCH, ACTION_84_CAVE)
    blob[ACTION_84_PATCH + 4 : ACTION_84_PATCH + 6] = asm("nop", ACTION_84_PATCH + 4)
    branch(blob, FLOOR_SELECT_PATCH, FLOOR_SELECT_CAVE)
    branch(blob, STATE2_RESET_PATCH, STATE2_RESET_CAVE)

    assert_branch_target(blob, ENTRY_STICKY_PATCH, ENTRY_CAVE)
    assert_branch_target(blob, FRESH_FLOOR_PATCH, FRESH_CAVE)
    assert_branch_target(blob, SET_RECORDS_POST_PATCH, SAVE_PICKLIST_CAVE)
    assert_branch_target(blob, ACTION_84_PATCH, ACTION_84_CAVE)
    assert_branch_target(blob, FLOOR_SELECT_PATCH, FLOOR_SELECT_CAVE)
    assert_branch_target(blob, STATE2_RESET_PATCH, STATE2_RESET_CAVE)
    assert_branch_target(blob, ENTRY_CAVE + len(entry_sticky) - 4, ENTRY_STICKY_RESUME)
    assert_branch_target(blob, FRESH_CAVE + len(fresh_floor) - 4, FLOOR_LIST_ACTIVE2_PATH)
    assert_branch_target(blob, SAVE_PICKLIST_CAVE + len(save_picklist) - 4, SET_RECORDS_POST_RESUME)
    assert_branch_target(blob, ACTION_84_CAVE + len(action84) - 4, ACTION_84_RESUME)
    assert_branch_target(blob, STATE2_RESET_CAVE + len(state2_rerequest) - 4, STATE2_RESET_RESUME)

    OUT_LIB.write_bytes(blob)
    patched_digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"stock_sha256={digest}")
    print(f"sha256={patched_digest}")
    print("request map:")
    print(
        "  floor-list return: "
        f"0x{STATE2_RESET_PATCH:08x} -> 0x{STATE2_RESET_CAVE:08x}; "
        f"calls _ExplorationModel::area=0x{EXPLORATION_MODEL_AREA:08x}; "
        "area() calls Model::connect route id 0x14; "
        f"route string anchor=0x{EXPLORATION_AREA_ROUTE_STRING:08x} exploration/area; "
        f"then LayoutScene::trigger(model)=0x{LAYOUT_SCENE_TRIGGER_MODEL:08x}; "
        f"resume -> 0x{STATE2_RESET_RESUME:08x}"
    )
    print("branch map:")
    print(f"  entry sticky latch: 0x{ENTRY_STICKY_PATCH:08x} -> 0x{ENTRY_CAVE:08x}; false -> 0x{ENTRY_STICKY_RESUME:08x}; true -> 0x{FLOOR_LIST_ACTIVE2_PATH:08x}")
    print(f"  fresh floor latch set: 0x{FRESH_FLOOR_PATCH:08x} -> 0x{FRESH_CAVE:08x}; true -> 0x{FLOOR_LIST_ACTIVE2_PATH:08x}")
    print(f"  save floor_list PickList: 0x{SET_RECORDS_POST_PATCH:08x} -> 0x{SAVE_PICKLIST_CAVE:08x}; resume -> 0x{SET_RECORDS_POST_RESUME:08x}")
    print(f"  floor_list +0x84 action guard: 0x{ACTION_84_PATCH:08x} -> 0x{ACTION_84_CAVE:08x}; resume -> 0x{ACTION_84_RESUME:08x}")
    print(f"  floor row selected clears latch: 0x{FLOOR_SELECT_PATCH:08x} -> 0x{FLOOR_SELECT_CAVE:08x}; resume -> 0x{FLOOR_SELECT_RESUME:08x}")
    print(f"  state2 return re-requests area: 0x{STATE2_RESET_PATCH:08x} -> 0x{STATE2_RESET_CAVE:08x}; resume -> 0x{STATE2_RESET_RESUME:08x}")
    print("trap map: none; this patch uses branch gates and a request map")
    for title, base, size in [
        ("entry sticky patch", ENTRY_STICKY_PATCH, 8),
        ("fresh floor patch", FRESH_FLOOR_PATCH, 8),
        ("setRecords-save patch", SET_RECORDS_POST_PATCH, 8),
        ("action84 patch", ACTION_84_PATCH, 10),
        ("floor-select patch", FLOOR_SELECT_PATCH, 8),
        ("state2-rerequest patch", STATE2_RESET_PATCH, 8),
        ("entry cave", ENTRY_CAVE, FRESH_CAVE - ENTRY_CAVE),
        ("fresh cave", FRESH_CAVE, SAVE_PICKLIST_CAVE - FRESH_CAVE),
        ("save cave", SAVE_PICKLIST_CAVE, 0x40),
        ("action84 cave", ACTION_84_CAVE, FLOOR_SELECT_CAVE - ACTION_84_CAVE),
        ("floor-select cave", FLOOR_SELECT_CAVE, STATE2_RESET_CAVE - FLOOR_SELECT_CAVE),
        ("state2-rerequest cave", STATE2_RESET_CAVE, 0x90),
        ("_ExplorationModel::area anchor", EXPLORATION_MODEL_AREA, 0x60),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
