# /connect/app/town/pointsetting schema card

## Frontier

After an ordinary exploration level-up, the accepted flow is:

```text
/connect/app/exploration/explore with lvup=1
-> /connect/app/town/lvup_status
-> player allocates AP/BC points
-> /connect/app/town/pointsetting
```

This card covers only the AP/BC allocation confirmation route.

## Native and layout evidence

- `_TownLvUpStatusScene::update(...)` handles the status page buttons from
  `layout_town_lvup_status.xml`.
- The layout contains AP/BC local controls:
  `ap_inc`, `ap_dec`, `ap_all`, `bc_inc`, `bc_dec`, and `bc_all`.
- Pressing the `ok` button reads the scene's current AP allocation counter and BC
  allocation counter, then calls `_TownModel::setPoint(int,int)`.
- `_TownModel::setPoint(int,int)` builds two integer string parameters and calls
  `Model::connect(0x5b, params)`.
- The route string table near the town model route list maps this request id to:

```text
town/pointsetting
```

## Request

Confirmed by runtime decrypted probe:

```text
ap=int
bc=int
```

The first level-up smoke allocates all three points to AP, so the expected runtime request is:

```text
ap=3
bc=0
```

The local server still accepts earlier `inc_ap`/`inc_bc` aliases defensively, but they are
not the accepted runtime key names.

## Minimal response candidate

No route-specific body parser was recovered for this pass. The current product candidate
persists the allocation in the player save, emits updated shared `your_data`, and returns to
the accepted main-menu scene:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<response>
  <header>
    <error><code>0</code></error>
    <session_id>local-town</session_id>
    <your_data>...</your_data>
    <next_scene>2100</next_scene>
  </header>
  <body>
    <mainmenu>...</mainmenu>
  </body>
</response>
```

For the first level-up smoke, persisted state should become:

```text
rank=18
ap.current=28
ap.max=28
bc.current=25
bc.max=25
free_ap_bc_point=0
apAllocated=3
bcAllocated=0
```

## Checks

Accepted checks:

```powershell
node .\server\test-bootstrap-server.js
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario self-check -Tag levelup-apbc-selfcheck
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-levelup-smoke -Tag levelup-accepted-runtime
```

The flow self-check includes:

```text
/connect/app/town/pointsetting ap=3 bc=0
-> nextScene=2100
-> apAllocated=3
-> remainingAbilityPoints=0
```

Runtime artifact:

```text
work/kssma-flow-exploration-levelup-smoke-levelup-accepted-runtime
```

## Open questions

- Whether the original service returned to main menu, a previous town page, or another
  level-up-related scene after point allocation.
- Max-level behavior and `is_limit=1`.
- Whether multi-level-up allocation batches need more than one status/pointsetting round.
