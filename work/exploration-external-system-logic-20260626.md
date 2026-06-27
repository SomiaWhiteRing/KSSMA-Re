# Exploration External System Logic

Generated: 2026-06-27T09:43:47.724Z

## Frontier

exploration/floor returns 200 and createFloorList builds a non-empty scene vector, but floor_list is still not visible.

This card is external evidence only. It names original-game mechanics and value-domain candidates; it does not authorize changing `server/bootstrap-server.js` without native/schema proof.

## Sources

- 探索 pageid=117, revid=7930, timestamp=2013-08-25T08:56:49Z, sha256=3387abf36af377515a9d191405035480ca69076efed1f663f1d5fd85c5c607a1
  - https://kssma.fandom.com/zh/wiki/%E6%8E%A2%E7%B4%A2
- 新手指南 pageid=110, revid=14604, timestamp=2014-04-22T12:45:47Z, sha256=a51505872b5c4ecb3bb03c3e4249dee2793d6824f7395e12b35f342c737cab7d
  - https://kssma.fandom.com/zh/wiki/%E6%96%B0%E6%89%8B%E6%8C%87%E5%8D%97

## System Logic Extracted

- Exploration is the main early source of Gold and EXP.
- The user-facing progression is region -> area/floor -> walking progress -> 100% -> next area/floor.
- Each move consumes AP; the zh wiki gives EXP as AP cost times 3 and Gold as AP cost times 20 times a random 0.8-1.0 multiplier.
- Each move also rolls one side event: AP recovery, BC recovery, fairy encounter during fairy events, card reward, factor fragment, other-player encounter, or no extra event.
- Region completion is separate from a normal floor row: all areas/floors plus the guardian must be cleared before the next region opens.
- Beginner guide cross-check: AP recovers 1 every 3 minutes; BC recovers 1 every 1 minute; card inventory cap 350 can block exploration and gacha.

## Structured Region Data

| # | region | image | guardian | factor | floors | AP costs | factor floors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 人魚の断崖 | File:area1.jpg | 特殊型ロウエナ | ルー | 6 | 1-3 | 3 |
| 2 | 燐光の湖 | File:area2.jpg | 支援型リュネット | 支援型パンジー | 9 | 2-4 | 4 |
| 3 | 錯乱の平原 | File:area3.jpg | 支援型オルトリート | 試作型リエンス | 10 | 2-4 | 4 |
| 4 | 叡智の草原 | File:area4.jpg | 試作型ヴォーティガーン | 試作型ブランデゴリス | 10 | 3-5 | 4 |
| 5 | 猛獣の砂丘 | File:area5.jpg | 第二型コルグリヴァンス | 鹵獲型魔女のエレイン | 15 | 3-5 | 6 |
| 6 | 祝福を授ける山 | File:area6.jpg | 支援型エヴェイン | シェリーコート | 20 | 4-6 | 8 |

Full structured data is written to `work/external-data/normalized/exploration-focus.json`.

## First Region Floor Rows

| region | floor | AP | item1 | item2 | item3 |
| --- | --- | --- | --- | --- | --- |
| 人魚の断崖 | 1 | 1 | 第二型マロース | 特殊型グリンゴレット | 無 |
| 人魚の断崖 | 2 | 2 | 第二型カエルダン | 因子碎片 | 無 |
| 人魚の断崖 | 3 | 2 | 第二型マロース | 因子碎片 | 無 |
| 人魚の断崖 | 4 | 2 | 第二型マロース | 第二型カエルダン | 無 |
| 人魚の断崖 | 5 | 3 | 第二型マロース | 因子碎片 | 無 |
| 人魚の断崖 | 6 | 3 | 第二型カエルダン | 第二型マロース | 無 |

## Mapping To Current Blocker

| External fact | Local protocol implication | Server action now |
| --- | --- | --- |
| Wiki has 6 regions and per-region area/floor tables | `/exploration/area` should eventually expose multiple regions/locations, but the current one-area baseline is a diagnostic stub | Do not expand area list until floor_list renders |
| Each area/floor has an AP consumption value | `floor_info.cost` is an AP-cost value-domain candidate; current `cost=1` matches the first listed floor | Do not sweep costs; the visible row is missing even with a non-empty scene vector |
| Each area/floor has three item/factor slots, with slot 1 most common and slot 3 least common | `found_item_list` likely drives row reward icons or later reward pools | Do not fake found items for visibility; native evidence says empty found items still continue row construction |
| Progress reaches 100% before the next area/floor | `progress` belongs to walking/floor progress, not to the existence of a selectable row | Keep `progress=0` as a valid unopened/current-floor state until a consumer proves otherwise |
| Guardians gate region completion | `boss_id`/guardian data is later boss/clear logic | Do not use boss data to debug the missing floor_list row |

## Next Smallest Observable

The external data points away from schema/value guessing and toward the later UI consumer:

- Instrument `_PickList::setPropertyValues` to prove whether this component receives a `list` property whose value is `floor_list`.
- Instrument `_PickList::setRecords` to prove whether it is called with the scene `floor_list` vector pointer and positive count.
- Only if `setRecords` receives positive records but draws nothing should the next branch inspect `_AnmExplorationList` item fields such as type/unlock/progress/cost visuals.

## Do Not Repeat

- No `floor_info/id` sweep; id 1 was already tested and failed.
- No empty-vector/parser chase; runtime proved `_ExplorationModel+0x58` count is greater than 0.
- No post-data `floor_list_active2`, update-all, or direct `updateProperty(floor_list)` retry without a new PickList observable.
- No server merge from wiki values before native parser/schema and runtime observables agree.

