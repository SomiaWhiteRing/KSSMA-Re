# Exploration FC2 Mechanics Card, 2026-06-27

Scope: external mechanics/value-domain evidence only. Do not merge these values into server responses until native schema and current client route mapping agree.

## Source

- 3DS版 拡散性ミリオンアーサー 攻略Wiki / FC2 pages fetched after JP VPN became available.
- Raw HTML cache: `work/external-data/raw/fc2-ma3ds/pages/`.
- Normalized JSON: `work/external-data/normalized/fc2-exploration-regions.json`.
- Version note: zh-Fandom says the early mobile data had six open regions; FC2 3DS data adds `天に至る氷壁` as a seventh main region. Treat region 7 as cross-version evidence until the local client/master mapping proves it belongs in the current CN baseline.

## Region Summary

| # | region | areas | AP range | total AP | guardian | guardian HP | guardian reward | next |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 人魚の断崖 | 6 | 1-3 | 194 | 特殊型ロウエナ | 15088 | 特殊型ロウエナ | 燐光の湖 |
| 2 | 燐光の湖 | 9 | 2-4 | 398 | 支援型リュネット |  | 支援型リュネット | 錯乱の平原 |
| 3 | 錯乱の平原 | 10 | 2-4 |  | 支援型オルトリート |  | 支援型オルトリート（ホロ） | 叡智の草原 |
| 4 | 叡智の草原 | 10 | 3-5 |  | 試作型ヴォーティガーン |  | 試作型ヴォーティガーン（ホロ） | 猛獣の砂丘 |
| 5 | 猛獣の砂丘 | 15 | 3-5 |  | 第二型コルグリヴァンス | 39008 | 第二型コルグリヴァンス | 祝福を授ける山 |
| 6 | 祝福を授ける山 | 20 | 4-6 | 5728 | 支援型エヴェイン | 45632 | 支援型エヴェイン |  |
| 7 | 天に至る氷壁 | 25 | 3-7 | 9366 | グルアガッハ | 1500000 | グルアガッハ |  |

## First Region Rows

| area | AP cost | EXP/move | Gold/move | moves to clear | total AP | rewards | progress/move |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 3 | 16-20 | 10 | 10 | 第二型マロース / 特殊型グリンゴレット | 10% |
| 2 | 2 | 6 | 30-40 | 11 | 22 | 第二型カエルダン / 因子の欠片(妖精の軍神) | 9.090909% |
| 3 | 2 | 6 | 30-40 | 12 | 24 | 第二型マロース / 因子の欠片(妖精の軍神) | 8.333333% |
| 4 | 2 | 6 | 30-40 | 15 | 30 | 第二型マロース / 第二型カエルダン | 6.666667% |
| 5 | 3 | 9 | 50-60 | 16 | 48 | 第二型マロース / 因子の欠片(妖精の軍神) | 6.25% |
| 6 | 3 | 9 | 50-60 | 20 | 60 | 第二型カエルダン / 第二型マロース | 5% |

## Mapping Notes

- `floor_info.cost` matches the AP cost column, not an arbitrary UI label.
- `/exploration/explore` should eventually return nonzero `gold` and `get_exp` on every normal forward step.
- `progress` should be derived from a required-move counter per area. The current server's one-percent-per-click behavior is a debug shim, not faithful game logic.
- `found_item_list` and reward/event branches should be driven by each row's card/factor slots, but branch enum and nested reward payloads still require native/parser evidence.
- Guardian data is a region-completion gate after the last normal area, not a normal walking-step field.
- FC2 gives exact Gold ranges for AP 1-4 rows, but several AP 5-6 rows are written as `15EXP/～Gold` or `18EXP/～Gold`; keep EXP as strong evidence and leave those Gold bounds open.

## Evidence Strength

- Strong: first two regions have complete per-area AP, EXP, Gold, required-move, required-total-AP, reward-slot, and next-region data.
- Strong: first region guardian has HP/EXP/Gold/reward-card data; several later guardian HP/Gold cells are blank on the page and remain open.
- Medium: later regions still provide AP/EXP/reward slots, but many required-move cells are literal `？` in the source page.
- Cross-source: zh-Fandom supplies the formula and event categories; FC2 supplies concrete table values. The two agree on EXP = AP x 3 and Gold roughly scaling with AP.

## Current Server Mismatch

- Current `/get_floor.next_floor` increments both `area_id` and `floor_info.id`; FC2 user-facing data says normal progress advances area rows within a region before the guardian. Treat current id movement as client-accepted diagnostics until native/master ID mapping is recovered.
- Current `/exploration/explore` returns `gold=0` and `get_exp=0`; FC2 and zh-Fandom both say normal walking always yields EXP and Gold.
- Current background value remains unresolved; FC2 mechanics pages do not identify client resource names for `get_floor.bg`.

## Suggested Next Implementation Frontier

Do not start with battle/fairy/reward branches. The smallest faithful improvement is a no-branch walking table for the first region:

- Keep current accepted hierarchy/native patch unchanged.
- Add a tiny in-memory exploration state keyed by the request IDs after native/master ID mapping is checked.
- For normal `/exploration/explore`, return `get_exp = cost_ap * 3`, a deterministic Gold value inside the FC2/Fandom range, and progress derived from `move_count / required_moves`.
- Only after this is accepted should reward/factor/player/fairy event_type values be recovered from native parser/UI branches.

