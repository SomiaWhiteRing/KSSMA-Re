# Exploration Explore Schema Card, 2026-06-27

Route:
- `/connect/app/exploration/explore`

Frontier:
- This card updates the older 2026-06-26 card with direct parser evidence.
- It only supports a no-branch walking response. Battle, fairy, reward, parts,
  card, and floor-clear flows remain later frontiers.

Static anchors:
- `_ExplorationModel::update(TiXmlElement*)` compares direct body child `explore`
  at `0x001d6de6` and again at `0x001d702e`.
- Both paths call `_ExploreTagParser::parse` at `0x002f9a64`, then
  `_ExplorationModel::init(ExploreTagData)` at `0x001d6700`.
- `_ExploreTagParser::parse` size is 4060 bytes in `librooneyj-symbols.txt`.

Expected parent:

```xml
<body>
  <explore>
    ...
  </explore>
</body>
```

Confirmed parser fields:
- `fairy`
- `rare_fairy`
- `next_floor`
- `user_card`
- `autocomp_card`
- `parts_one`
- `user`
- `special_item`
- `progress`
- `event_type`
- `gold`
- `friendship_point`
- `recover`
- `get_exp`
- `next_exp`
- `lvup`
- `is_limit`
- `complete`
- `parts_complete`
- `secret_unlock`
- `normal_unlock`
- `message`
- `fairy_pose`
- `fairy_face`
- `encounter`

Minimal no-branch server payload:

```xml
<explore>
  <progress>2</progress>
  <event_type>0</event_type>
  <gold>0</gold>
  <get_exp>0</get_exp>
  <next_exp>0</next_exp>
  <next_floor>0</next_floor>
  <friendship_point>0</friendship_point>
  <recover>0</recover>
  <encounter>0</encounter>
  <fairy_pose>2</fairy_pose>
  <fairy_face>5</fairy_face>
</explore>
```

Value notes:
- `next_scene=6200` comes from `rule_scene.xml` scene `exploration_main`.
- Zero branch/reward values are intentional: they should avoid prize, fairy,
  boss, card, and parts branches until those payloads are recovered.
- `progress=2` is a candidate forward-after-entry value. If runtime shows
  immediate floor-clear or no motion, next single-variable check is `progress`.
- `fairy_pose=2` and `fairy_face=5` reuse the already resource-backed main menu
  pixie baseline only to avoid missing-image surprises if the field is consumed.

Rejected shapes:
- `<exploration_explore>` parent: old card candidate only; corrected parser
  evidence shows the body child compare is `explore`.
- Treating layout names such as `bgName`, `bgmName`, `areaName`, `bossId`, or
  `fairyBossId` as wire names: the parser-confirmed wire names are snake_case
  and do not include those camelCase names in this pass.
- Adding `user_card`, `parts_one`, `autocomp_card`, `fairy`, `rare_fairy`, or
  `message` with guessed nested bodies: parser fields exist, but nested shape
  and no-event defaults are not closed.

Request params:
- Runtime-captured after `get_floor` reached `exploration_main`:
  - `area_id=0`
  - `floor_id=2`
  - `auto_build=1`
- Encrypted form body fixed in `server/test-bootstrap-server.js`:
  `area_id=NzgOGTK08BvkZN5q8XvG6Q%3D%3D%0A&auto_build=HJQrxs%2FKaF3hyO81WS2jdA%3D%3D%0A&floor_id=vEVHSbIy52rSa1oy06FUIg%3D%3D%0A`

Runtime observable:
- After `get_floor` reaches `exploration_main`, tapping the visible forward
  button should emit `/connect/app/exploration/explore`. The next acceptance
  check is no connection modal and either a visible progress/UI change, another
  route, or stable return to main menu.

Open questions:
- Exact forward request params.
- Which zero fields are safe omissions vs. required explicit zeroes.
- Exact no-branch value domain for `event_type`, `encounter`, and `progress`.
