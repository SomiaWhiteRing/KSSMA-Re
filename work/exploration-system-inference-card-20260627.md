# Exploration System Inference Card, 2026-06-27

Scope:
- External mechanics plus current native/protocol mapping.
- This is a value-domain and implementation-planning card, not a server patch.
- Do not change `server/bootstrap-server.js` from this card alone; route fields still need parser/native proof when branch UI is involved.

## Sources Checked

Primary cached sources:
- FC2 3DS wiki exploration overview: `https://ma3ds.wiki.fc2.com/wiki/%E6%8E%A2%E7%B4%A2`
- FC2 region pages cached under `work/external-data/raw/fc2-ma3ds/pages/`.
- Normalized FC2 table: `work/external-data/normalized/fc2-exploration-regions.json`.
- zh-Fandom `探索`: `https://kssma.fandom.com/zh/wiki/%E6%8E%A2%E7%B4%A2`
- zh-Fandom `新手指南`: `https://kssma.fandom.com/zh/wiki/%E6%96%B0%E6%89%8B%E6%8C%87%E5%8D%97`

Supplementary non-wiki sources:
- 4399 exploration intro: `https://news.4399.com/news/shouyou/254664.html`
- 962 exploration guide: `https://www.962.net/gl/63980.html`
- Gamebiz 2014 update/campaign note: `https://gamebiz.jp/news/131618`

Attempted but not usable this round:
- NGA thread `https://bbs.nga.cn/read.php?tid=6298020`: 403.
- atwiki candidate `https://w.atwiki.jp/kssma/pages/16.html`: 403. Existing project note keeps atwiki as manual cross-check only.

## Confirmed System Formulas

Normal move:
- Consumes `cost_ap`.
- Player EXP: `cost_ap * 3`.
- Rare EXP: `cost_ap * 15`.
- Gold: random value in `[cost_ap * 16, cost_ap * 20]`.
- Rare Gold: random value in `[cost_ap * 80, cost_ap * 100]`.

Recovery/event values:
- AP recovery event: `cost_ap`; rare AP recovery: `cost_ap * 5`.
- BC recovery event: `ceil(cost_ap * 1.5)`; rare BC recovery: `ceil(cost_ap * 1.5) * 5`.
- Other-player encounter: FC2 and `新手指南` agree on friendship/bond points `cost_ap * 4`; old zh-Fandom `探索` text also says 10 points, so treat fixed 10 as platform/version conflict until native UI proof.
- Fairy/strong-enemy and event-item branches are limited-event behavior, not baseline walking behavior.

Progress display:
- Floor/current-area progress is truncated, not rounded:
  `floor_progress_pct = floor(done_moves * 100 / required_moves)`.
- Region/secret-area list progress is also truncated:
  `region_progress_pct = floor(sum_done_moves * 100 / sum_required_moves)`.
- FC2 examples: `1 / 8 = 12.5%` displays `12%`; `8 / 108 = 7.40%` displays `7%`.

Recovery timers:
- AP recovers 1 every 3 minutes.
- BC recovers 1 every 1 minute.

Guardian:
- Region clear requires all normal areas plus the region guardian.
- Guardian battle consumes no BC.
- Excalibur does not fire and SUPER gauge does not increase.
- Retry fully restores guardian HP.
- Main-story guardian reward is usually the guardian holo card and unlocks the next region.

## Region Data Strength

FC2 normalized summary:
- Regions parsed: 7.
- Normal areas parsed: 95.
- AP costs observed: 1 through 7.
- Known total required AP: 15686 across pages with explicit totals.

Version split:
- zh-Fandom early mobile/CN table says 6 open regions and 70 rows.
- FC2 3DS table adds region 7, `天に至る氷壁`, with 25 areas and guardian `グルアガッハ`.
- Therefore: implement current CN baseline from the six-region table first; keep region 7 as cross-version evidence.

Strong first-region table:

| user area | AP | EXP | Gold | required moves | total AP | first displayed progress |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 3 | 16-20 | 10 | 10 | 10, 20, 30, 40, 50... |
| 2 | 2 | 6 | 30-40 | 11 | 22 | 9, 18, 27, 36, 45... |
| 3 | 2 | 6 | 30-40 | 12 | 24 | 8, 16, 25, 33, 41... |
| 4 | 2 | 6 | 30-40 | 15 | 30 | 6, 13, 20, 26, 33... |
| 5 | 3 | 9 | 50-60 | 16 | 48 | 6, 12, 18, 25, 31... |
| 6 | 3 | 9 | 50-60 | 20 | 60 | 5, 10, 15, 20, 25... |

First-region aggregate:
- Normal walking required moves: 84.
- Normal walking required AP: 194.
- Guardian area: 7.
- Guardian: `特殊型ロウエナ`, HP `15088`, reward `特殊型ロウエナ` holo.

## Mapping To Current Protocol

Current accepted request flow:
- `/connect/app/exploration/area`
- `/connect/app/exploration/floor`
- `/connect/app/exploration/get_floor`
- `/connect/app/exploration/explore`
- `/connect/app/exploration/get_floor` when the visible next-area button is tapped.

Field mapping:

| Game concept | Current protocol field | Confidence | Notes |
| --- | --- | --- | --- |
| region/secret-area progress | `/exploration/area area_info.prog_area` | medium | Formula known, but current server has only one diagnostic area. |
| collection progress | `/exploration/area area_info.prog_item` | medium | 962 confirms the second percent is card collection; exact item ownership mapping is later. |
| current floor/area AP cost | `floor_info.cost` | high | Native parses it and FC2 row AP values match purpose. |
| current floor progress | `floor_info.progress`, `get_floor.floor_info.progress`, `explore.progress` | high | Native parses these; value formula now known. |
| current floor clear successor | `/get_floor.next_floor` nested object | high | Runtime accepted this as the floor-clear predicate source. |
| step EXP | `/exploration/explore get_exp` | high | Parser-confirmed field; formula known. |
| step Gold | `/exploration/explore gold` | high | Parser-confirmed field; formula/range known. |
| AP/BC recovery | `/exploration/explore recover` plus `event_type` | medium | Parser-confirmed scalar exists; event enum and UI branch still need native proof. |
| other-player encounter | `/exploration/explore friendship_point`, `encounter`, maybe `user` | medium | Parser-confirmed fields exist; nested user payload still unknown. |
| card/factor reward | `found_item_list`, `parts_one`, `parts_complete`, `user_card`, `autocomp_card` | low-medium | External slots known; branch XML shape and enum need native proof. |
| guardian | `boss_id`, boss/battle routes/layouts | low-medium | External rules known; route and battle payload are separate frontier. |
| exploration background | `/get_floor bg` -> `exploration_bg.bgName` | medium schema, low value | `exp_sarch` is resource-backed but not visually accepted; wiki `area1.jpg` maps to list/map art, not proven walking bg. |

## Safe Next Server Model

The smallest faithful improvement is a no-branch walking model for the first region only.

Implementation shape:
- Keep the accepted native hierarchy patch unchanged.
- Keep `/area`, `/floor`, `/get_floor`, `/explore` route structure unchanged.
- Add an in-memory table for first-region normal rows after current ID mapping is checked.
- For no-branch `/exploration/explore`:
  - `event_type=0`
  - `encounter=0`
  - `recover=0`
  - `friendship_point=0`
  - `get_exp = cost_ap * 3`
  - `gold = deterministic value inside [cost_ap * 16, cost_ap * 20]`
  - `progress = floor(done_moves * 100 / required_moves)`
  - keep `next_floor=0` inside `explore`, because runtime proved floor-clear uses `/get_floor.next_floor`.

Recommended deterministic Gold for local baseline:
- Use a stable midpoint to avoid randomness in tests:
  `gold = floor(cost_ap * 18)`.
- This sits inside the confirmed normal range for all integer AP costs.
- Upgrade path: replace with seeded RNG once save persistence and replay policy exist.

Next-floor predicate:
- `/get_floor` must advertise the successor through nested `next_floor` before the current area reaches 100%.
- On a 100% explore response, the client reads the previously populated `/get_floor.next_floor` and shows the accepted `进入下一个区域` button.
- The current server increments both `area_id` and `floor_info.id`; that is runtime-accepted but semantically suspect.
- Do not change ID movement until native/master mapping explains why current visible `区域 1` request uses `floor_id=2`.

## Open Questions Before Branches

Do not implement from external docs alone:
- Event probabilities for rare EXP/Gold/AP/BC/card/factor/player/fairy.
- `event_type` enum values and which values drive each branch.
- Nested `user`, `user_card`, `autocomp_card`, `parts_one`, `special_item`, `fairy`, and `rare_fairy` shapes.
- Guardian battle route and battle response schema.
- The exact current-client ID mapping between `area_id`, `floor_id`, displayed `区域 N`, and external row numbers.
- `next_exp` value source.
- Correct `/get_floor.bg` for each region/floor.

## Conclusion

The next productive implementation frontier is:

```text
exploration_main no-branch forward -> faithful first-region progress/EXP/Gold
```

Not:

```text
random event branches, guardian battle, background value, or all-region persistence
```

The reason is practical: normal walking fields are already parser-confirmed and externally formula-backed. Branch events and guardian flows have enough gameplay description, but not enough protocol shape.
