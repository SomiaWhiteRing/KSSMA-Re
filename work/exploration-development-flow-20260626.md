# Exploration Development Flow

This plan starts from the current evidence: `/connect/app/exploration/floor` returns 200,
`_ExplorationArea::preUpdate()` reaches the `createFloorList` call naturally, and the
visible UI still remains on the area map.

## Current Frontier

The active blocker is not server reachability and not the area-map layout. The blocker is
between floor response parsing and visible floor-list item creation.

Known evidence:

- `/connect/app/exploration/area` returns 200 and shows `Local Area`.
- `/connect/app/exploration/floor` returns 200 with decrypted `area_id=0`.
- A diagnostic SIGILL at `librooneyj.so+0x003420CE` fires after the floor response, proving
  stock control flow reaches the `createFloorList` call.
- With stock bytes restored (`0x3420CE=fff77dfc`), the game does not crash but still stays
  on the area map.
- Changing only floor `id=2 -> id=1` did not show a visible floor list and was reverted.

## Hard Rules

- Do not keep guessing floor XML field values until runtime proves which consumer is failing.
- Do not stack state-machine patches; prior state forcing did not produce the UI observable.
- Do not run full APK install for native-only probes. Use `kssma-runtime.ps1 patch-lib`.
- Do not use Frida as the default probe on ARM19; it previously destabilized ADB.
- Every runtime probe must leave requests, screenshot, Activity, and relevant logcat artifacts.

## Phase 0: Runtime Gate

Before every real-device run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-baseline
node .\server\test-bootstrap-server.js
```

If `fast-health` or `ensure-baseline` fails, fix the helper/runtime state first. Do not
interpret exploration behavior while hosts, mount, package, display, or server are unproven.

## Phase 1: Prove createFloorList Input

Goal: determine whether `createFloorList` sees a nonzero floor vector.

Preferred static task:

- Locate the exact vector/count read in `createFloorList`.
- Produce a minimal diagnostic that distinguishes `count == 0` from `count > 0`.
- The diagnostic should be one native patch only, documented with offset, stock bytes,
  patched bytes, and expected observable.

Acceptable observables:

- A controlled SIGILL at the `count == 0 return` branch.
- A controlled SIGILL after the first list item is created.
- A logcat line from an existing native/Java logging call if one is already available.

Do not accept:

- "Looks better" screenshots.
- Another XML value candidate without proving the vector count.
- A broad Frida session with no stop condition.

## Phase 2: If Vector Count Is Zero

Then the failure is before list creation.

Work in this order:

1. Reconfirm `_ExplorationModel::update` floor branch reaches `_ExplorationFloorTagParser::parse`.
2. Reconfirm `_ExplorationModel::init(ExplorationFloorTagData)` copies `floor_info_list` into
   `_ExplorationModel+0x58`.
3. Recover exact scalar and list fields consumed by `_FloorInfoTagParser`.
4. Add or change one field at a time in `EXPLORATION_FLOOR_XML`.
5. Re-run only the floor path and check vector count again.

Only after vector count becomes nonzero should the floor-list UI be judged.

## Phase 3: If Vector Count Is Nonzero

Then the failure is in item construction, layout binding, or visibility.

Work in this order:

1. Trace `_AnmExplorationList` creation and required item tags.
2. Identify which fields are read from each `floor_info` item after vector iteration.
3. Test exactly one missing item field/value.
4. The acceptance observable is a screenshot showing a visible floor row, not merely another
   200 response.

## Phase 4: After Floor List Appears

Only then advance gameplay.

1. Click the first floor item.
2. Record the next concrete route and decrypted request params.
3. Add the smallest server handler for that route.
4. Repeat route by route. The expected shape is request -> parser/schema -> minimal response
   -> real-device observable.

## Suggested Parallel Agents

- Native probe agent: recover `createFloorList` count/read offsets and propose one diagnostic
  patch. No server XML edits.
- Parser/schema agent: deepen `_ExplorationFloorTagParser`, `_FloorInfoListTagParser`, and
  `_FloorInfoTagParser` field evidence. No runtime testing.
- Runtime agent: run exactly one validated hypothesis through ARM19 using `fast-health`,
  `ensure-baseline`, `patch-lib` only when native bytes changed, and `observe`.
- Server agent: implement response changes only after native/parser evidence names a concrete
  missing field or route.

## Done Criteria For This Frontier

This frontier is done when one of these is true:

- The floor list is visible on device, with request/log/screenshot artifacts recorded.
- A native/parser proof shows the current server response cannot populate `model+0x58`, and
  the next missing field/value is identified.
- A controlled diagnostic proves item creation happens but visibility/layout is the blocker,
  with the next layout-side consumer identified.
