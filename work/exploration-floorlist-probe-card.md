# Exploration Floor List Probe Card

Route: `/connect/app/exploration/floor`

Current frontier:

```text
/connect/app/exploration/area OK
-> /connect/app/exploration/floor encrypted 200
-> _ExplorationArea::createFloorList() reached
-> floor_list not visible
```

Hypothesis:

`_ExplorationArea::createFloorList()` is reached, but the next unknown is whether the
`floor_info_list` vector copied from `_ExplorationModel+0x58` has `count == 0` or
`count > 0`.

Last observable:

- Prior runtime hit a diagnostic `SIGILL` at `librooneyj.so+0x003420CE`, proving
  `_ExplorationArea::preUpdate()` naturally reaches the `createFloorList()` call after
  `/connect/app/exploration/floor` returns 200.
- Stock bytes at `librooneyj.so+0x003420CE` are `ff f7 7d fc`, the Thumb `bl
  #0x3419cc` call into `_ExplorationArea::createFloorList()`.
- With stock `0x003420CE` restored, runtime does not crash but the visible UI remains the
  `Local Area` map.

Static anchors:

- `work/exploration-ui-disasm-annotated.txt`
- `work/exploration-createfloorlist-disasm.txt`
- `work/create-floor-list-disasm.txt`
- `work/installed-lib-stock-createfloor.so`
- `work/million_cn/apktool/assets/bundle/layout_exploration_area.xml`

Reachability anchor:

```text
_ExplorationArea::preUpdate()
003420cc: adds     r0, r4
003420ce: bl       #0x3419cc ; _ExplorationArea::createFloorList()
003420d2: movs     r3, #0x80
```

Count source inside `_ExplorationArea::createFloorList()`:

```text
_ExplorationArea::createFloorList() at 0x003419cc
003419fc: mov      r0, r8
003419fe: ldr      r3, [r0, #0x5c]      ; _ExplorationArea model smart_ptr
00341a00: movs     r1, #0
00341a02: cmp      r3, #0
00341a04: beq      #0x341a08
00341a06: ldr      r1, [r3]             ; model object
00341a08: adds     r1, #0x58            ; model floor_info_list
00341a0a: add      r0, sp, #0xd0
00341a0c: bl       #0x340b08            ; copy vector<smart_ptr<FloorInfoTagData>>
00341a10: ldr      r2, [sp, #0xd4]      ; copied vector end
00341a12: ldr      r3, [sp, #0xd0]      ; copied vector begin
00341a16: subs     r3, r2, r3
00341a18: asrs     r3, r3, #3           ; count, 8-byte smart_ptr entries
00341a1a: str      r3, [sp, #0x24]
00341a1c: bl       #0x1d5218            ; destroy temporary vector copy
00341a20: ldr      r2, [sp, #0x24]      ; count reloaded
...
00341a30: cmp      r2, #0
00341a32: bgt      #0x341a36            ; count > 0 enters item path
00341a34: b        #0x341c3a            ; count <= 0 returns
00341a36: mov      fp, r3               ; first non-empty path instruction
```

Recommended probe:

Install one diagnostic native patch that replaces the two possible count outcomes with
different Thumb `udf` instructions. This gives one runtime run and one logcat PC.

Patch window:

```text
librooneyj.so+0x00341A30 stock:
00 2A 00 DC 01 E1 9B 46

librooneyj.so+0x00341A30 patched:
00 2A 00 DC 00 DE 01 DE
```

Individual changes:

```text
0x00341A34: 01 E1 -> 00 DE    ; count <= 0: udf #0
0x00341A36: 9B 46 -> 01 DE    ; count > 0:  udf #1
```

Why this point:

- It is after the vector copy and count calculation from `_ExplorationModel+0x58`.
- It is before any floor item UI construction, found-item processing, texture lookup, or
  `floor_list` scene insertion.
- It does not depend on field values such as floor id/type/unlock/cost.
- It leaves the existing branch condition intact; only the two outcomes become observable.

Expected runtime observable:

```text
Fatal signal 4 (SIGILL) at pc 00341a34 in librooneyj.so
=> createFloorList() saw count <= 0. Next smallest action: parser/model card C,
   specifically `_ExplorationFloorTagParser` -> list push -> `_ExplorationModel+0x58`.

Fatal signal 4 (SIGILL) at pc 00341a36 in librooneyj.so
=> createFloorList() saw count > 0. Next smallest action: UI/item card B,
   specifically item construction and `scene.floor_list` insertion/visibility.

Fatal signal 4 (SIGILL) at pc 003420ce in librooneyj.so
=> stale old reachability probe is still installed. Restore stock `ff f7 7d fc` before
   running this count probe.

No SIGILL after `/connect/app/exploration/floor` 200
=> this run did not reach the counted `createFloorList()` path; first re-check that
   `0x003420CE` is stock and that the same area click path reached floor 200.
```

Layout consumer context:

`layout_exploration_area.xml` binds `floor_list` as a scene list:

```text
<v_list name="floor_list" model="scene" ...>
  <param name="focus" value="f_focus" />
  <param name="list" value="floor_list" />
  <param name="remake" value="remake"/>
</v_list>
```

The relevant behaviors are `floor_list_active2` / `floor_list_true`, which set
`floor_list` visible and call `remake`. This card does not test those behaviors; it only
classifies the model vector input before UI work starts.

Dead ends recorded:

- Floor `<id>2 -> 1` was already tried and reverted; it did not make the floor list visible.
- Prior state/error-gate native diagnostics reached `/exploration/floor` 200 but did not show
  `floor_list`; do not stack more state patches before proving vector count.
- The `0x003420CE` SIGILL proves reachability only; it does not distinguish empty vector from
  hidden/non-rendered items.

Do not change for this probe:

- No server XML changes.
- No APK resource/layout changes.
- No extra route implementations.
- No Frida session.
- Do not leave this diagnostic patch installed after the count result is recorded.

Open questions:

- None for the next runtime handoff. The next run only needs to observe whether the SIGILL PC is
  `00341a34` or `00341a36`.
