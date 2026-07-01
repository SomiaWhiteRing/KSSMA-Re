# Flow Scenario Guide

`work/kssma-runtime.ps1 flow` is the default gameplay acceptance harness. A flow
scenario should start from the main menu and reuse the shared runtime plumbing
instead of copying login, server, ADB, or artifact code.

## User Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario list
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario self-check
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario mainmenu-faction-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario mainmenu-buttons-route-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario mainmenu-bottom-buttons-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario menu-buttons-route-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario menu-buttons-tail-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario menu-item-parts-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-walk-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-forward-visual-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-floor-clear-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-ap-shortage-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-levelup-smoke
```

## Scenario Contract

- `list` and `self-check` must not touch ARM19 or the local server.
- Runtime gameplay scenarios own the local `bootstrap-server.js` process.
- Runtime gameplay scenarios call the shared runtime gate and login-to-main-menu stage before gameplay taps.
- Runtime gameplay scenarios use an artifact-local player save. The default exploration smoke
  starts like a new player: only `人魚の断崖` and its first unlocked floor are visible.
- `mainmenu-faction-smoke` writes an artifact-local `technique` player save before starting
  the server, logs into the main menu, verifies the server response advertises
  `countryId=2`, `fairyCharacterId=120`, `fairyPose=1`, and `fairyFace=8`, then saves a
  main-menu screenshot. The complete three-faction XML matrix is covered by
  `node .\server\test-bootstrap-server.js`.
- `mainmenu-buttons-route-smoke` logs into the main menu, taps representative visible
  entries (`gacha`, `battle`, `compound`, `shop`, `menu -> playerinfo`), waits for their
  first `/connect/app/*` route and response metadata, screenshots each entered page, then
  returns to main menu before the next entry. It is an entry/back smoke, not a full gacha,
  battle, shop, compound, or profile implementation test.
- `mainmenu-bottom-buttons-smoke` is the focused regression for bottom status entries:
  deck/round table (`roundtable/edit`, `move=1`) and friends (`menu/friendlist`). It uses screenshot-diff
  gates against the main menu, so it fails if either tap does not visibly enter its page or
  if back does not visibly return to the main menu.
- `menu-buttons-route-smoke` logs into the main menu, opens the Menu page, taps every
  visible Menu-page entry currently exposed by `layout_menu.xml`, waits for the first
  `/connect/app/*` route or `/connect/web/*` WebView URL, screenshots each entered page,
  and verifies the back path returns to Menu or main menu before continuing. It covers
  entry/back routing only; full story, ranking, fairy, item, collection, parts, option,
  help, and notice content remain later page-specific frontiers.
- `menu-buttons-tail-smoke` is the same validation shape but only for the lower/late Menu
  entries: option, item, card collection, parts list, fairy, update history, and help.
  Use it when a full Menu-page run already proved the earlier entries and ARM19/ADB
  stability is the active bottleneck.
- `menu-item-parts-smoke` is the focused regression for the currently fragile edges:
  item page open/back and parts-list open/back. It uses screenshot-diff gates against the
  Menu page, so it fails if the tap does not leave the Menu page or if back does not
  visibly return to it.
- Deep exploration scenarios may use `KSSMA_EXPLORATION_MOVES_SEED`, but the seed is only an
  initial minimum; it must not overwrite higher progress saved during the same run.
- `exploration-ap-shortage-smoke` writes an artifact-local AP=0 save before starting the server,
  enters the first stage, taps forward, then accepts either the real client-local AP shortage page
  or a server `/exploration/explore` AP shortage response. It also taps the AP shortage back
  button and proves the stage is usable again by tapping forward a second time. Then it enters
  the AP purchase page, tests its back path, and again proves the stage/AP-shortage loop is not
  stuck. Purchase-page return may first reload the current stage through `/exploration/get_floor`;
  the scenario accepts that only if the next forward tap reaches the AP shortage response again.
  In all passes it verifies AP, `movesByFloor`, EXP, and Gold are not mutated.
- `exploration-levelup-smoke` writes an artifact-local Lv17 save with `1997/2000` EXP before
  starting the server, enters the first stage, advances once, and verifies Lv18, carry EXP 0,
  next EXP 2100, full AP/BC recovery, +3 free AP/BC points, and one saved exploration move. The
  Lv17/Lv18 thresholds are direct mobile atwiki rows; do not switch this smoke to inferred rows.
- A gameplay step waits for a route, decrypted params, or response metadata; screenshots are milestone/failure evidence, not the pass condition.
- Failures must use a stable class such as `runtime-not-ready`, `server-start-failed`, `login-failed`, `route-timeout`, `route-param-mismatch`, `tap-no-effect`, `native-baseline-mismatch`, `client-crash`, or `resource-miss`.
- Every run writes `summary.json`, `summary.txt`, `events.jsonl`, `requests.jsonl`, `server.out.log`, `server.err.log`, `logcat.txt`, `activity.txt`, and key screenshots.

## Adding A Scenario

1. Add one scenario entry to `Get-FlowScenarioCatalog`.
2. Add one `Invoke-Flow<FeatureName>` function that starts after main menu.
3. Dispatch it from `Invoke-Flow` after `Start-FlowServer`, `Invoke-FlowRuntimeGate`, and `Invoke-FlowLaunchAndLogin`.
4. Use `Invoke-FlowTapThenWaitProbe`, `Wait-FlowServerEvent`, `Wait-FlowServerQuiet`, and `Capture-FlowScreenshot` instead of ad hoc ADB loops.
5. Add or update the smallest self-check that proves new log parsing or matching behavior.

Do not create a separate login driver for gacha, shop, exploration depth, or any
other gameplay system.
