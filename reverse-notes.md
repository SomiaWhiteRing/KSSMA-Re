# KSSMA-Re Current Reverse Notes

This file is the startup index, not the full experiment log. The full pre-compaction
notes are archived at
`docs/reverse-archive/reverse-notes-full-before-compaction-20260627.md`.

## Current Baseline

- Source APK: `base/com.square_enix.million_cn-1.0.0.100.0712.M330.apk`.
- Unique installable client baseline: `work/client-baseline/KSSMA-Re-client-baseline.apk`.
- Client baseline manifest: `work/client-baseline/client-baseline.json`.
- Resource dump: `base/com.square_enix.million_cn-140330.zip`.
- Decompiled output and working assets: `work/million_cn/`.
- Runtime target: Android `4.4.2` / API 19 / `armeabi-v7a` classic ARM emulator.
- Runtime control entry: `work/kssma-runtime.ps1`; `work/android44-arm19.ps1` is only a legacy shim.
- Primary serial is `emulator-5556`; `127.0.0.1:5557` is only a compatibility/diagnostic alias.
  Old `5582/5583` ports are not a current baseline because this Windows environment reserves
  TCP `5562..5661`, and the classic emulator can fail to bind inside that range.
- Known keys:
  - `k1`: `A1dPUcrvur2CRQyl`
  - `k2`: `rBwj1MIAivVN222b`
- Manual/debug server runs on both `50005` and `10001` through:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 start`.
- Gameplay acceptance should normally use:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-smoke`.
  The flow owns its local bootstrap server, runtime gate, login, route waits, screenshots, and summary artifacts.
- Human play entry is split for non-developers:
  `start-runtime.cmd` starts/prepares ARM19, `start-server.cmd` starts the local server, and `stop.cmd` stops it.
  `play.cmd` is only a compatibility instruction page.
- Server self-check:
  `node .\server\test-bootstrap-server.js`.

## Flow Discipline

- Startup can still be advanced by next route.
- Gameplay must be advanced by flow edge:
  `user action -> request/response -> client state switch -> visible UI -> next click target/route`.
- HTTP 200 is not a gameplay success criterion.
- If an already-accepted correct path can produce the target UI/state/route,
  write a path card and statically recover that complete path before product patching.
- Repeating the previous-layer route after a supposed layer switch is strong evidence that foreground/click ownership did not change.
- After two failed local UI/state/behavior product patches, the next round must use known-good path diff/reuse or a read-only classifier.

## Accepted Startup And Main Menu

- Original Java flow can reach:
  `world_list.php -> check_inspection -> post_devicetoken -> connect/app/login`.
- Full save preload/mount fixed the old `save/download/rest/treasurebox` crash.
- `/connect/web/` notice handling is not a failure by itself; only interact with it when screenshot/UI proves an active notice is blocking play.
- Main menu visual restoration is accepted:
  - background uses `<mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile>`;
  - initial main-menu pixie face/pose and information box are accepted for all three faction slots:
    `sword -> 117/1/4`, `technique -> 120/1/8`, `magic -> 111/2/4`;
  - BGM/voice runtime baseline is accepted;
  - user footage confirmed tapped character subtitles originally had no backing dialogue box.
- Mainmenu faction mapping evidence:
  `work/mainmenu-faction-fairy-card-20260630.md`; `server/test-bootstrap-server.js`
  covers all three login and mainmenu-update XML paths, and runtime artifact
  `work/kssma-flow-mainmenu-faction-smoke-20260630-193142` validates the
  non-default `technique` path with `countryId=2`, `fairyCharacterId=120`,
  `fairyPose=1`, `fairyFace=8`, and `screenshots/mainmenu-technique.png`.
- Mainmenu expression preview artifact:
  `work/mainmenu-fairy-expression-preview-20260630/all-labeled-sheet.png`.
  The adopted closed-mouth defaults are user-selected from that sheet:
  `111_2_4`, `117_1_4`, and `120_1_8`.
- Do not reopen main menu black background, face black, BGM, voice, or tapped dialogue-box work without a new resource-miss log, native texture crash, or regression screenshot.

Archive: `docs/reverse-archive/startup-mainmenu-20260624-20260625.md`.

## Accepted Runtime Control

- Use ARM19 only unless the user explicitly asks to investigate another runtime.
- Gameplay acceptance normally runs through `flow -Scenario <name>`, which already performs `fast-health`,
  `repair-adb` on failure, `ensure-baseline`, and `ensure-client-baseline`.
- For manual/debug device work outside flow, run `fast-health` first and run `repair-adb` only after it explicitly fails.
- `repair-adb` first tries short reconnect repair. It may automatically warm-restart
  only `detached-arm19`: `kssma_arm19` still has classic emulator processes, but
  both `emulator-5556` and `127.0.0.1:5557` cannot shell.
- Manual `restart-runtime -Force -Reason "..."` remains explicit-only outside that
  detached ARM19 repair path.
- `install-apk` only accepts the unique client baseline APK. Old APKs are archived and must not be installed.
- Native-only changes should use `patch-lib -ApkPath <explicit .so>` and must verify installed/source SHA-256 equality.
- Frida is not a default probe because it can destabilize ARM19 ADB.

Archive: `docs/reverse-archive/runtime-control-arm19-20260625-20260627.md`.

## Accepted Exploration State

Exploration is initially complete as of 2026-06-30. It is good enough for the current project baseline:
enter from main menu, show the save-gated area list, show the floor list, enter a floor, walk, spend AP,
persist progress, unlock the next floor, show AP shortage, handle ordinary level-up, and play the normal
floor-clear / next-area transition. Deeper exploration work is intentionally frozen until player data is
more complete.

The accepted hierarchy is:

```text
main menu -> area list -> floor list -> floor/exploration main
```

Current accepted flow evidence:

- `flow -Scenario exploration-smoke` is the canonical smoke path for this hierarchy.
- Main menu exploration button emits `/connect/app/exploration/area`. A fresh player save returns only the first
  unlocked area, `人魚の断崖`; later areas remain in `server/data/game/exploration.json` but are gated by player save.
- Selecting area 0 emits `/connect/app/exploration/floor` with decrypted `area_id=0`; selecting its current row emits
  `/connect/app/exploration/get_floor` with `area_id=0`, `floor_id=2`, `check=1`, response `regionId=0`, `areaNo=1`,
  `bg=adv_bg14`, and enters `exploration_main`.
- Returning from the stage re-requests `/connect/app/exploration/area`.
- Fresh progression now opens floors in order. `/exploration/floor` lists only unlocked floors for the requested
  area; `/exploration/explore` spends AP, persists floor progress, and unlocks the next floor when progress reaches
  100%. Locked floor/stage requests return an encrypted locked response and do not mutate the save.
- AP shortage uses the bundled `ap_fail_in` scene id `81100` and does not mutate AP, progress, EXP, or Gold.
- Ordinary exploration level-up routes through `/town/lvup_status` and `/town/pointsetting`, with AP/BC allocation
  persisted in the player save.
- Historical six-area artifacts remain useful for background/value checks, but they predate save-gated unlocking and
  are no longer the default new-player smoke path.

Accepted native patches/builders:

- Sticky floor-list mode accepted the floor-list switch after floor data exists.
  Archive details: `docs/reverse-archive/exploration-floorlist-deadends-20260625-20260627.md`.
- Area/floor descent and floor-list return re-request accepted:
  - builder: `work/build-exploration-area-return-rerequest.py`
  - path card: `work/exploration-area-entry-rerequest-card-20260627.md`
  - output: `work/librooneyj-exploration-area-return-rerequest.so`
  - SHA-256: `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`
  - key artifacts:
    `work/kssma-runtime-exploration-area-return-rerequest-area-*`,
    `work/kssma-runtime-exploration-area-return-rerequest-floor-*`,
    `work/kssma-runtime-exploration-area-return-rerequest-return-*`,
    `work/kssma-runtime-exploration-area-return-rerequest-refloor-*`.

Accepted server handlers:

- `/connect/app/exploration/area`
- `/connect/app/exploration/floor`
- `/connect/app/exploration/get_floor`
- `/connect/app/exploration/explore`
- `/connect/app/mainmenu`

Schema/value cards:

- `work/exploration-get-floor-schema-card-20260627.md`
- `work/exploration-explore-schema-card-20260627.md`
- `work/exploration-area-entry-rerequest-card-20260627.md`
- `work/exploration-bg-value-card-20260627.md`

Archives:

- `docs/reverse-archive/exploration-floorlist-deadends-20260625-20260627.md`
- `docs/reverse-archive/exploration-minloop-and-schema-20260627.md`
- `docs/reverse-archive/exploration-return-deadends-and-rerequest-20260627.md`

## Do Not Repeat

- Do not continue server `floor_info` field/value sweeps for floor-list visibility.
- Do not continue XML-only floor-list fixes without new native parser/consumer evidence.
- Do not use `0x00342108` as an unconditional floor-only anchor.
- Do not use successful-return-only `getSelected` probes as proof that a branch was not entered.
- Do not continue `+0x84` single-point visual fixes for the accepted floor-list blocker.
- Do not continue local `area_list_sp`, remake, draw-flag, state-only, or behavior-only return fixes for the accepted floor-list return blocker.
- Do not use `0x001f4200` as a layout behavior event function or `0x000c6b81` as `area_list_sp`.
- Do not merge the exploration background problem into hierarchy or route fixes.
- Do not treat APN permission warnings from `CheckNetWork` as a gameplay blocker.
- Do not treat `/connect/web/` alone as failure.

## Current Frontiers

- Flow-first runtime acceptance is now the default project path. Use:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-smoke`.
- Active product frontier is back to the main menu / home hub. Do not reopen the accepted main-menu black-screen,
  face, background, BGM, voice, or tapped subtitle visual work without new regression evidence. The next main-menu
  work should improve user-data-backed hub behavior: shared player save fields, visible AP/BC/card/friend/currency
  consistency, main-menu entry routes, information/notification data, and reusable flow scenarios for those menu
  edges.
- Exploration is marked initially complete for now. Keep its smoke/walk/floor-clear/AP-shortage/level-up flows as
  regression tests, but pause cross-region completion, guardian/battle, event, fairy, and reward branches until the
  player data model is stronger.
- Current accepted exploration smoke artifact:
  `work/kssma-flow-exploration-smoke-dev21-area1-two-step-smoke`.
- Flow-first reset regression artifact:
  `work/kssma-flow-exploration-smoke-flow-first-reset-smoke`; it passed with
  `/exploration/area -> /exploration/floor area_id=0 -> /exploration/get_floor area_id=0 floor_id=7 ->
  /exploration/area -> /exploration/floor area_id=1 -> /exploration/get_floor area_id=1 floor_id=16`.
- Human entry frontier: non-technical play is split into `start-runtime.cmd`, `start-server.cmd`, and `stop.cmd`.
  `play.cmd` is only a compatibility instruction page.
- Human entry smoke artifact: `work/kssma-flow-play-human-entry-smoke` passed on 2026-06-28. It recovered a
  detached ARM19 by warm restart, restored the accepted exploration native baseline, logged in, and screenshot
  `screenshots/ready-mainmenu.png` shows the accepted main menu. Server was stopped after validation.
- Human entry cmd parsing fix: `play.cmd` and `stop.cmd` are ASCII one-line wrappers because Windows `cmd.exe`
  misparsed the previous UTF-8/LF Chinese batch text. Entry self-checks passed:
  `cmd /c play.cmd self-test` and `cmd /c stop.cmd self-test`. Flow self-check/list and
  `node .\server\test-bootstrap-server.js` also passed.
- Human entry visibility fix: `play.cmd`/`stop.cmd` now keep a plain `pause` at the end of the same cmd window
  instead of relying on a child window. This should make double-click failures visible instead of disappearing.
  Rechecked `cmd /c play.cmd self-test`, `cmd /c stop.cmd self-test`, flow self-check, and server self-check.
- Human entry split: one-shot `play` failed in
  `work/kssma-flow-play-human-entry-20260628-104414` because ADB saw only non-ARM19 devices
  (`wrong-runtime-only`) and no `kssma_arm19` process. Added `start-runtime.cmd`, `start-server.cmd`, and
  `start-runtime` runtime command so ARM19 startup is separate from server startup and gameplay flow.
- Manual play connectivity fix: server was healthy on `50005/10001`, but the newly started ARM19 had stale hosts
  (`/system/etc/hosts` only contained localhost), so the client could not reach local bootstrap despite server health.
  `ensure-baseline` repaired hosts/mount/display/audio/package. `start-runtime` now runs baseline after ARM19 startup
  or when ARM19 is already running; verified output includes `baseline.cache=fresh` and `hostsOk=true`.
- Manual play exploration-baseline fix: area list regressed to "tap area does not enter floor list" because the installed
  `librooneyj.so` hash was `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`, not the accepted
  exploration baseline `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`. Ran
  `ensure-exploration-baseline`; it patched only `librooneyj.so` and post-verify matched. `start-runtime` now runs
  `ensure-exploration-baseline` after `ensure-baseline`, so manual play gets the same hierarchy baseline as flow.
- Exploration rebaseline smoke artifact: `work/kssma-flow-exploration-smoke-area-floor-rebaseline` passed. Route
  sequence proved `/exploration/area -> /exploration/floor area_id=0 -> /exploration/get_floor area_id=0 floor_id=7`,
  return to `/exploration/area`, then `/exploration/floor area_id=1 -> /exploration/get_floor area_id=1 floor_id=16`.
- Client baseline uniqueization: generated `work/client-baseline/KSSMA-Re-client-baseline.apk` from clean base APK plus
  accepted `work/librooneyj-exploration-area-return-rerequest.so`; manifest records the current signed baseline APK
  SHA-256 and fixed lib SHA-256 `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`.
  The APK hash can change when rebuilt because `jarsigner` rewrites signature metadata; the embedded lib hash is the
  stable client-behavior guard. `ensure-client-baseline` passed
  with installed/source lib match, and `install-check -ApkPath .\work\million-cn-animationguard-signed.apk` correctly
  refused the old APK because its embedded lib was stock `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
  Old `work/*.apk` and obsolete probe `.so` files were deleted; their removal manifest is
  `docs/reverse-archive/client-artifacts-before-baseline-20260628/removed-binaries.tsv`.
- Client baseline uniqueization runtime proof: `start-runtime` now reports `clientBaseline.status=already-matched`.
  `install-check` without `-ApkPath` verifies the unique baseline, and `flow -Scenario exploration-smoke -Tag client-baseline-uniqueization`
  passed with artifact `work/kssma-flow-exploration-smoke-client-baseline-uniqueization`.
- Former exploration frontier beyond normal walking, floor-clear, and next-floor continuation is now frozen:
  return behavior from exploration main, cross-region completion, guardian/battle, event, fairy, and reward branches
  are not active until main-menu/player-data work catches up.
- The active tooling frontier is adding new `flow` scenarios for new systems instead of copying login/server/ADB setup into separate scripts.
- Detailed pre-flow-first exploration depth, media, ADB, native-baseline, and smoke-run notes were moved to:
  `docs/reverse-archive/exploration-frontiers-before-flow-first-20260628.md`.
- Data-layer split: `server/bootstrap-server.js` now reads temporary JSON data from three separate roots:
  `server/data/game/` for game content, `server/data/player/` for local player defaults, and
  `server/data/server/` for local server compatibility/config. Main menu welcome text/background,
  exploration regions/floors/BGM/backgrounds, default exploration progress, world list, and masterdata route
  mapping were moved out of hardcoded server constants. `node .\server\test-bootstrap-server.js` passed.
- Exploration walk smoke accepted: `flow -Scenario exploration-walk-smoke` passed with artifact
  `work/kssma-flow-exploration-walk-smoke-20260628-184805`. This supersedes
  `work/kssma-flow-exploration-walk-smoke-walk-smoke-dev3`, where the floor list highlighted `区域 6` but
  the entered stage title showed `地区7`. Current fix keeps floor-list XML on the client's internal
  `floorId=7`, but renders `get_floor` current/next `floor_info.id` as visible `areaNo=6`; screenshot
  `screenshots/area0-main.png` shows `人魚の断崖 地区6`. Route sequence now proves
  `area -> floor area_id=0 -> get_floor area_id=0 floor_id=7 -> explore area_id=5 floor_id=6` twice,
  while server maps stage actions back to `floorKey=5:7`. Server response evidence: first walk
  `progress=5`, second walk `progress=10`, both with `gold=55`, `getExp=9`; the returned floor-list
  response reported `maxProgress=10`, `maxProgressFloorId=7`, `maxProgressAreaNo=6`. Floor completion and
  next-floor behavior are superseded by the accepted floor-clear evidence below.
- Random exploration area review: static random sample picked `錯乱の平原 / 区域7`
  (`routeAreaId=21`, `floorId=23`, `areaNo=7`, `bg=adv_bg12`) and `createExplorationGetFloorXml(...)`
  rendered the current visible `floor_info.id` as `7`. Runtime non-default review passed with artifact
  `work/kssma-flow-exploration-smoke-random-review-area1`: route sequence reached `燐光の湖`,
  `/exploration/get_floor area_id=1 floor_id=16`, response logged `floorId=16`, `areaNo=9`,
  `bg=adv_bg11`, and `screenshots/area1-main.png` shows `燐光の湖 地区9`. No client/native change.
- Exploration floor-clear / next-area accepted: added `flow -Scenario exploration-floor-clear-smoke`,
  with flow-only seed `KSSMA_EXPLORATION_MOVES_SEED={"4:6":15}` so `人魚の断崖 区域5`
  starts at `15/16` moves. Accepted artifact:
  `work/kssma-flow-exploration-floor-clear-smoke-floor-clear-smoke-3`. Route sequence proved
  `/exploration/floor area_id=0 -> /exploration/get_floor area_id=0 floor_id=6` with response
  `floorKey=4:6`, `areaNo=5`, `progress=93`, `hasNextFloor=true`, then
  `/exploration/explore area_id=4 floor_id=5` returned `progress=100`, then tapping the clear-state
  top button emitted `/exploration/get_floor area_id=5 floor_id=6` and entered `floorKey=5:7`,
  `areaNo=6`, `progress=0`. Screenshots `area0-area5-clear-early.png` and
  `area0-area5-clear-after-animation.png` show the original clear-state UI with
  `进入下一个区域`; `area0-area6-main-after-next-floor.png` shows `人魚の断崖 地区6`.
  No `Fatal signal`, `SIGSEGV`, `JResourceLoader`, `loadTexture`, or `getSDPackFile` evidence was found.
  Flow calibration note: selecting area 5 in the floor list requires first tapping the second visible row,
  then after the list recenters, tapping the top highlighted row to enter.
- Exploration floor-clear / next-area revalidated on 2026-06-30 with no product-code change. Checks:
  `node .\server\test-bootstrap-server.js`, `flow -Scenario self-check -Tag floorclear-current-selfcheck`, and
  `flow -Scenario exploration-floor-clear-smoke -Tag floorclear-current-runtime` all passed. Artifact:
  `work/kssma-flow-exploration-floor-clear-smoke-floorclear-current-runtime`. Runtime route sequence again proved
  `/exploration/get_floor area_id=0 floor_id=6 -> /exploration/explore area_id=4 floor_id=5 progress=100 ->
  /exploration/get_floor area_id=5 floor_id=6`; screenshots show `地区5` at `100%` with `进入下一个区域`, then
  `地区6` at `0%`. Logcat had no fatal/resource-miss evidence; only the known APN permission noise appeared.
- Exploration forward visual update fix: `/connect/app/exploration/explore` no longer includes
  `<next_scene>6200</next_scene>`; only `/exploration/get_floor` keeps that stage-entry header. Hypothesis was
  that forward responses were being treated like re-entering `exploration_main`, causing the progress bar and
  right-side buttons to replay. Server self-check now asserts `EXPLORATION_EXPLORE_XML` has no `next_scene`.
  Runtime proof:
  `work/kssma-flow-exploration-forward-visual-smoke-no-next-scene-visual` seeded `floorKey=5:7` to 10/20 moves;
  screenshot `before-forward-progress-50.png` showed 50%, `/exploration/explore` returned `movesDone=11`,
  `progress=55`, screenshot `after-forward-0200ms.png` already showed 55% with reward overlay rather than a 0%
  reload, and `after-forward-0800ms.png` / `after-forward-1800ms.png` showed stable 55% controls. Regression
  artifacts `work/kssma-flow-exploration-walk-smoke-no-next-scene-explore` and
  `work/kssma-flow-exploration-floor-clear-smoke-no-next-scene-floorclear` both passed, proving normal walking
  and floor-clear/next-area still work.
- Exploration progress is player data: `/connect/app/exploration/explore` now persists
  `exploration.movesByFloor` to a player save JSON. `server/data/player/default-save.json` remains only the
  initial template; manual play writes ignored `server/data/player/local-save.json`; flow runs set
  `KSSMA_PLAYER_SAVE_PATH` to the artifact-local `player-save.json` so acceptance tests stay reproducible and do not
  mutate the human play save. Server self-check asserts that two explore posts write `0:2 = 1` then `0:2 = 2`.
  Runtime proof: `work/kssma-flow-exploration-walk-smoke-player-save-walk-5` passed. The real client entered
  `floorKey=5:7`; first `/exploration/explore` saved `movesDone=1`, `progress=5`, second saved `movesDone=2`,
  `progress=10`; artifact `player-save.json` contains `"5:7": 2`, and the returned floor-list response reported
  `maxProgress=10`. Server logs now emit only ASCII-safe save path labels such as `player-save.json`, preventing
  flow request parsing from being broken by non-ASCII Windows user paths.
- Player save schema expanded: `server/data/player/default-save.json` is now schema version 2 with top-level
  sections for `account`, `profile`, `resources` (AP/BC/SUPER), `progression`, `currencies`, `items`, `cards`,
  `friends`, `gacha`, `exploration`, `battle`, `stories`, `tutorial`, `notifications`, `server`, and `stats`.
  Evidence is summarized in `docs/player-save-schema.md`: local `local_battle_player.xml` proves current player
  fields such as AP/BC/max_card/gold/friendship/gacha ticket; the local zh-Fandom knowledge extraction proves
  AP 180s regen, BC 60s regen, card cap 350, friend cap 30, friendship gacha cost 200, level cap 350, and
  AP/BC ability point rules; exploration data comes from the accepted FC2/zh-Fandom cards. Save loading now deep-merges
  old partial saves into the new template. `/exploration/explore` mutates player data beyond progress: it spends AP,
  adds EXP/Gold, updates per-floor and per-region progress, marks floor unlock/clear metadata, and increments
  `stats.explorationMoves`. `node .\server\test-bootstrap-server.js` and
  `flow -Scenario self-check -Tag player-save-schema-selfcheck` passed.
- Exploration unlock/AP correction: current server self-check passed after making player save the source of truth for
  exploration availability. Fresh `/exploration/area` returns one area (`人魚の断崖`), fresh `/exploration/floor`
  returns only the first unlocked floor, a locked next-floor request returns `createExplorationLockedXml()`, a seeded
  9/10 first floor reaches `progress=100` and unlocks floor id `3`, and AP=0 returns `createExplorationApFailXml()`
  with `next_scene=81100` without mutating the save. Flow seeds are now minimum progress seeds, not per-request
  overwrites, so seeded tests cannot roll back higher saved progress. Runtime flow expectations were updated to the
  new-player path (`floor_id=2`, `areaNo=1`, first walk `progress=10`, AP `25 -> 24`).
- Runtime proof for the corrected new-player path:
  `work/kssma-flow-exploration-smoke-exploration-save-gating-smoke-2` passed with route sequence
  `/exploration/area areaCount=1 -> /exploration/floor area_id=0 unlockedFloorIds=[2] ->
  /exploration/get_floor area_id=0 floor_id=2 areaNo=1 -> /exploration/area -> /exploration/floor area_id=0`.
  `work/kssma-flow-exploration-walk-smoke-exploration-save-gating-walk` passed with two forward requests
  `/exploration/explore area_id=0 floor_id=1`; server logged `remainingAp=24`, `progress=10`, then
  `remainingAp=23`, `progress=20`, and artifact `player-save.json` persisted `resources.ap.current=23`,
  `profile.exp=6`, `currencies.gold=36`, `exploration.movesByFloor["0:2"]=2`, and floor progress `20`.
  A prior smoke attempt `work/kssma-flow-exploration-smoke-exploration-save-gating-smoke` failed only after the
  accepted return `/exploration/area` because ADB went offline during a nonessential screenshot; smoke was trimmed to
  avoid that screenshot before the passing run.
- AP visible refresh fix: manual testing showed "AP did not decrease" even though server logs and
  `server/data/player/local-save.json` proved five walks had spent AP from `25` to `20`. The missing piece was that
  `/exploration/explore` changed the save but did not return updated header `your_data`, so the stage resource bar
  stayed on the login sample values (`27/27`). `createExplorationExploreXml(...)` now accepts the updated player save
  and emits header `your_data` using the local save AP/BC/Gold/card/friendship fields. Server self-check passed and
  runtime artifact `work/kssma-flow-exploration-walk-smoke-ap-your-data-refresh` proved two walks returned
  `/exploration/explore` with `bytes=1440`, `remainingAp=24` then `23`, persisted `player-save.json`
  `resources.ap.current=23`, and screenshots `area0-after-forward-1.png` / `area0-after-forward-2.png` show the
  native resource bar updating to `24/25` and `23/25`. The flow process later had to be manually stopped during
  summary collection because ADB primary `127.0.0.1:5583` was offline; `repair-adb` recovered through healthy legacy
  `emulator-5582`, and this was not a gameplay/protocol failure.
- Player HUD synchronization fix: login/mainmenu/exploration list/stage routes now all derive header `your_data` from
  the same player save instead of mixing the old `local_battle_player.xml` sample with live exploration state.
  Server self-check seeds a deliberately different save (`level=10`, `AP=19/31`, `BC=12/33`, `Gold=4567`,
  `friendshipPoint=88`, `maxCardNum=222`, `nextExp=321`) and asserts those values appear in `/connect/app/login`,
  `/mainmenu/update`, `/mainmenu`, `/exploration/area`, `/exploration/floor`, and `/exploration/get_floor`. It then
  asserts two explore steps return updated global totals in `your_data` (`AP 18/31`, `Gold 4585`, then `AP 17/31`,
  `Gold 4603`) while the explore body still reports per-step rewards (`gold=18`, `get_exp=3`). `profile.exp` is
  persisted in the save, but only `rank`, `percentage`, and body `next_exp` are currently wired to proven client XML
  fields; no unproven "current total EXP" response field was added.
- Exploration edge-case analysis card added:
  `work/exploration-edgecases-ap-levelup-card-20260628.md`. AP shortage is evidence-backed by
  `rule_scene.xml` scene `81100` (`ap_fail_in`) and `layout_ap_failin.xml`; current
  `createExplorationApFailXml()` is the right minimal branch and server self-check already proves AP=0 does not mutate
  progress/resources. Level-up is not implementation-ready: `_ExploreTagParser` confirms fields `lvup`, `is_limit`,
  `get_exp`, and `next_exp`, and `layout_exploration_main.xml` has `lvup_event -> exp_lvCheck` plus `lv_max_anm`, but
  the `lvup` value/nested shape and EXP threshold table are still open. Do not copy battle-only
  `before_level/after_level` from `local_battle_result.xml` into `/exploration/explore` without native proof.
- AP shortage runtime accepted: added `flow -Scenario exploration-ap-shortage-smoke`, which uses an artifact-local
  `player-save.json` with `resources.ap.current=0`. Runtime artifact
  `work/kssma-flow-exploration-ap-shortage-smoke-20260629-083016` passed. Route sequence reached
  `/exploration/area -> /exploration/floor area_id=0 -> /exploration/get_floor area_id=0 floor_id=2 ->
  /exploration/explore area_id=0 floor_id=1`; server logged `source="exploration ap fail"`, `nextScene=81100`,
  `currentAp=0`, and `saved=false`. Screenshot `screenshots/ap-shortage-page.png` shows the original AP shortage
  page, and artifact-local save remained unchanged: AP `0`, `movesByFloor` empty, EXP `0`, Gold `0`.
- AP shortage return and AP purchase-page return accepted: extended `flow -Scenario exploration-ap-shortage-smoke`
  and runtime artifact `work/kssma-flow-exploration-ap-shortage-smoke-20260629-232520` passed. The AP shortage back
  button returns to the stage, and tapping forward reaches `/exploration/explore` with the AP-fail response again.
  The AP recovery shop page is client-local in this path: tapping its purchase entry emitted no route before the
  screenshot `screenshots/ap-shortage-buy-page.png`. Its back button returns to a usable stage
  (`screenshots/ap-shortage-after-buy-return.png`). The first forward tap after returning from the shop may emit
  `/exploration/get_floor area_id=0 floor_id=1 check=1` to reload the current stage; after that, the next forward
  reaches `/exploration/explore area_id=0 floor_id=1` and the AP-fail response again. The artifact-local save stayed
  unchanged: AP `0`, `movesByFloor` empty, EXP `0`, Gold `0`.
- Player level EXP table is now clean adopted game data:
  `server/data/game/player-level-exp-table.json`. Runtime rows contain only playable baseline fields:
  `level`, `nextExp`, `statPointsOnLevelUp`, and optional `friendMax`. Evidence/source ranking is kept in
  `work/player-level-exp-table-card-20260629.md`, not in the runtime JSON.
- Ordinary exploration level-up accepted: `work/exploration-levelup-schema-card-20260629.md` closes scalar
  `<lvup>` and `<is_limit>` for non-max exploration upgrades when paired with trusted EXP rows. Server self-check
  covers Lv17 `1997/2000` + one AP=1 move, and runtime artifact
  `work/kssma-flow-exploration-levelup-smoke-20260630-002346` passed. Observed `/exploration/explore` response:
  `levelUp=true`, `isLimit=false`, `beforeLevel=17`, `level=18`, `profileExp=0`, `nextExp=2100`,
  `remainingAp=25`, `abilityPoints=3`, `abilityPointsGranted=3`.
  Artifact-local save ended with level 18, EXP 0, AP/BC 25/25, free AP/BC points 3, Gold 18, and
  `movesByFloor["0:2"]=1`.
- Level-up status and AP/BC allocation accepted: `work/town-lvup-status-schema-card-20260630.md`,
  `work/town-pointsetting-schema-card-20260630.md`, and `work/player-owner-card-bootstrap-card-20260630.md`.
  The first `/town/lvup_status` implementation exposed a missing-player-card crash
  (`_UserCard::isCardNull` from `_AnmAeLvUpStatus`), fixed by seeding default/local player saves with
  `leaderSerialId=1` and one owned card `serialId=1/masterCardId=22`, then emitting it through
  `your_data/owner_card_list`. Runtime artifact
  `work/kssma-flow-exploration-levelup-smoke-levelup-accepted-runtime` passed with route sequence
  `/exploration/explore levelUp=true -> /town/lvup_status -> /town/pointsetting ap=3 bc=0`. Artifact-local save
  ended at Lv18, EXP 0, AP `28/28`, BC `25/25`, `free_ap_bc_point=0`,
  `abilityPoints.apAllocated=3`, `bcAllocated=0`, Gold 18, and `movesByFloor["0:2"]=1`. No
  `_UserCard::isCardNull`/FATAL crash remained; APN permission log noise is unrelated emulator noise.
- Wide player EXP search completed: `work/player-level-exp-table-wide-search-card-20260630.md` and
  `work/recovered-data/player-level-exp-table-wide-20260630.json` separate original mobile evidence from
  cross-version candidates and rejected card-EXP tables. No complete original mobile player EXP table was found.
  Direct original mobile rows remain Lv17-Lv26 only. The broadest candidate is 3DS FC2 to Lv200 plus comment/pattern
  support: counts are `mobile_exact=10`, `fc2_3ds_exact=101`, `fc2_3ds_uncertain=2`,
  `pattern_inferred_from_fc2_comment_supported=1`, `pattern_inferred_from_fc2=78`, `missing=8`
  (`10-16, 200`). English Fandom `Experience Table` and zh-Fandom `強化合成` are card reinforcement EXP, not player
  level next-EXP; do not use them for player level-up.
- Lv10-Lv16 player EXP weak candidates added after targeted search failed to find direct rows:
  `work/player-level-exp-lv10-lv16-weak-candidates-card-20260630.md`. Values are `10=1300`, `11=1400`,
  `12=1500`, `13=1600`, `14=1700`, `15=1800`, `16=1900`, derived by extending the direct mobile Lv17-Lv25 +100
  sequence backward and supported only by the FC2/mobile overlap at Lv21-Lv26. A weak-filled table exists at
  `work/recovered-data/player-level-exp-table-wide-20260630-lv10-lv16-weak-filled.json`; it leaves only Lv200
  missing. Do not promote these rows to `mobile_exact` or `fc2_3ds_exact`.
- Lv10-Lv16 adopted EXP values are in the clean game table as ordinary baseline rows:
  `10=1300`, `11=1400`, `12=1500`, `13=1600`, `14=1700`, `15=1800`, `16=1900`.
  Their weak evidence caveat remains in `work/player-level-exp-lv10-lv16-weak-candidates-card-20260630.md`.
  Runtime code no longer carries source-rank fields. `node .\server\test-bootstrap-server.js` covers Lv16
  `1897/1900` + one AP=1 exploration move, producing Lv17, carry EXP 0, next EXP 2000, and AP/BC full recovery.
- Data-layer hygiene rule accepted: `server/data/**/*.json` is runtime data only, not documentation.
  Source strength, wiki URLs, rejected candidates, inference notes, and provenance belong in evidence cards,
  `work/recovered-data/`, or archive docs. Server self-check rejects documentation/provenance fields in formal data.
- Main-menu entry route skeletons added: `work/mainmenu-button-route-card-20260630.md` records button command,
  route, scene, and sample-body evidence. `server/bootstrap-server.js` now handles representative main/menu entry
  routes such as `/gacha/select/getcontents`, `/battle/area`, `/menu/menulist`, `/menu/playerinfo`, `/shop/shop`,
  `/menu/rewardbox`, `/item/havelist`, `/menu/fairyselect`, `/story/getoutline`, and compound/card/shop skeletons.
  Gacha entry deliberately uses a minimal safe `gacha_select/xml_contents` shell; `local_gachaselect.xml` is rejected
  for the entry smoke because runtime crashed on missing `gac_event_0`. Battle still uses bundled
  `local_battle_area.xml`; other route entries are explicit scene skeletons, not full subsystem implementations.
- `flow -Scenario mainmenu-buttons-route-smoke` accepted on ARM19 with artifact
  `work/kssma-flow-mainmenu-buttons-route-smoke-20260630-212726`. It logs in and proves:
  `/gacha/select/getcontents -> /mainmenu`, `/battle/area -> /mainmenu`,
  `/card/exchange mode=1 -> /mainmenu`, `/shop/shop -> /mainmenu`,
  `/menu/menulist -> /menu/playerinfo kind=6 user_id=0 -> /menu/menulist`.
  Screenshots cover each entered page. No fatal/SIGSEGV/resource-miss evidence appeared; the only matched logcat
  noise was a system Binder `RuntimeException`. Return-to-town remains `/connect/app/mainmenu`; player-info back
  returns to `/connect/app/menu/menulist` first.

## Archive Index

- Full old log:
  `docs/reverse-archive/reverse-notes-full-before-compaction-20260627.md`
- Startup/login/main menu:
  `docs/reverse-archive/startup-mainmenu-20260624-20260625.md`
- ARM19 runtime control:
  `docs/reverse-archive/runtime-control-arm19-20260625-20260627.md`
- Exploration floor-list dead ends and accepted sticky floor-list mode:
  `docs/reverse-archive/exploration-floorlist-deadends-20260625-20260627.md`
- Exploration `get_floor` / `explore` schema and minimal loop:
  `docs/reverse-archive/exploration-minloop-and-schema-20260627.md`
- Exploration hierarchy return dead ends and accepted re-request fix:
  `docs/reverse-archive/exploration-return-deadends-and-rerequest-20260627.md`
- Pre-flow-first exploration frontier details:
  `docs/reverse-archive/exploration-frontiers-before-flow-first-20260628.md`
- Process lessons:
  `docs/reverse-archive/process-lessons-20260627.md`

## Compaction Note

This file was compacted on 2026-06-27 from 2269 lines / 236228 bytes into a startup index.
Do not paste old archive material back into this file. Add new detailed experiments to a topic
archive when they are no longer current, and keep this file focused on accepted facts, active
frontiers, and hard "do not repeat" constraints.

