# Exploration Command -> Route Map

Date: 2026-06-26

Frontier: after `floor_list` becomes visible, avoid blind runtime clicks by mapping
exploration layout commands to native route owners, request parameters, and confidence.

Static anchor: `layout_exploration_area.xml`, `layout_exploration_main.xml`,
`layout_exploration_boss.xml`, `layout_exploration_fairy.xml`, existing
`work/*exploration*` / `work/*annotated*` notes, and `reverse-notes.md`.

Observable wanted later: the next HTTP route and decrypted request after floor-row,
forward, next-floor, and return actions.

## Evidence Summary

- `reverse-notes.md` route list contains:
  `exploration/area`, `exploration/floor`, `exploration/get_floor`,
  `exploration/explore`, `exploration/battle`, `exploration/fairyhistory`,
  `exploration/fairy_floor`, `exploration/boss_floor`,
  `exploration/fairy_lose`, `exploration/fairybattle`.
- `layout_exploration_area.xml` has behavior `get_floor` with
  `<command name="floor"/>`; the area scene native update path triggers layout
  behavior `get_floor`, then `_ExplorationModel::floor(int)`.
- `_ExplorationModel::floor(int)` builds a parameter map containing `area_id`
  and calls `Model::connect(0x15, params)`.
- Runtime notes already prove that selecting the local area produces
  `POST /connect/app/exploration/floor?cyt=1` with decrypted `area_id=0`.
- `_ExplorationModel::update(TiXmlElement)` has parser branches for
  `exploration/explore` via `_ExploreTagParser` and for the floor response via
  `_ExplorationFloorTagParser`.
- The allowed exploration annotations show only one explicit `Model::connect`
  call in exploration command code: `_ExplorationModel::floor`.

Address anchors from current annotations:

- `layout_exploration_area.xml:210`: `<command name="floor"/>`.
- `layout_exploration_main.xml:116-124`: `next_floor`, `foward`,
  `foward2`, `back`, and `return_town` button commands.
- `layout_exploration_boss.xml:81,420,532`: `battle`, `boss_lose`,
  and `reward_check`.
- `layout_exploration_fairy.xml:51,90,540`: `fairyHistory`, `battle`,
  and `boss_lose`.
- `work/exploration-annotated-strings.txt:312`: `0x00341384` loads
  string `get_floor` before triggering the layout behavior.
- `work/exploration-ui-disasm-annotated.txt:186-189`: `0x00340a90`
  calls `_ExplorationModel::floor(int)`, then `LayoutScene::trigger(model)`.
- `work/exploration-annotated-strings.txt:920,975`: `_ExplorationModel::floor`
  loads `area_id` at `0x001d7b00` and calls `Model::connect` at `0x001d7b80`
  with route id `0x15`.
- `work/exploration-ui-disasm-annotated.txt:583-586`: floor-row selection
  calls `_ExplorationModel::move(area_id, floor_info, false)` at `0x00341426`,
  then `LayoutScene::trigger(model)`.
- `work/exploration-model-update-disasm.txt:69,121,211`: update branch
  sees route text fragment for `exploration/explore`, calls `_ExploreTagParser`,
  and separately calls `_ExplorationFloorTagParser` for floor responses.
- `work/exploration-ui-disasm-annotated.txt:683-692`: area-page return path
  calls `_TownModel::mainmenu()` at `0x00341514` then triggers the model.

## Mapping Table

| Layout file | Command/action | Native owner | Route string | Request parameter source | Confidence | Gap |
| --- | --- | --- | --- | --- | --- | --- |
| `layout_exploration_area.xml` | behavior `get_floor` -> `<command name="floor"/>` | `_ExplorationArea::update` triggers `get_floor`; `_ExplorationModel::floor(int)` builds params and calls `Model::connect(0x15, params)` | `exploration/floor` | `area_id` from selected area/focus. Runtime proof: decrypted `area_id=0` after selecting `Local Area`. | High | This is the area -> floor-list fetch, not the later floor-row enter action. |
| `layout_exploration_area.xml` | floor-row selection in `floor_list` (no explicit XML command) | `_ExplorationArea::update` state-2 path copies `model+0x58` floor vector, bounds-checks selected row, then calls `_ExplorationModel::move(area_id, floor_info, false)` and `LayoutScene::trigger(model)` | Unknown. Candidate route family: `exploration/get_floor` or `exploration/explore`. | Selected `floor_info` from `floor_info_list`, plus current `area_id`; exact POST keys not recovered. | Medium for native owner, Low for route | `_ExplorationModel::move` body/connect id is not present in the allowed annotations. This is the main missing edge for "click a floor row". |
| `layout_exploration_main.xml` | button `forward`, command `foward` | Not found in allowed native annotations. Response owner exists: `_ExplorationModel::update` branch for `exploration/explore` -> `_ExploreTagParser` -> `_ExplorationModel::init(ExploreTagData)`. | `exploration/explore` | Current exploration state, likely area/floor/progress/AP; exact keys not recovered. | Medium | Command-to-connect call is missing. The route is inferred from route string plus response parser, not from the button handler. |
| `layout_exploration_main.xml` | button `forward2`, command `foward2` | Same as `foward`; no separate native connect body found. | `exploration/explore` | Same as `foward`; likely the cleared-floor variant of the same explore request. | Medium | Need handler/connect disasm or runtime click after floor list works. |
| `layout_exploration_main.xml` | button `next_floor`, command `next_floor` | Not found in allowed native annotations. | Unknown. Candidate route family: `exploration/get_floor`, `exploration/floor`, or `exploration/explore`. | Likely current/next floor id from `floorInfo`; exact keys not recovered. | Low | No native command handler or `Model::connect` evidence in allowed files. Keep this open before implementing any server route. |
| `layout_exploration_area.xml` | right-side `back` / `back_mainmenu` buttons, no explicit command attribute | `_ExplorationArea::update` uses `isBackKeyPush`; state-0 path calls `_TownModel::mainmenu()` then `LayoutScene::trigger(model)`. Runtime notes prove return button produced `/connect/app/mainmenu` and reached main menu. | `mainmenu` (`/connect/app/mainmenu`) | No decrypted request params observed. | High for area-page return | This evidence is for area-page return/back, not necessarily the walking-scene `back` command. |
| `layout_exploration_main.xml` | button `back`, command `back`; behavior `return` -> `<command name="back"/>` | Not found in allowed native annotations. | Unknown; likely local return to area/floor selection or town-mainmenu transition depending state. | Unknown. | Low | Do not assume it is `/connect/app/mainmenu`; only area-page return has runtime proof. |
| `layout_exploration_main.xml` | button `return_town`, command `return_town` | Not found in allowed native annotations. | Probable `mainmenu` by UI meaning and area-page return evidence, but not statically closed for this layout. | Unknown. | Medium-Low | Need walking-scene command handler or runtime click after entering floor. |
| `layout_exploration_boss.xml`, `layout_exploration_fairy.xml` | button `battle`, command `battle` | Boss/fairy layouts expose `battle`; `bcCheck`/`bcCheck2` behaviors gate battle standby. Native command handler not found in allowed annotations. | Candidate: `exploration/battle` for normal boss; `exploration/fairybattle` for fairy. | Boss/fairy ids and battle state from `exp_model`/`fairy_model`; exact keys not recovered. | Low | Separate boss/fairy route pass needed. |
| `layout_exploration_fairy.xml` | `exploration_fairy` component command `fairyHistory` | Layout binding only; native command handler not found. | Candidate: `exploration/fairyhistory` | Likely fairy boss/discoverer fields from `fairy_model`; exact keys not recovered. | Medium-Low | Name match is strong, but no connect call or params found. |
| `layout_exploration_boss.xml`, `layout_exploration_fairy.xml` | behavior `boss_lose_dialog` -> `<command name="boss_lose"/>` | Layout command only; native command handler not found. | Unknown. No `exploration/boss_lose` route string in the extracted list. | Unknown. | Low | `boss_floor` exists as a route string, but mapping from `boss_lose` is unproven. |
| `layout_exploration_boss.xml`, `layout_exploration_fairy.xml` | behavior `fairy_lose`; fairy layout also has `fairy_lose_move` command | Layout behavior/command only; native command handler not found. | Candidate: `exploration/fairy_lose` for lose reporting or assist flow. | Fairy ids/state from `fairy_model`; exact keys not recovered. | Low | Layout uses `fairy_lose_move`, not plain `<command name="fairy_lose"/>`; route binding remains open. |
| `layout_exploration_boss.xml` | behavior `reward_check_com` -> `<command name="reward_check"/>` | Layout command only; reward behavior later runs `levelCheck`; `_ExplorationModel::update` also has `BonusModel`/`BonusListTagParser` branches. | Unknown. No `exploration/reward_check` route string in extracted list. | Battle/result state; exact source not recovered. | Low | Likely local post-battle gate or bonus parser trigger, but no HTTP route is proven. |

## Priority Stop Status

The four priority commands have enough confidence to stop this D pass without
runtime or server changes:

- `floor` as area -> floor-list fetch: High, route `exploration/floor`, param `area_id`.
- floor-row click after list appears: native owner identified as `_ExplorationModel::move`,
  but route is open. This must not be implemented from a guess.
- `foward` / `foward2`: Medium, route `exploration/explore` by route string and
  response parser evidence; request keys and command handler are open.
- `next_floor`: Low, route open among `get_floor`/`floor`/`explore`.
- area-page `back`/return: High for `/connect/app/mainmenu`; walking-scene `back`
  and `return_town` remain open.

## Dead Ends Recorded

- Searching the allowed `work/*exploration*` and `work/*annotated*` files found no
  explicit `Model::connect` call for `foward`, `foward2`, `next_floor`, `battle`,
  `fairyHistory`, `boss_lose`, `fairy_lose`, or `reward_check`.
- `boss_lose` and `reward_check` do not have matching extracted route strings.
- `exploration/get_floor` exists in the native route list, but no allowed evidence
  ties it to floor-row click or `next_floor`.

## Next Smallest Action

Static: recover `_ExplorationModel::move(int, smart_ptr<FloorInfoTagData>, bool)`
and the command dispatch owner for `foward`/`next_floor`. The minimum target is the
`Model::connect` route id and parameter key strings.

Runtime, only after floor list is visible: click one floor row once and collect only
the next route plus decrypted request params. Do not add a server handler first.
