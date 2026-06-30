# /connect/app/town/lvup_status schema card

## Frontier

After a confirmed exploration level-up, the client requests:

```text
/connect/app/town/lvup_status
```

The current server returned the generic 501 in artifact:

```text
work/kssma-flow-exploration-levelup-smoke-20260630-002346
```

This card covers only the entry into the level-up status allocation page. AP/BC
point allocation and the OK/return path are covered by
`work/town-pointsetting-schema-card-20260630.md`.

## Native and resource evidence

- `_TownModel::townLvUp()` calls `Model::connect(0x5a, empty_params)` and then marks the
  town model syncing. The native string table contains `town/lvup_status`, matching the
  runtime route above.
- `_TownModel::townLvUpAnimation()` is a separate entry using another connect id and should
  not be conflated with this route.
- Bundled `rule_scene.xml` defines:

```xml
<scene id="84100" name="town_lvup_status_scene" layout="town_lvup_status">
  <cause name="battle_result"/>
  <cause name="adv_clear"/>
  <cause name="menu_player_information_own" suspend="true"/>
  <cause name="exploration_fairy_result"/>
  <cause name="exploration_main"/>
</scene>
```

- Bundled `rule_resource.xml` maps the scene resources:

```xml
<scene name="town_lvup_status_scene" scene_id="15000">
  <resources>
    <image name="adv_bg6.png"/>
    <image name="ae_cmn_lvup_status.png"/>
    <layout name="town_lvup_status.xml"/>
  </resources>
</scene>
```

- `layout_town_lvup_status.xml` contains an `ae_lvup_status` root and buttons
  `lvup_plus`, `lvup_minus`, `lvup_all`, and `lvup_ok`. The layout references scene-side
  booleans such as `ap_inc_disable`, `bc_inc_disable`, and lock flags; these are produced
  by the status scene from player state, not by a route-specific body parser found in this
  pass.
- `_TownLvUpStatusScene::init(...)` reads the global player object and initializes current
  free points/AP/BC allocation counters. `_AnmTownLvUp::draw(...)` also reads the player
  object for town level and renders the free/AP/BC counters.
- Native string table confirms `free_ap_bc_point`, which is already parsed by the shared
  `your_data` parser and emitted by current server headers.

## Minimal response candidate

The route can be a header-only connect/app response:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<response>
  <header>
    <error><code>0</code></error>
    <session_id>local-town</session_id>
    <your_data>...</your_data>
    <next_scene>84100</next_scene>
  </header>
  <body></body>
</response>
```

Confirmed fields:

- `header/error/code=0`
- `header/session_id`
- `header/your_data`, especially `rank`, `ap`, `bc`, `max_card_num`, and
  `free_ap_bc_point`
- `header/next_scene=84100`

No route-specific body fields are confirmed for this pass.

## Runtime acceptance

Accepted runtime:

```text
/exploration/explore levelUp=true
-> /connect/app/town/lvup_status
-> encrypted 200 response with next_scene=84100 and upgraded your_data
-> client advances past generic network error into the level-up status page
-> /connect/app/town/pointsetting ap=3 bc=0
```

Accepted artifact:

```text
work/kssma-flow-exploration-levelup-smoke-levelup-accepted-runtime
```

## Open questions

- Whether the level-up animation scene `84200` must be requested/entered before or after
  the allocation scene in all sources.
