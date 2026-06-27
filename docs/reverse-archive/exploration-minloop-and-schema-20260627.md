# Exploration Minloop And Schema 20260627

get_floor/explore schema cards, server handlers, and accepted minimal exploration loop.

Source: `reverse-notes.md` before compaction, archived in full at `reverse-notes-full-before-compaction-20260627.md`.

<!-- original lines 1374-1496 -->

## Exploration get_floor/explore minimal schema and server handlers

- Frontier: floor-list row click now emits `/connect/app/exploration/get_floor`
  with decrypted params `area_id=0`, `floor_id=2`, `check=1`; the server had no
  handler, so the client stopped at a network error before `exploration_main`.
- Hypothesis: implementing only parser-confirmed `get_floor` and no-branch
  `explore` responses is enough to move from floor-list selection into the
  walking scene and expose the next route/UI observable.
- Static evidence:
  - `_ExplorationModel::move(...)` calls `Model::connect` with route id `23`
    at `0x001d79fe`, matching runtime `/exploration/get_floor`.
  - `_ExplorationModel` compares body child `get_floor` at `0x001d6b6c`, then
    calls `_GetFloorTagParser::parse` at `0x001d6caa` and
    `_ExplorationModel::init(GetFloorTagData)` at `0x001d6cda`.
  - `_GetFloorTagParser::parse` confirms direct fields `next_floor`,
    `special_item`, `area_id`, `bg`, `bgm`, `area_name`, `next_exp`, and
    `floor_info`.
  - `_ExplorationModel::update` compares body child `explore` at `0x001d6de6`
    and `0x001d702e`, then calls `_ExploreTagParser::parse` and
    `_ExplorationModel::init(ExploreTagData)`.
  - `_ExploreTagParser::parse` confirms snake_case fields including `progress`,
    `event_type`, `gold`, `get_exp`, `next_exp`, `next_floor`,
    `friendship_point`, `recover`, `encounter`, `fairy_pose`, and `fairy_face`.
- Changed one variable:
  - Added `EXPLORATION_GET_FLOOR_XML` and `/connect/app/exploration/get_floor`
    handler in `server/bootstrap-server.js`.
  - Added `EXPLORATION_EXPLORE_XML` and `/connect/app/exploration/explore`
    no-branch candidate handler.
  - Added encrypted route self-checks in `server/test-bootstrap-server.js`.
  - Added schema cards:
    `work/exploration-get-floor-schema-card-20260627.md` and
    `work/exploration-explore-schema-card-20260627.md`.
- Check:
  - `node .\server\test-bootstrap-server.js` passed.
  - The self-check decrypts `/exploration/get_floor` using the observed
    encrypted params and confirms the response equals `EXPLORATION_GET_FLOOR_XML`.
  - At this static/server stage, the `/exploration/explore` test only proved
    the handler XML; the next runtime section captures and fixes the real
    forward request body.
- Conclusion:
  - The old `<exploration_explore>` candidate parent is rejected. The native
    body child is `<explore>`.
  - The `/exploration/get_floor` response is a distinct `<get_floor>` payload,
    not a reused `<exploration_floor>` list response.
- Next frontier:
  - Runtime with sticky floor-list patch installed: tap floor row, confirm no
    network modal, then capture whether `exploration_main` becomes visible or
    which route/logcat/activity observable appears next. This is closed by the
    following minimal-loop runtime section.

## Exploration minimal loop accepted

- Frontier: validate the smallest playable exploration loop after adding
  `/connect/app/exploration/get_floor` and `/connect/app/exploration/explore`.
- Hypothesis: with the accepted sticky floor-list native patch as baseline, the
  parser-confirmed `get_floor` and no-branch `explore` payloads are enough to
  enter the walking scene, advance once, and return through existing mainmenu.
- Changed one variable:
  - Kept installed native at `sticky-floorlist-mode`, SHA-256
    `2A12D64209E287F4470F66915D6BFC9DD56B5DADAEAE2156085480073784A0F6`.
  - Server protocol change was limited to the new `get_floor` and `explore`
    handlers already covered by schema cards.
  - After runtime captured the forward request, tightened
    `server/test-bootstrap-server.js` to use the observed encrypted
    `/exploration/explore` body.
- Server check:
  - `node .\server\test-bootstrap-server.js` passed after fixing the real
    `explore` request body in the self-check.
- ARM19 check:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health`
    passed on ARM19 (`armeabi-v7a`, Android `4.4.2`, boot completed), with the
    known primary TCP serial offline warning and healthy `emulator-5582` legacy
    serial.
  - `patch-lib` had verified installed/source sticky native hash equality:
    `2A12D64209E287F4470F66915D6BFC9DD56B5DADAEAE2156085480073784A0F6`.
  - Helper server was running on both `50005` and `10001`.
- Runtime commands and artifacts:
  - Login/main menu: `work/kssma-runtime-exploration-minloop-login-*`.
  - Exploration entry: `work/kssma-runtime-exploration-minloop-after-explore-*`.
  - Area to floor-list: `work/kssma-runtime-exploration-minloop-after-area-*`.
  - Floor row to walking scene: `work/kssma-runtime-exploration-minloop-after-getfloor-*`.
  - One forward action: `work/kssma-runtime-exploration-minloop-after-forward-*`.
  - Return to main menu: `work/kssma-runtime-exploration-minloop-after-return-*`.
- Observed:
  - Tap `1090,250` from main menu emitted
    `/connect/app/exploration/area`.
  - Tap `730,280` on `Local Area` emitted
    `/connect/app/exploration/floor` with decrypted `area_id=0`; screenshot
    `work/kssma-runtime-exploration-minloop-after-area.png` shows the floor
    list row `区域 1`.
  - Tap `720,270` on the floor row emitted
    `/connect/app/exploration/get_floor` with decrypted `area_id=0`,
    `floor_id=2`, `check=1`; screenshot
    `work/kssma-runtime-exploration-minloop-after-getfloor.png` shows
    `exploration_main` for `Local Area 地区2` at `1%` with the `前进` button.
  - Tap `1090,105` on `前进` emitted
    `/connect/app/exploration/explore` with decrypted `area_id=0`,
    `floor_id=2`, `auto_build=1`; screenshot
    `work/kssma-runtime-exploration-minloop-after-forward.png` shows progress
    advanced to `2%`.
  - Tap `1090,430` on `回到据点` emitted `/connect/app/mainmenu`, reusing the
    existing `minimal mainmenu` handler; screenshot
    `work/kssma-runtime-exploration-minloop-after-return.png` shows the visible
    main menu.
  - Activity stayed `com.test.RooneyJActivity`; logcat had no `Fatal signal`,
    `SIGILL`, `SIGSEGV`, `SIGABRT`, `JResourceLoader`, `getSDPackFile`, or
    texture-miss blocker. The repeated APN permission warning is known
    CheckNetWork noise.
- Conclusion:
  - The requested minimal exploration loop is now proven end to end:
    main menu -> exploration -> area -> floor list -> floor -> one forward
    explore -> return main menu.
  - `/connect/app/exploration/get_floor` uses `<get_floor>`, and
    `/connect/app/exploration/explore` uses `<explore>`; the old
    `<exploration_explore>` shape remains rejected.
  - No battle, fairy, boss, reward, or floor-clear route was reached in this
    no-branch loop.
- Next frontier:
  - If continuing exploration depth, recover the next state after repeated
    `explore` or a deliberate event branch. Do not widen the current no-branch
    XML with guessed reward/battle/fairy fields before a new route, screenshot,
    or native parser observable demands it.
