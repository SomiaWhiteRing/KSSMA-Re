# Exploration Edge Cases: AP Shortage and Level-Up, 2026-06-28

## Frontier

Analyze two exploration forward edge cases:

- AP is lower than the current floor cost.
- Step EXP is enough to level up.

No server response shape is changed by this card.

## AP Shortage

### Evidence

- `rule_scene.xml` defines scene `81100` as `ap_fail_in`, layout `ap_failin`, with cause
  `exploration_main`.
- `rule_resource.xml` loads `exploration.png` and `ap_failin.xml` for `ap_fail_in`.
- `layout_ap_failin.xml` contains `ap_comedown`, a `back` button, hidden `ap_use_item`,
  hidden `ap_buy_item`, and behaviors `mode_use` / `mode_buy`.
- `layout_ap_failin_no_item.xml` exists, but the accepted scene rule points to
  `ap_failin.xml`; no route/value evidence currently selects the no-item layout.
- Current server response `createExplorationApFailXml()` returns header
  `<next_scene>81100</next_scene>` with empty body.
- Server self-check already asserts the AP=0 branch returns `createExplorationApFailXml()`
  and does not mutate AP, EXP, Gold, or exploration progress.

### Expected Client Behavior

When the player taps forward with insufficient AP, the client should leave the normal
exploration-main action flow and show the AP shortage screen/dialog. The player can back out
to the exploration page. The current local implementation should not spend AP, advance progress,
or grant rewards.

### Open Questions

- Which runtime condition chooses `mode_use` versus `mode_buy`.
- Whether possession of AP recovery items should switch to `ap_use_item` instead of
  `ap_buy_item`.
- Whether `layout_ap_failin_no_item.xml` is used by another scene/rule not yet recovered.

## Level-Up on Explore

### Evidence

- `work/exploration-explore-schema-card-20260627.md` confirms `_ExploreTagParser` parses
  `get_exp`, `next_exp`, `lvup`, and `is_limit` under body child `<explore>`.
- `layout_exploration_main.xml` binds `next_exp` in the stage HUD and contains:
  - behavior `lvup_event` -> command `exp_lvCheck`;
  - behavior `lv_max_anm`;
  - hidden component `lv_max` using model `exp_model` param `lvMaxData`.
- `work/exploration-getmap-annotated-20260627.txt` confirms model map names including
  `getExp` and `lvMaxData`.
- `local_battle_result.xml` has battle-only `before_exp`, `after_exp`, `before_level`,
  and `after_level`, but this is not exploration parser evidence and must not be copied
  directly into `/exploration/explore`.
- Local search has not found a reliable level EXP table. Current player save stores
  `profile.exp`, `profile.level`, `profile.nextExp`, and AP/BC allocation rules, but
  `nextExp=0` is currently only a placeholder in the default save.

### Expected Client Behavior

The original client likely handles exploration level-up inside the exploration page, not by
immediately jumping to a separate town status scene. The response probably needs to update
normal HUD data (`your_data/rank`, `free_ap_bc_point`, AP/BC/Gold as applicable) and provide
an exploration-specific level-up marker through `lvup` / `is_limit`.

### What Current Local Server Does

Current local walking only adds `get_exp` to `profile.exp`. It does not:

- compare EXP against a real level table;
- increment `profile.level`;
- recompute `profile.nextExp`;
- grant level-up AP/BC allocation points;
- emit `lvup` or `is_limit`.

So a save that is manually placed near a level boundary will accumulate EXP, but the client
should not show a proper level-up effect yet.

### Open Questions

- Exact `lvup` field type and nested shape.
- Exact `is_limit` semantics for normal level-up versus max level.
- EXP table / threshold source for early levels.
- Whether level-up fully restores AP/BC, only grants allocation points, or does both.
- Whether the separate `town_lvup_status_scene` is entered immediately after exploration
  level-up or later through another command.

## Recommended Next Checks

1. Add `exploration-ap-shortage-smoke` flow:
   - seed AP below the floor cost;
   - enter a normal floor;
   - tap forward;
   - expect `/exploration/explore` followed by `next_scene=81100`;
   - screenshot must show the AP shortage screen;
   - save must remain unchanged except for non-gameplay timestamps.

2. Run a static `lvup` schema pass before product implementation:
   - start from `_ExploreTagParser::parse`;
   - recover whether `lvup` is scalar or nested;
   - recover how `is_limit` and `lvMaxData` are copied into the model;
   - only then create a one-variable level-up runtime candidate.

3. Find or reconstruct a level EXP table:
   - local master/resource first;
   - cached wiki/external data second;
   - if no table exists, use a clearly marked test-only threshold seed and do not call it
     original behavior.

