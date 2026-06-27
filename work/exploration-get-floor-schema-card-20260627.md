# Exploration Get Floor Schema Card, 2026-06-27

Route:
- `/connect/app/exploration/get_floor`

Frontier:
- Floor row click is already runtime-proven to emit this route with decrypted
  params `area_id=0`, `floor_id=2`, and `check=1`.
- This card covers only the response needed to enter `exploration_main`.

Static anchors:
- Floor row selection calls `_ExplorationModel::move(int, smart_ptr<FloorInfoTagData>, bool)`
  at `0x00341426`.
- `_ExplorationModel::move` calls `Model::connect(..., route_id=23, ...)`
  at `0x001d79fe`, matching the runtime `/exploration/get_floor` request.
- `_ExplorationModel` response handling compares body child `get_floor` at
  `0x001d6b6c`, then calls `_GetFloorTagParser::parse` at `0x001d6caa`.
- `_GetFloorTagParser::parse` starts at `0x003002c0`.
- `_ExplorationModel::init(GetFloorTagData)` starts at `0x001d58f8`.

Expected parent:

```xml
<body>
  <get_floor>
    ...
  </get_floor>
</body>
```

Confirmed request params:
- `area_id` | runtime decrypted value `0` | static string in move at `0x3d3594`.
- `floor_id` | runtime decrypted value `2` | static string in move at `0x3d359c`.
- `check` | runtime decrypted value `1` | static string in move at `0x3d3ee0`.

Confirmed response fields:
- `area_id` | int | parser compare at `0x00300456`.
- `bg` | string | parser compare at `0x00300466`.
- `bgm` | string | parser compare at `0x00300476`.
- `area_name` | string | parser compare at `0x00300486`.
- `next_exp` | int | parser compare at `0x00300496`.
- `next_floor` | int | parser compare at `0x00300436`.
- `floor_info` | nested `_FloorInfoTagParser` data | parser compare at `0x003004b0`.
- `special_item` | optional nested/scalar branch | parser compare at `0x00300446`; omitted from the minimal no-branch payload until its consumer is needed.

Minimal server payload:

```xml
<get_floor>
  <area_id>0</area_id>
  <bg>exp_sarch</bg>
  <bgm>bgm_sarch1</bgm>
  <area_name>Local Area</area_name>
  <next_exp>0</next_exp>
  <next_floor>0</next_floor>
  <floor_info>
    <id>2</id>
    <type>0</type>
    <unlock>1</unlock>
    <progress>1</progress>
    <cost>1</cost>
    <boss_id>0</boss_id>
    <found_item_list></found_item_list>
  </floor_info>
</get_floor>
```

Value notes:
- `next_scene=6200` comes from `rule_scene.xml`, where scene `6200` is
  `exploration_main`.
- `bgm_sarch1` and `exp_sarch` are local resource-backed candidates from the
  exploration resource family; runtime still has to prove rendering.
- `special_item` stays omitted because this pass is no-branch floor entry.

Rejected shapes:
- `<exploration_get_floor>` parent: no native compare evidence.
- Reusing `<exploration_floor>`: that is the floor-list parser branch at
  `0x001d6eb0..0x001d6f26`, not floor entry.
- Putting `floor_info` inside `floor_info_list`: `_GetFloorTagParser` compares
  direct child `floor_info`; the list wrapper belongs to `/exploration/floor`.

Runtime observable:
- After tapping floor row, `/exploration/get_floor` returns 200, no connection
  modal appears, and either `exploration_main` is visible or the client emits the
  next route.

Open questions:
- Exact `special_item` shape and no-item default.
- Exact `bg` value expected by `exploration_bg` beyond resource-backed candidate.
