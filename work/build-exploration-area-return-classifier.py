from __future__ import annotations

import hashlib
import os
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
POST_REBUILD = os.environ.get("POST_REBUILD") == "1"
OUT_LIB = ROOT / (
    "librooneyj-exploration-area-return-rebuild-classifier.so"
    if POST_REBUILD
    else "librooneyj-exploration-area-return-classifier.so"
)

STOCK_SHA256 = "CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27"

ENTRY_STICKY_PATCH = 0x00341F26
ENTRY_STICKY_RESUME = 0x00341F2A
AREA_CAPTURE_PATCH = 0x0034202A
AREA_CAPTURE_RESUME = 0x0034202E
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
RETURN_CLASSIFY_PATCH = 0x00341590
CREATE_AREA_LIST = 0x00341788

ENTRY_CAVE = 0x003E7720
FRESH_CAVE = 0x003E7770
BIG_CAVE = 0x00010168
SAVE_PICKLIST_CAVE = 0x00010168
RETURN_CLASSIFY_CAVE = 0x00010280
AREA_CAPTURE_CAVE = 0x00010380
ACTION_84_CAVE = 0x003E7E60
FLOOR_SELECT_CAVE = 0x003E7EA0
STATE2_RESET_CAVE = 0x003E7EE0

STATE_ADDR = 0x004493AC
FLOOR_CAPTURE_FLAG_OFFSET = 0
FLOOR_PICKLIST_PTR_OFFSET = 4
LATCH_FLAG_OFFSET = 8
AREA_THIS_OFFSET = 12
AREA_CAPTURE_FLAG_OFFSET = 16
AREA_PICKLIST_PTR_OFFSET = 20

TRAPS = {
    0x10: "return classifier: model area vector smart pointer is null",
    0x11: "return classifier: model area vector count is zero",
    0x12: "return classifier: scene-side _ExplorationArea+0x70 area vector count is zero",
    0x13: "return classifier: correct-entry area_list PickList was not captured",
    0x14: "return classifier: captured area_list PickList records count is zero",
    0x15: "return classifier: captured area_list PickList draw flag +0x7e is zero",
    0x16: "return classifier: captured area_list PickList scroll/offset +0x84 is nonzero",
    0x17: "return classifier: data, records, draw flag, and scroll offset all look present",
    0x18: "return classifier: stock return extra-event flag +0x55 is nonzero",
}


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
        str r4, [r2, #{AREA_THIS_OFFSET}]
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
        str r3, [r2, #{FLOOR_CAPTURE_FLAG_OFFSET}]
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
        str r4, [r2, #{AREA_THIS_OFFSET}]
        movs r3, #1
        str r3, [r2, #{FLOOR_CAPTURE_FLAG_OFFSET}]
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


def area_capture_block(base: int) -> bytes:
    block = bytearray()
    block += load_addr("r3", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        str r4, [r3, #{AREA_THIS_OFFSET}]
        movs r2, #1
        str r2, [r3, #{AREA_CAPTURE_FLAG_OFFSET}]
        adds r2, r4, #0
        adds r1, r0, #0
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def save_picklist_block(base: int) -> bytes:
    block = bytearray()
    block += asm("push {r0,r1,r2,r3}", base + len(block))
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        ldr r3, [r2, #{AREA_THIS_OFFSET}]
        cmp r3, #0
        beq replay

        ldr r1, [r2, #{FLOOR_CAPTURE_FLAG_OFFSET}]
        cmp r1, #1
        bne check_area
        mov r0, sb
        adds r3, #0x7c
        cmp r0, r3
        bne check_area
        mov r0, sb
        ldr r1, [r0]
        ldr r3, [r0, #4]
        subs r3, r3, r1
        asrs r3, r3, #3
        cmp r3, #0
        ble check_area
        mov r3, r8
        str r3, [r2, #{FLOOR_PICKLIST_PTR_OFFSET}]
        movs r3, #0
        str r3, [r2, #{FLOOR_CAPTURE_FLAG_OFFSET}]
        mov r0, r8
        str r3, [r0, #0x84]
        b replay

    check_area:
        ldr r3, [r2, #{AREA_THIS_OFFSET}]
        ldr r1, [r2, #{AREA_CAPTURE_FLAG_OFFSET}]
        cmp r1, #1
        bne replay
        mov r0, sb
        adds r3, #0x70
        cmp r0, r3
        bne replay
        mov r0, sb
        ldr r1, [r0]
        ldr r3, [r0, #4]
        subs r3, r3, r1
        asrs r3, r3, #3
        cmp r3, #0
        ble replay
        mov r3, r8
        str r3, [r2, #{AREA_PICKLIST_PTR_OFFSET}]
        movs r3, #0
        str r3, [r2, #{AREA_CAPTURE_FLAG_OFFSET}]

    replay:
        pop {{r0,r1,r2,r3}}
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
        ldr r1, [r0, #{FLOOR_PICKLIST_PTR_OFFSET}]
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


def state2_reset_block(base: int) -> bytes:
    block = bytearray()
    if POST_REBUILD:
        block += asm("push {r0,r1,r2,r3,r7,lr}", base + len(block))
        block += load_addr("r2", base + len(block), STATE_ADDR)
        block += asm(
            f"""
            movs r3, #0
            str r3, [r2, #{LATCH_FLAG_OFFSET}]
            mov r0, r4
            bl 0x{CREATE_AREA_LIST:x}
            pop {{r0,r1,r2,r3,r7,lr}}
            movs r3, #0
            str r3, [r4, #0x3c]
            """,
            base + len(block),
        )
        block += b"\x00\x00\x00\x00"
        return bytes(block)

    block += asm("push {r2,r3}", base + len(block))
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        movs r3, #0
        str r3, [r2, #{LATCH_FLAG_OFFSET}]
        pop {{r2,r3}}
        movs r3, #0
        str r3, [r4, #0x3c]
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def return_classify_block(base: int) -> bytes:
    block = bytearray()
    block += asm(
        """
        b main
    trap_all_present:
        udf #0x17
    trap_model_null:
        udf #0x10
    trap_model_empty:
        udf #0x11
    trap_scene_empty:
        udf #0x12
    trap_no_area_picklist:
        udf #0x13
    trap_records_empty:
        udf #0x14
    trap_draw_disabled:
        udf #0x15
    trap_scroll_nonzero:
        udf #0x16
    trap_extra_event:
        udf #0x18

    main:
        movs r3, #0x55
        ldrb r3, [r4, r3]
        cmp r3, #0
        bne trap_extra_event

        ldr r2, [r4, #0x5c]
        cmp r2, #0
        beq trap_model_null
        ldr r2, [r2]
        cmp r2, #0
        beq trap_model_null
        ldr r0, [r2, #0x30]
        ldr r1, [r2, #0x34]
        subs r1, r1, r0
        asrs r1, r1, #3
        cmp r1, #0
        ble trap_model_empty

        ldr r0, [r4, #0x70]
        ldr r1, [r4, #0x74]
        subs r1, r1, r0
        asrs r1, r1, #3
        cmp r1, #0
        ble trap_scene_empty
        """,
        base + len(block),
    )
    trap_addr = {}
    for imm in TRAPS:
        idx = block.find(bytes([imm, 0xDE]))
        if idx < 0:
            raise RuntimeError(f"missing trap marker during assembly: {imm:#x}")
        trap_addr[imm] = base + idx
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        ldr r0, [r2, #{AREA_PICKLIST_PTR_OFFSET}]
        cmp r0, #0
        beq 0x{trap_addr[0x13]:x}

        movs r3, #0x94
        ldr r1, [r0, r3]
        movs r3, #0x98
        ldr r2, [r0, r3]
        subs r2, r2, r1
        asrs r2, r2, #3
        cmp r2, #0
        ble 0x{trap_addr[0x14]:x}

        movs r3, #0x7e
        ldrb r1, [r0, r3]
        cmp r1, #0
        beq 0x{trap_addr[0x15]:x}

        movs r3, #0x84
        ldr r1, [r0, r3]
        cmp r1, #0
        bne 0x{trap_addr[0x16]:x}
        b 0x{trap_addr[0x17]:x}
        """,
        base + len(block),
    )
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


def print_trap_map(block: bytes, base: int) -> None:
    print("trap map:")
    for imm, description in TRAPS.items():
        marker = bytes([imm, 0xDE])
        idx = block.find(marker)
        if idx < 0:
            raise SystemExit(f"missing udf trap {imm:#x}")
        print(f"  0x{base + idx:08x}: udf #{imm:#04x} => {description}")


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    digest = hashlib.sha256(blob).hexdigest().upper()
    if digest != STOCK_SHA256:
        raise SystemExit(f"unexpected stock sha256: got {digest}, expected {STOCK_SHA256}")

    require(blob, ENTRY_STICKY_PATCH, bytes.fromhex("041c0021"))
    require(blob, AREA_CAPTURE_PATCH, bytes.fromhex("221c011c"))
    require(blob, FRESH_FLOOR_PATCH, bytes.fromhex("3d482368"))
    require(blob, SET_RECORDS_POST_PATCH, bytes.fromhex("49464a68"))
    require(blob, ACTION_84_PATCH, bytes.fromhex("fa2284235200"))
    require(blob, FLOOR_SELECT_PATCH, bytes.fromhex("061eeddb"))
    require(blob, STATE2_RESET_PATCH, bytes.fromhex("0023e363"))
    require(blob, RETURN_CLASSIFY_PATCH, bytes.fromhex("5523e35c002b00d1"))
    require(blob, ENTRY_CAVE, b"\x00" * 0xC0)
    require(blob, BIG_CAVE, b"\x00" * 0x400)
    require(blob, ACTION_84_CAVE, b"\x00" * 0x1F0)

    entry_sticky = entry_sticky_block(ENTRY_CAVE)
    fresh_floor = fresh_floor_block(FRESH_CAVE)
    save_picklist = save_picklist_block(SAVE_PICKLIST_CAVE)
    return_classify = return_classify_block(RETURN_CLASSIFY_CAVE)
    area_capture = area_capture_block(AREA_CAPTURE_CAVE)
    action84 = action84_block(ACTION_84_CAVE)
    floor_select = floor_select_block(FLOOR_SELECT_CAVE)
    state2_reset = state2_reset_block(STATE2_RESET_CAVE)

    write_block(blob, "entry_sticky", ENTRY_CAVE, entry_sticky, FRESH_CAVE - ENTRY_CAVE)
    write_block(blob, "fresh_floor", FRESH_CAVE, fresh_floor, 0x70)
    write_block(blob, "save_picklist", SAVE_PICKLIST_CAVE, save_picklist, RETURN_CLASSIFY_CAVE - SAVE_PICKLIST_CAVE)
    write_block(blob, "return_classify", RETURN_CLASSIFY_CAVE, return_classify, AREA_CAPTURE_CAVE - RETURN_CLASSIFY_CAVE)
    write_block(blob, "area_capture", AREA_CAPTURE_CAVE, area_capture, 0x80)
    write_block(blob, "action84", ACTION_84_CAVE, action84, FLOOR_SELECT_CAVE - ACTION_84_CAVE)
    write_block(blob, "floor_select", FLOOR_SELECT_CAVE, floor_select, STATE2_RESET_CAVE - FLOOR_SELECT_CAVE)
    write_block(blob, "state2_reset", STATE2_RESET_CAVE, state2_reset, 0x1F0 - (STATE2_RESET_CAVE - ACTION_84_CAVE))

    branch(blob, ENTRY_CAVE + len(entry_sticky) - 4, ENTRY_STICKY_RESUME)
    branch(blob, AREA_CAPTURE_CAVE + len(area_capture) - 4, AREA_CAPTURE_RESUME)
    branch(blob, SAVE_PICKLIST_CAVE + len(save_picklist) - 4, SET_RECORDS_POST_RESUME)
    branch(blob, ACTION_84_CAVE + len(action84) - 4, ACTION_84_RESUME)
    branch(blob, STATE2_RESET_CAVE + len(state2_reset) - 4, STATE2_RESET_RESUME)

    branch(blob, ENTRY_STICKY_PATCH, ENTRY_CAVE)
    branch(blob, AREA_CAPTURE_PATCH, AREA_CAPTURE_CAVE)
    branch(blob, FRESH_FLOOR_PATCH, FRESH_CAVE)
    branch(blob, SET_RECORDS_POST_PATCH, SAVE_PICKLIST_CAVE)
    branch(blob, ACTION_84_PATCH, ACTION_84_CAVE)
    blob[ACTION_84_PATCH + 4 : ACTION_84_PATCH + 6] = asm("nop", ACTION_84_PATCH + 4)
    branch(blob, FLOOR_SELECT_PATCH, FLOOR_SELECT_CAVE)
    branch(blob, STATE2_RESET_PATCH, STATE2_RESET_CAVE)
    branch(blob, RETURN_CLASSIFY_PATCH, RETURN_CLASSIFY_CAVE)
    blob[RETURN_CLASSIFY_PATCH + 4 : RETURN_CLASSIFY_PATCH + 8] = asm(
        "nop\nnop", RETURN_CLASSIFY_PATCH + 4
    )

    for patch, target in [
        (ENTRY_STICKY_PATCH, ENTRY_CAVE),
        (AREA_CAPTURE_PATCH, AREA_CAPTURE_CAVE),
        (FRESH_FLOOR_PATCH, FRESH_CAVE),
        (SET_RECORDS_POST_PATCH, SAVE_PICKLIST_CAVE),
        (ACTION_84_PATCH, ACTION_84_CAVE),
        (FLOOR_SELECT_PATCH, FLOOR_SELECT_CAVE),
        (STATE2_RESET_PATCH, STATE2_RESET_CAVE),
        (RETURN_CLASSIFY_PATCH, RETURN_CLASSIFY_CAVE),
        (ENTRY_CAVE + len(entry_sticky) - 4, ENTRY_STICKY_RESUME),
        (FRESH_CAVE + len(fresh_floor) - 4, FLOOR_LIST_ACTIVE2_PATH),
        (AREA_CAPTURE_CAVE + len(area_capture) - 4, AREA_CAPTURE_RESUME),
        (SAVE_PICKLIST_CAVE + len(save_picklist) - 4, SET_RECORDS_POST_RESUME),
        (ACTION_84_CAVE + len(action84) - 4, ACTION_84_RESUME),
        (STATE2_RESET_CAVE + len(state2_reset) - 4, STATE2_RESET_RESUME),
    ]:
        assert_branch_target(blob, patch, target)

    OUT_LIB.write_bytes(blob)
    patched_digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"stock_sha256={digest}")
    print(f"sha256={patched_digest}")
    print("branch map:")
    print(f"  entry sticky latch: 0x{ENTRY_STICKY_PATCH:08x} -> 0x{ENTRY_CAVE:08x}; false -> 0x{ENTRY_STICKY_RESUME:08x}; true -> 0x{FLOOR_LIST_ACTIVE2_PATH:08x}")
    print(f"  area_list capture arm: 0x{AREA_CAPTURE_PATCH:08x} -> 0x{AREA_CAPTURE_CAVE:08x}; resume -> 0x{AREA_CAPTURE_RESUME:08x}")
    print(f"  fresh floor latch set: 0x{FRESH_FLOOR_PATCH:08x} -> 0x{FRESH_CAVE:08x}; true -> 0x{FLOOR_LIST_ACTIVE2_PATH:08x}")
    print(f"  save area/floor PickList: 0x{SET_RECORDS_POST_PATCH:08x} -> 0x{SAVE_PICKLIST_CAVE:08x}; resume -> 0x{SET_RECORDS_POST_RESUME:08x}")
    print(f"  floor_list +0x84 action guard: 0x{ACTION_84_PATCH:08x} -> 0x{ACTION_84_CAVE:08x}; resume -> 0x{ACTION_84_RESUME:08x}")
    print(f"  floor row selected clears latch: 0x{FLOOR_SELECT_PATCH:08x} -> 0x{FLOOR_SELECT_CAVE:08x}; resume -> 0x{FLOOR_SELECT_RESUME:08x}")
    if POST_REBUILD:
        print(f"  state2 return clears latch and rebuilds scene area vector: 0x{STATE2_RESET_PATCH:08x} -> 0x{STATE2_RESET_CAVE:08x}; createAreaList=0x{CREATE_AREA_LIST:08x}; resume -> 0x{STATE2_RESET_RESUME:08x}")
    else:
        print(f"  state2 return clears latch only: 0x{STATE2_RESET_PATCH:08x} -> 0x{STATE2_RESET_CAVE:08x}; resume -> 0x{STATE2_RESET_RESUME:08x}")
    print(f"  return classifier: 0x{RETURN_CLASSIFY_PATCH:08x} -> 0x{RETURN_CLASSIFY_CAVE:08x}; traps instead of resuming")
    print_trap_map(return_classify, RETURN_CLASSIFY_CAVE)

    for title, base, size in [
        ("entry sticky patch", ENTRY_STICKY_PATCH, 8),
        ("area capture patch", AREA_CAPTURE_PATCH, 8),
        ("fresh floor patch", FRESH_FLOOR_PATCH, 8),
        ("setRecords-save patch", SET_RECORDS_POST_PATCH, 8),
        ("action84 patch", ACTION_84_PATCH, 10),
        ("floor-select patch", FLOOR_SELECT_PATCH, 8),
        ("state2-reset patch", STATE2_RESET_PATCH, 8),
        ("return-classify patch", RETURN_CLASSIFY_PATCH, 10),
        ("entry cave", ENTRY_CAVE, FRESH_CAVE - ENTRY_CAVE),
        ("fresh cave", FRESH_CAVE, 0x50),
        ("save cave", SAVE_PICKLIST_CAVE, RETURN_CLASSIFY_CAVE - SAVE_PICKLIST_CAVE),
        ("return-classify cave", RETURN_CLASSIFY_CAVE, AREA_CAPTURE_CAVE - RETURN_CLASSIFY_CAVE),
        ("area-capture cave", AREA_CAPTURE_CAVE, 0x40),
        ("action84 cave", ACTION_84_CAVE, FLOOR_SELECT_CAVE - ACTION_84_CAVE),
        ("floor-select cave", FLOOR_SELECT_CAVE, STATE2_RESET_CAVE - FLOOR_SELECT_CAVE),
        ("state2-reset cave", STATE2_RESET_CAVE, 0x60),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
