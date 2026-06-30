# Exploration Level-Up Schema Card, 2026-06-29

## Frontier

Recover the level-up boundary for `/connect/app/exploration/explore`.

This card is static schema evidence. It authorizes only ordinary non-max-level `lvup=1`
runtime work when paired with a trusted EXP threshold row from
`work/player-level-exp-table-card-20260629.md`.

## Confirmed XML Fields

`_ExploreTagParser` parses these fields under:

```xml
<body>
  <explore>
    ...
  </explore>
</body>
```

Confirmed ordinary level-up related fields:

```xml
<get_exp>int</get_exp>
<next_exp>int</next_exp>
<lvup>0_or_1_int</lvup>
<is_limit>0_or_1_int</is_limit>
```

## Static Evidence

- `lvup` is a scalar integer node. `_ExploreTagParser` compares the `lvup` child, enters
  the branch at `0x002fa158`, reads node text, calls the integer parser helper at
  `0x387344`, and writes the parsed value to `ExploreTagData+0x1c`.
- `is_limit` is also a scalar integer node. The branch at `0x002fa134` follows the same
  text-to-integer path and writes to `ExploreTagData+0x20`.
- `_ExplorationModel::init(ExploreTagData)` copies `is_limit` into the exploration model
  field that `getMap` exposes as `isLimit`.
- `layout_exploration_main.xml` contains `lvup_event -> exp_lvCheck`, plus `lv_max_anm`
  and hidden `lv_max` UI that reads `exp_model.lvMaxData`.
- `lvMaxData` is a model map key, not a confirmed XML field in this pass.

## Minimal Ordinary Level-Up Candidate

If the next runtime pass only tests the ordinary non-max-level upgrade marker, the only
evidence-backed XML addition is:

```xml
<get_exp>3</get_exp>
<next_exp>100</next_exp>
<lvup>1</lvup>
<is_limit>0</is_limit>
```

This candidate is not enough for max-level behavior.

## Not Closed

- `lvMaxData` source node or object shape.
- Full `exp_lvCheck` consumed field set.
- Max-level value domain for `lvMaxData` and `is_limit=1`.
- Full original mobile player level EXP threshold table.
- Growth reward payloads, if any, for level-up.

## Rejected Shortcuts

- Do not copy battle-only `before_level`, `after_level`, `before_exp`, or `after_exp`
  from `local_battle_result.xml` into `/exploration/explore`.
- Do not treat `<is_limit>1</is_limit>` alone as a closed max-level response.
- Do not implement level-up for rows whose source rank is `missing`, `fc2_3ds_uncertain`,
  or `pattern_inferred_from_fc2`.

## Value-Domain Update

`work/player-level-exp-table-card-20260629.md` found enough evidence for a first ordinary
upgrade smoke without test-only thresholds:

```text
Lv17 nextExp=2000 -> Lv18 nextExp=2100
```

Both values come directly from original mobile atwiki. The mobile atwiki page also confirms
level-up restores AP/BC and grants AP/BC allocation points, with 3 points before level 50
and 2 points from level 50.

## Accepted Runtime

`flow -Scenario exploration-levelup-smoke` passed with artifact:

```text
work/kssma-flow-exploration-levelup-smoke-20260630-002346
```

The scenario seeded a Lv17 player at `profile.exp=1997`, then one AP=1 exploration move emitted
`lvup=1`, `is_limit=0`, rank 18, `next_exp=2100`, AP/BC full recovery, and +3 unspent
allocation points. The artifact-local save ended with level 18, carry EXP 0, next EXP 2100,
AP 25, BC 25, ability points 3, Gold 18, and `movesByFloor["0:2"]=1`.

## Next Frontier

After the level-up response, the client requests:

```text
/connect/app/town/lvup_status
```

The current server returns the generic 501 for that route. Do not guess this response from the
exploration XML. Recover the `town/lvup_status` parser/schema as its own route card before
implementing the allocation/status page.
