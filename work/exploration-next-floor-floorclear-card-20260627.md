# Exploration Next Floor Rejected Floor-Clear Candidate, 2026-06-27

Status:
- Runtime rejected this candidate. Do not keep it as a product server response.
- The static chain below remains useful as a lead, but the served XML shape did
  not satisfy the real client enough to reveal `floor_clear_button`.

Frontier:
- `exploration_main` reaches `<progress>100</progress>` but still does not show
  floor-clear UI.
- Raw `progress=100` and standalone `<complete>1</complete>` were runtime
  rejected.

Static evidence:
- `_ExplorationMain` triggers behavior `floor_clear_button` only after calling
  the model predicate at `0x001d519c`.
- The predicate returns true only when progress at model `+0xf8` is `100` and
  the parsed `nextFloor` object exists with its first integer nonzero.
- `_NextFloorTagParser::parse` starts at `0x00307f44`.
- Inside `_NextFloorTagParser`, direct child `floor_info` is compared at
  `0x00308040..0x0030804e`; matching it calls `_FloorInfoTagParser::parse`.
- The alternate direct scalar compare at `0x00308028..0x00308034` resolves to
  `area_id`; matching it stores the child integer into the first field of
  `NextFloorTagData` at `0x0030810a..0x00308112`.

Minimal progress-100 payload addition:

```xml
<next_floor>
  <area_id>1</area_id>
  <floor_info>
    <id>3</id>
    <type>0</type>
    <unlock>1</unlock>
    <progress>0</progress>
    <cost>1</cost>
    <boss_id>0</boss_id>
    <found_item_list></found_item_list>
  </floor_info>
</next_floor>
```

Value notes:
- `area_id=1` is intentionally nonzero because the native floor-clear predicate
  treats zero as no next floor.
- `floor_info.id=3` is the next local floor candidate after the current accepted
  `floor_id=2`.
- This is only the floor-clear branch trigger. Battle, fairy, reward, next-floor
  click behavior, and background value-domain remain separate frontiers.

Rejected:
- `<complete>1</complete>` as a standalone trigger: runtime served it, but the
  UI stayed at the 100% walking screen with no new route.
- Treating `<next_floor>` as a scalar once progress reaches 100: the parser
  requires direct child fields, and the UI predicate depends on the parsed
  object.
- The nested `<next_floor><area_id>1</area_id><floor_info>...</floor_info></next_floor>`
  candidate above: runtime served it at `progress=100` and the encrypted
  response size grew, but the screenshot still showed the normal 100% walking
  screen with no floor-clear UI and no new route.

Next:
- Recheck the exact field copied into the model-side next-floor object before
  another server response candidate. Do not add more `next_floor`, `complete`,
  boss, reward, or event fields without a new native consumer proof.
