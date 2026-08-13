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
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario deck-builder-entry-smoke -Tag deck-builder-entry-1
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario deck-builder-leader-mode-smoke -Tag deck-builder-leader-mode-1
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario deck-builder-edit-smoke -Tag deck-builder-edit-1
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario deck-builder-save-smoke -Tag deck-builder-save-1
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-draw-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-result-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-result-back-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-settlement-deck-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-paid-settlement-deck-smoke
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario gacha-paid-retry-smoke
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
- `deck-builder-entry-smoke` is the D1 card-deck entry acceptance. From the shared main-menu
  baseline it taps `(640,675)`, requires `/connect/app/roundtable/edit` with decrypted
  `move=1`, requires `command=round_table` and `nextScene=83200`, then waits three seconds,
  checks that the client is alive, requires the `deck-builder-entry.png` screenshot to differ
  from `deck-builder-mainmenu.png` by at least 20, and checks the accepted 1280x720 DeckScene
  color signature for its deck rail plus four right-side controls. The artifact records the next target
  as the leader control at `(1090,270)`, expected local behavior `change_mode_leader_select`,
  and no expected route. D1 stops there: it does not tap leader, save a deck, seed a custom
  player save, or sync additional resources.
- `deck-builder-leader-mode-smoke` is the bounded D2 acceptance. It reuses the complete D1
  DeckScene entry, captures `deck-builder-leader-before.png`, moves the request cursor, taps
  leader at `(1090,270)`, and fails if any `connect_app_probe` appears during the next three
  seconds. It then requires the client to remain alive and `deck-builder-leader-after.png`
  to differ by at least 8. A DeckScene-specific leader-mode signature also requires the four
  right-side controls to be dimmed while the left deck rail remains active, matching
  `change_mode_leader_select`; the artifact records no expected route. D2 stops without
  selecting a card, going back, deciding, or saving.
- `deck-builder-edit-smoke` is the bounded D4 local edit acceptance. It seeds only owned
  serials `1/22` and `2/9`, while the active deck and leader remain `[1]` and `1`. After the
  complete D1 entry it follows the statically closed taps `(127,360) -> (226,247) ->
  (1144,360)` to open card mode, choose the sole serial-2 candidate, and explicitly return.
  Every action requires a cursor-scoped three-second window without `connect_app_probe`, a
  live client, and a screenshot. Relational visual checks require the candidate to appear on
  mode entry and leave its ROI after selection, the mode-1 return tab to stay stable and normal
  DeckScene controls to remain hidden until explicit return, slot 0 to stay stable, and slot 1
  to change from `EMPTY`; player-save bytes and SHA-256 captured before deck entry must remain
  unchanged. D4 never taps `decide` or `/cardselect/savedeckcard`.
- `deck-builder-save-smoke` is the capture-only D5 edge. It reuses the complete D4 seed and
  local edit path, verifies a fresh normal DeckScene, then taps decide at `(1090,95)`. The
  scenario requires exactly one `/connect/app/cardselect/savedeckcard` probe with the
  case-sensitive key set `C,lr`, exact 12-slot value
  `C=1,2,empty,empty,empty,empty,empty,empty,empty,empty,empty,empty`, and `lr=1`.
  A cursor-scoped three-second window and a final count both reject duplicate save probes.
  The same-path response, client activity, follow-up routes, screenshot diff, and DeckScene
  classifier result are diagnostic only: the current empty-body response leaves DeckScene unchanged,
  while runtime acceptance of the statically closed current-model response path and successful persistence remain
  unproven. Save
  bytes and SHA-256 must remain equal to their pre-entry values; D5 stops without readback,
  retry, response-body changes, or disk persistence.
- `gacha-draw-smoke` logs into the main menu, enters the safe gacha select page, taps the
  visible one-draw option, waits for the first gacha draw route and response, then verifies
  that the client stays alive long enough to capture the draw scene screenshot.
- `gacha-result-smoke` continues the same path, taps the draw-card touch screen, and verifies
  the local transition to the result page. It is the regression for the accepted
  `librooneyj-gacha-cardget-inner-touch-nullguard.so` baseline and does not yet prove result-page
  back/retry commands or persisted ticket/currency spending.
- `gacha-result-back-smoke` continues to the result page, taps the visible result-page back
  button, and verifies either a route-backed return or a local page transition away from the result page.
  Accepted behavior is route-backed return to `/connect/app/gacha/select/getcontents`. The friendship-point
  result keeps retry hidden; paid retry has its own scenario.
- `gacha-paid-retry-smoke` seeds an artifact-local save with 600 MC, completes one paid draw,
  taps the original result-page retry button and confirmation dialog, then verifies the second
  `/gacha/buy` keeps `product_id=2`, spends the remaining 300 MC, persists serials `2` and `3`,
  and reaches the second visible result page with the client alive.
- `gacha-settlement-deck-smoke` seeds an artifact-local save with 400 friendship points, opens the
  original-style same-page gacha list, taps the visible friendship entry, runs the accepted one-draw/result/back path,
  verifies `/gacha/buy` persisted one drawn card
  (`serialId=2`, `masterCardId=9`) and spent 200 friendship points, returns to the main menu,
  then opens bottom deck/round table and verifies `/roundtable/edit` response metadata still
  reports the same owned card.
- `gacha-paid-settlement-deck-smoke` seeds an artifact-local save with 300 MC and no friendship
  points, opens the same gacha list, taps the paid MC entry, confirms the native purchase dialog,
  verifies `/gacha/buy` arrives with `product_id=2`, spends
  300 MC, persists the drawn card, returns to the main menu, then opens bottom deck/round table
  and verifies the deck response sees the same card.
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
