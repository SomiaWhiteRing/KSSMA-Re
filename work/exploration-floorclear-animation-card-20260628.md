# Exploration Floor-Clear Animation Card, 2026-06-28

Frontier:
- Verify the normal exploration edge:
  `人魚の断崖 区域5 -> progress 100 -> floor-clear animation/buttons -> 人魚の断崖 区域6`.
- This pass is not guardian, battle, fairy, reward, or background work.

Known-good setup:
- Accepted hierarchy is `main menu -> area list -> floor list -> exploration_main`.
- `flow -Scenario exploration-walk-smoke` already proved entering `人魚の断崖 地区6`
  and walking twice.
- The default top floor row is `区域6`, the last normal row of the first region.
  It is not suitable for validating ordinary next-area flow because completion may
  become a guardian frontier.

Static evidence:
- `work/million_cn/apktool/assets/bundle/layout_exploration_main.xml`
  defines:
  - `exploration_floor_clear name="floor_clear"` with params `floorInfo`,
    `bossId`, `fairyBossId`, `eventType`, `rareFairyFlg`, and `before_boss_id`.
  - `button type="new_next_floor" name="next_floor" command="next_floor"`.
  - behavior `floor_clear_button`, which makes `next_floor`, `forward2`, `back`,
    and `return_town` visible/open.
  - behavior `floor_clear`, which hides normal HUD, makes `floor_clear` visible,
    and runs `action target="floor_clear" name="clear_floor"` before reopening
    the clear-state buttons.
- `work/exploration-floorclear-conditions-20260627.txt` shows two native paths
  that call the model predicate at `0x001d519c` and, when true, trigger layout
  behavior string `floor_clear_button` at `0x0034577c` and `0x00347358`.
- `work/exploration-get-floor-schema-card-20260627.md` records that the predicate
  checks model progress `== 100`, then requires a non-null parsed `next_floor`
  object whose first integer is nonzero.

Server/tooling support added:
- `KSSMA_EXPLORATION_MOVES_SEED` is a flow-only JSON object merged into
  process-local exploration progress. Default server startup does not set it.
- `exploration-floor-clear-smoke` starts the server with `{"4:6":15}`, so
  `人魚の断崖 区域5` is one move away from its `16` required moves.
- `/connect/app/exploration/get_floor` logs `progress`, `hasNextFloor`,
  `nextFloorKey`, `nextFloorId`, `nextAreaNo`, and `nextRouteAreaId`.
- `/get_floor` request resolution now accepts the next-floor command shape
  where `area_id` is a route-area id and `floor_id` is the visible area number.
  This is needed for `area_id=5`, `floor_id=6` to enter `区域6` instead of
  falling back to the previous `floorId=6` row.

Minimal runtime candidate:
- Enter `人魚の断崖` floor list.
- Tap the second visible row. Expected request:
  `/connect/app/exploration/get_floor area_id=0 floor_id=6 check=1`.
- Expected response metadata:
  `floorKey=4:6`, `floorId=6`, `areaNo=5`, `movesDone=15`, `progress=93`,
  `hasNextFloor=true`, `nextFloorId=7`, `nextAreaNo=6`.
- Tap forward once. Expected request:
  `/connect/app/exploration/explore area_id=4 floor_id=5`.
- Expected response metadata:
  `movesDone=16`, `progress=100`.
- After the clear animation/buttons appear, tap the top-right `next_floor`
  button. Expected route candidate:
  `/connect/app/exploration/get_floor area_id=5 floor_id=6`.
- Expected next response metadata:
  `floorKey=5:7`, `floorId=7`, `areaNo=6`, `progress=0`, `hasNextFloor=false`.

Rejected / do not repeat:
- Do not put a nested `next_floor` under `/exploration/explore` as the next
  candidate. `work/exploration-next-floor-floorclear-card-20260627.md` records
  that this shape was served at progress 100 and did not reveal clear UI.
- Do not add standalone `complete=1`, boss, fairy, reward, or event fields for
  this pass without a new native consumer proof.
- Do not test the current top row `区域6` for ordinary next-area behavior.

Observable:
- `requests.jsonl` must prove the request sequence.
- Screenshots must include pre-clear, early clear, after-animation, and next-area
  milestones.
- If logcat reports exact missing resource paths for `floor_clear`, only those
  resources become the next resource frontier.

Open questions:
- The `next_floor` button command route is still only runtime-candidate evidence.
  If it emits a non-`get_floor` route, write a route/schema card before adding a
  handler.
- If progress reaches 100 but clear UI does not appear, the next frontier is the
  client-side floor-clear predicate/model state, not another broad XML sweep.
