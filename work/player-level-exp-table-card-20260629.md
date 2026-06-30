# Player Level EXP Table Card, 2026-06-29

## Frontier

Recover a player level EXP table before implementing exploration level-up.

The goal is not to pretend a complete original mobile table exists. The current result is a
source-ranked table that lets server code use only rows with acceptable evidence.

## Sources Checked

- Mobile atwiki:
  `https://w.atwiki.jp/kssma/pages/43.html`
  fetched through:
  `https://r.jina.ai/http://r.jina.ai/http://https://w.atwiki.jp/kssma/pages/43.html`
- 3DS FC2:
  `https://ma3ds.wiki.fc2.com/wiki/%E3%83%AC%E3%83%99%E3%83%AB`
- zh-Fandom:
  `https://kssma.fandom.com/zh/wiki/%E6%96%B0%E6%89%8B%E6%8C%87%E5%8D%97`
- Local normalized cache:
  `work/external-data/normalized/kssma-external.jsonl`

## Outputs

- Raw mobile mirror: `work/recovered-data/mobile-atwiki-player-info.md`
- Raw FC2 page: `work/recovered-data/fc2-3ds-player-level-page.html`
- FC2 extracted table: `work/recovered-data/fc2-3ds-player-level-table.json`
- FC2 extracted TSV: `work/recovered-data/fc2-3ds-player-level-table.tsv`
- Merged source-ranked evidence table: `work/recovered-data/player-level-exp-table.json`
- Merged TSV: `work/recovered-data/player-level-exp-table.tsv`
- Game data copy: `server/data/game/player-level-exp-table.json`

## Confirmed Mobile Mechanics

- Level-up fully recovers AP and BC.
- Level-up grants AP/BC allocation points.
- Mobile atwiki wording says 3 points, and from level 50 onward 2 points.
- Friend count gives 3 allocation points per added friend.

## Mobile EXP Rows

The original mobile atwiki table is sparse. Confirmed next-level EXP rows:

| level | next EXP |
| --- | ---: |
| 17 | 2000 |
| 18 | 2100 |
| 19 | 2200 |
| 20 | 2300 |
| 21 | 2400 |
| 22 | 2500 |
| 23 | 2600 |
| 24 | 2700 |
| 25 | 2800 |
| 26 | 3000 |

Rows 1-16 and 27-80 are mostly blank in the mobile page.

## Candidate Table Strength

`work/recovered-data/player-level-exp-table.json` stores evidence rows with `sourceRank`.
`server/data/game/player-level-exp-table.json` is the clean runtime baseline and must not
store source/provenance fields.

Counts:

- `mobile_exact`: 10 rows.
- `fc2_3ds_exact`: 101 rows.
- `fc2_3ds_uncertain`: 2 rows.
- `pattern_inferred_from_fc2`: 79 rows.
- `missing`: 8 rows.

Missing rows:

```text
10, 11, 12, 13, 14, 15, 16, 200
```

Uncertain FC2 rows:

```text
41, 48
```

## Implementation Rule

For product code, only these rows are acceptable by default:

```text
mobile_exact
fc2_3ds_exact
```

Do not use `fc2_3ds_uncertain`, `pattern_inferred_from_fc2`, or `missing` unless a future
test explicitly opts into candidate behavior and labels the result as non-original.

## Runtime Candidate

Use a level with a trusted table row to avoid test-only thresholds. A practical first smoke:

```text
level = 17
profile.exp = 1997
nextExp = 2000
one AP=1 exploration move gives get_exp=3
expected after move: level 18, profile.exp carryover 0, nextExp 2100
lvup=1, is_limit=0, AP/BC full, +3 allocation points
```

This uses direct mobile atwiki values for both the current and next level threshold.

## Runtime Result

Accepted artifact:

```text
work/kssma-flow-exploration-levelup-smoke-20260630-002346
```

The Lv17 runtime candidate passed. The server logged `levelUp=true`, `isLimit=false`,
`beforeLevel=17`, `level=18`, `profileExp=0`, `nextExp=2100`, `remainingAp=25`,
`abilityPoints=3`, `abilityPointsGranted=3`, and `thresholdSourceRank=mobile_exact`.

The client then requested `/connect/app/town/lvup_status`; that route is outside this table
card and needs its own schema recovery.

## Open Questions

- Full original mobile EXP table beyond the sparse atwiki rows.
- Whether early tutorial levels 1-4 follow the same table on this CN client.
- Max-level behavior and `lvMaxData`.
- Growth rewards for level-up are not part of `/exploration/explore` until a route/schema proves them.
