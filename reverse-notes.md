# KSSMA-Re Current Reverse Notes

This file is the startup index, not the full experiment log. The full pre-compaction
notes are archived at
`docs/reverse-archive/reverse-notes-full-before-compaction-20260627.md`.

## Current Baseline

- Source APK: `base/com.square_enix.million_cn-1.0.0.100.0712.M330.apk`.
- Resource dump: `base/com.square_enix.million_cn-140330.zip`.
- Decompiled output and working assets: `work/million_cn/`.
- Runtime target: Android `4.4.2` / API 19 / `armeabi-v7a` classic ARM emulator.
- Runtime control entry: `work/kssma-runtime.ps1`; `work/android44-arm19.ps1` is only a legacy shim.
- Primary serial is `127.0.0.1:5583`; the healthy fallback alias commonly used by helper commands is `emulator-5582`.
- Known keys:
  - `k1`: `A1dPUcrvur2CRQyl`
  - `k2`: `rBwj1MIAivVN222b`
- Server normally runs on both `50005` and `10001` through:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 start`.
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
  - initial character face/pose and information box are accepted;
  - BGM/voice runtime baseline is accepted;
  - user footage confirmed tapped character subtitles originally had no backing dialogue box.
- Do not reopen main menu black background, face black, BGM, voice, or tapped dialogue-box work without a new resource-miss log, native texture crash, or regression screenshot.

Archive: `docs/reverse-archive/startup-mainmenu-20260624-20260625.md`.

## Accepted Runtime Control

- Use ARM19 only unless the user explicitly asks to investigate another runtime.
- Always run `fast-health` before real-device work.
- Only run `repair-adb` after `fast-health` explicitly fails.
- `repair-adb` first tries short reconnect repair. It may automatically warm-restart
  only `detached-arm19`: `kssma_arm19` still has classic emulator processes, but
  both `127.0.0.1:5583` and `emulator-5582` cannot shell.
- Manual `restart-runtime -Force -Reason "..."` remains explicit-only outside that
  detached ARM19 repair path.
- Native-only changes should use `patch-lib -ApkPath <apk-or-so>` and must verify installed/source SHA-256 equality.
- Frida is not a default probe because it can destabilize ARM19 ADB.

Archive: `docs/reverse-archive/runtime-control-arm19-20260625-20260627.md`.

## Accepted Exploration State

The accepted hierarchy is:

```text
main menu -> area list -> floor list -> floor/exploration main
```

Current accepted flow evidence:

- Main menu exploration button emits `/connect/app/exploration/area` and shows non-empty `Local Area`.
- Tapping `Local Area` emits `/connect/app/exploration/floor` with decrypted `area_id=0` and shows floor row `区域 1`.
- Tapping floor row emits `/connect/app/exploration/get_floor` with decrypted `area_id=0`, `floor_id=2`, `check=1`, and enters `exploration_main`.
- Tapping forward emits `/connect/app/exploration/explore` with decrypted `area_id=0`, `floor_id=2`, `auto_build=1`, and progress advances.
- Returning to main menu uses `/connect/app/mainmenu` and shows the accepted main menu.
- Floor-list return now re-requests `/connect/app/exploration/area`; the accepted route order is:
  `/exploration/area -> /exploration/floor -> /exploration/area -> /exploration/floor`.

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

- Exploration repeated forward accepted:
  - Frontier: `exploration_main` repeated no-branch forward after the first accepted `/connect/app/exploration/explore`.
  - Hypothesis: the visible stall was server-side, because the client kept issuing `/exploration/explore` but the server always returned `<progress>2</progress>`.
  - Change: `/connect/app/exploration/get_floor` seeds per-process floor progress to 1, and `/connect/app/exploration/explore` increments per `area_id:floor_id` up to 100. No native/resource/background/event/battle changes.
  - Server check: `node .\server\test-bootstrap-server.js` passed; encrypted repeated explore responses decode to 2% then 3%.
  - ARM19 check: installed `work/librooneyj-exploration-area-return-rerequest.so` SHA-256 matched source `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`.
  - Runtime artifacts: `work/kssma-runtime-exploration-secondloop-*`.
  - Observed: `/area -> /floor -> /get_floor -> /explore -> /explore`; second post-change forward returned progress 3 and screenshot `work/kssma-runtime-exploration-secondloop-after-forward3.png` showed `3%`. `RooneyJActivity` stayed resumed; no fatal/native crash was observed.
  - Conclusion: repeated no-branch exploration is now a server-state frontier, not a native hierarchy blocker. Next depth work should intentionally choose event/floor-clear/battle/fairy/reward, not keep tweaking the hierarchy patch.

- Exploration 99/100 progress boundary:
  - Frontier: `exploration_main` repeated forward at the end of the progress bar.
  - Hypothesis: progress alone might trigger a floor-clear route or UI transition at 99/100.
  - Changed one variable: kept `event_type=0`, reward/event fields zero, and only advanced `<progress>` to 99 and then 100.
  - Server check: `node .\server\test-bootstrap-server.js` passed after allowing `createExplorationExploreXml(100)`.
  - Runtime artifacts: `work/kssma-runtime-exploration-depth-after-99-*` and `work/kssma-runtime-exploration-depth-after-100-*`.
  - Observed: the client accepted progress 99 and 100, stayed in `RooneyJActivity`, kept the exploration main UI visible, and emitted no new route; logcat showed no fatal/native/resource error.
  - Conclusion: raw progress value is not the floor-clear trigger. Next proof must inspect or test parser-confirmed branch fields such as `complete`, not keep increasing progress or changing background/resource values.

- Exploration `complete=1` floor-clear check rejected:
  - Frontier: `exploration_main` at 100% still does not show floor-clear UI or emit a next route.
  - Hypothesis: parser-confirmed `<complete>1</complete>` might be the missing floor-clear branch switch after `<progress>100</progress>`.
  - Changed one variable: temporarily added `<complete>1</complete>` only when `createExplorationExploreXml(100)` was returned; lower progress responses stayed unchanged. The temporary field was reverted after the run.
  - Server check: `node .\server\test-bootstrap-server.js` passed before and after reverting the temporary field.
  - Runtime check: server was restarted, `fast-health` and `ensure-baseline` passed; progress was seeded to 99 with direct encrypted `/exploration/explore` posts, then the real client tapped forward once.
  - Runtime artifacts: `work/kssma-runtime-exploration-depth-complete1-before.png`, `work/kssma-runtime-exploration-depth-complete1-after.png`, `work/kssma-runtime-exploration-depth-complete1-requests.txt`, `work/kssma-runtime-exploration-depth-complete1-logcat.txt`, `work/kssma-runtime-exploration-depth-complete1-activity.txt`.
  - Observed: the real client request decrypted to `area_id=0`, `floor_id=2`, `auto_build=1`; response logged `progress=100` and byte size increased from 576 to 608, proving the added field was served. Screenshot still showed the same 100% exploration main screen with forward/return controls, no floor-clear panel or next route. `RooneyJActivity` stayed focused; no fatal/native/resource log appeared.
  - Conclusion: `complete=1` alone is not the floor-clear trigger for the current minimal payload. Do not repeat raw `progress=100` or standalone `complete=1`; next frontier is static recovery of the `_ExplorationMain` branch that fires `floor_clear`/`next_floor`, likely involving floorInfo/event/boss or command behavior state.

- Exploration nested `next_floor` floor-clear check rejected:
  - Frontier: `exploration_main` accepted 100% progress but still did not expose floor-clear or next-floor UI.
  - Hypothesis: `_ExplorationMain` floor-clear predicate would pass when `progress=100` and the parsed `next_floor` object had a nonzero scalar plus nested `floor_info`.
  - Changed one variable: temporarily replaced `<next_floor>0</next_floor>` only at `progress=100` with `<next_floor><area_id>1</area_id><floor_info>...</floor_info></next_floor>`. The product server response was reverted after runtime rejection; dynamic progress remains.
  - Server check: `node .\server\test-bootstrap-server.js` passed after reverting the rejected special payload.
  - Runtime check: installed/source `work/librooneyj-exploration-area-return-rerequest.so` SHA-256 matched `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`; server was reset, progress was seeded with direct encrypted `get_floor + 98 explore` posts, and the real client tapped forward once.
  - Runtime artifacts: `work/kssma-runtime-exploration-depth-nextfloor-after100.png`, `work/kssma-runtime-exploration-depth-nextfloor-after100-logcat.txt`, `work/kssma-runtime-exploration-depth-nextfloor-after100-activity.txt`, `work/kssma-runtime-exploration-depth-nextfloor-server.log`, `work/exploration-next-floor-floorclear-card-20260627.md`.
  - Observed: the real client request decrypted to `area_id=0`, `floor_id=2`, `auto_build=1`; server logged `progress=100` and encrypted response size `864`, proving the nested `next_floor` payload was served. Screenshot still showed the normal 100% walking screen with forward/return controls, no floor-clear panel, no next route, and no fatal/native crash.
  - Conclusion: the tested nested `next_floor` shape is not sufficient. Do not repeat raw `progress=100`, standalone `complete=1`, scalar `next_floor`, or this `area_id=1 + floor_info id=3` shape. Next frontier is exact static recovery of the `next_floor` parser/model copy and the `_ExplorationMain` predicate input before any more server XML changes.

- Exploration `/get_floor.next_floor` floor-clear predicate accepted:
  - Frontier: `exploration_main` reached 100% but needed the real floor-clear/next-floor entry instead of staying on the ordinary walking screen.
  - Hypothesis: the floor-clear predicate reads the next-floor object copied from `/connect/app/exploration/get_floor`, not the `next_floor` node inside `/connect/app/exploration/explore`.
  - Changed one variable: changed only `/exploration/get_floor` from scalar `<next_floor>0</next_floor>` to parser-confirmed nested `<next_floor><area_id>1</area_id><floor_info>...</floor_info></next_floor>`; `/exploration/explore` still returns `<next_floor>0</next_floor>` while dynamic progress reaches 100.
  - Server check: `node .\server\test-bootstrap-server.js` passed; encrypted `/get_floor` self-check response size is 928 and repeated `/exploration/explore` still decodes to dynamic progress with scalar `next_floor=0`.
  - ARM19 check: `fast-health` passed using healthy ARM19 legacy serial `emulator-5582`; installed/source `work/librooneyj-exploration-area-return-rerequest.so` SHA-256 matched `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`.
  - Runtime artifacts: `work/kssma-runtime-exploration-getfloor-nextfloor-main.png`, `work/kssma-runtime-exploration-getfloor-nextfloor-after100.png`, `work/kssma-runtime-exploration-getfloor-nextfloor-after100-logcat.txt`, `work/kssma-runtime-exploration-getfloor-nextfloor-after100-activity.txt`, `work/kssma-runtime-exploration-getfloor-nextfloor-live-server.log`.
  - Observed: real client `/get_floor` decrypted to `area_id=0`, `floor_id=2`, `check=1` and response bytes were 928. After direct encrypted seed requests set progress to 99, a real client forward tap returned `/exploration/explore` with `progress=100`; screenshot showed the new red `进入下一个区域` button while `RooneyJActivity` stayed resumed and no fatal/native/resource log appeared.
  - Conclusion: floor-clear entry is gated by `progress=100` plus the next-floor object populated from `/get_floor`. Keep nested `/get_floor.next_floor`; do not retry `explore.next_floor` for this blocker. Next frontier is clicking `进入下一个区域` and capturing the next route/scene.

- Exploration next-area button route captured:
  - Frontier: `进入下一个区域` button after 100% floor progress.
  - Hypothesis: the button reuses `/connect/app/exploration/get_floor` with the next-floor values parsed from the previous `/get_floor.next_floor`.
  - Changed one variable: no server or native change; tapped only the visible `进入下一个区域` button.
  - Server check: previous `node .\server\test-bootstrap-server.js` passed for the active server shape.
  - ARM19 check: same accepted `work/librooneyj-exploration-area-return-rerequest.so` baseline stayed installed and `RooneyJActivity` remained resumed.
  - Runtime artifacts: `work/kssma-runtime-exploration-nextarea-click.png`, `work/kssma-runtime-exploration-nextarea-click-logcat.txt`, `work/kssma-runtime-exploration-nextarea-click-activity.txt`, `work/kssma-runtime-exploration-getfloor-nextfloor-live-server.log`.
  - Observed: tapping the button emitted `/connect/app/exploration/get_floor` with decrypted `area_id=1`, `floor_id=3`, `check=1`. The server response was still the hardcoded old floor payload, so the screenshot returned to `Local Area 地区2` at `1%` instead of visibly becoming floor 3.
  - Conclusion: next-area routing works. Next server frontier is to make `/exploration/get_floor` mirror the requested/current floor and advertise the following floor, instead of always returning `area_id=0`, current `floor_info.id=2`, next `floor_info.id=3`.

- Exploration dynamic `/get_floor` accepted:
  - Frontier: after `进入下一个区域`, the client requested next floor `area_id=1`, `floor_id=3`, but hardcoded `/get_floor` kept returning floor 2 data.
  - Hypothesis: server can mirror the decrypted request into current `<area_id>` and current `<floor_info><id>`, while advertising the following floor in nested `<next_floor>`.
  - Changed one variable: replaced fixed `EXPLORATION_GET_FLOOR_XML` with `createExplorationGetFloorXml(areaId, floorId)`; default output remains the old accepted floor 2 payload, and the handler now calls it with decrypted request params. No native/resource/background changes.
  - Server check: `node .\server\test-bootstrap-server.js` passed, including encrypted self-check for observed `area_id=1`, `floor_id=3`.
  - ARM19 check: current service was restarted only; no APK/native reinstall. `RooneyJActivity` stayed resumed and logcat showed no fatal/native/resource error.
  - Runtime artifacts: `work/kssma-runtime-exploration-dynamic-getfloor-live-server.log`, `work/kssma-runtime-exploration-dynamic-getfloor-param-probe.png`, `work/kssma-runtime-exploration-dynamic-getfloor-nextarea.png`, `work/kssma-runtime-exploration-dynamic-getfloor-nextarea-logcat.txt`, `work/kssma-runtime-exploration-dynamic-getfloor-nextarea-activity.txt`.
  - Observed: after reseeding floor `0:2` to 99 and tapping forward, real client `/exploration/explore` returned `progress=100`. Tapping `进入下一个区域` emitted `/exploration/get_floor` with decrypted `area_id=1`, `floor_id=3`, `check=1`; screenshot showed `Local Area 地区3` at `1%`.
  - Conclusion: next-floor descent now works through at least floor 3 with server-generated `/get_floor`. Next frontier can be either repeated floor descent beyond floor 3, return behavior from exploration main, or the known exploration background value-domain.

- Exploration background value-domain:
  - Current server value is `<bg>exp_sarch</bg>`.
  - This is resource-backed but not accepted as visually correct.
  - Keep it separate from hierarchy/route work.
- Further exploration depth:
  - Repeated `explore`, event, battle, fairy, boss, reward, and floor-clear routes are not implemented as complete gameplay.
  - Add fields/routes only after a new route, screenshot, decrypted request, or native parser observable demands it.
- Exploration external mechanics pass:
  - FC2 3DS wiki pages became reachable after JP VPN; raw HTML is cached under
    `work/external-data/raw/fc2-ma3ds/pages/`.
  - Extractor: `work/kssma-fc2-exploration-extract.js`; output:
    `work/external-data/normalized/fc2-exploration-regions.json` and
    `work/exploration-fc2-mechanics-card-20260627.md`.
  - Follow-up system inference card:
    `work/exploration-system-inference-card-20260627.md`.
  - Strong external evidence now exists for normal walking formulas:
    `get_exp = AP * 3`, Gold in `[AP * 16, AP * 20]`, rare rewards at 5x,
    AP recovery `AP`, BC recovery `ceil(AP * 1.5)`, friendship/bond points
    `AP * 4`, and displayed progress as truncated integer percent.
  - FC2 normalized data now includes seven 3DS regions / 95 normal rows, but
    zh-Fandom early mobile/CN evidence still says six open regions / 70 rows.
    Treat FC2 region 7 as cross-version evidence until local master/client
    mapping proves it belongs in the current CN baseline.
  - First region starts: area 1 costs 1 AP, gives 3 EXP and 16-20 Gold, and
    needs 10 moves; area 2 costs 2 AP, gives 6 EXP and 30-40 Gold, and needs
    11 moves. First-region total normal walking is 84 moves / 194 AP.
  - Non-wiki sources cached under `work/external-data/raw/nonwiki-exploration/`:
    4399 and 962 confirm the exploration/secret-area flow and event categories;
    Gamebiz confirms campaign modifiers can multiply EXP/Gold and set
    exploration AP cost to 0 in special cases. NGA and atwiki candidate pages
    returned 403 in this pass.
  - Conclusion: current one-percent-per-click `/exploration/explore` and
    `gold=0/get_exp=0` are debug shims. Next faithful server frontier should be
    a no-branch first-region walking table after native/master ID mapping is
    checked, not battle/fairy/reward/guardian/background expansion.
- Exploration first-region no-branch walking table:
  - Frontier: `exploration_main` ordinary forward should use real first-region
    AP/EXP/Gold/progress values instead of the debug one-percent-per-click shim.
  - Hypothesis: keeping event branches off while changing only server-side
    walking state is enough to make no-branch forward more faithful without
    touching hierarchy/native/background.
  - Changed one variable: server exploration walking model only. Added the first
    region's six normal rows to `server/bootstrap-server.js`; `/get_floor`
    now mirrors the requested first-region row and current saved move count,
    and `/exploration/explore` advances move count with truncated progress,
    deterministic normal Gold, and normal EXP. Random events, guardian,
    rewards, background, and native patch are unchanged.
  - Server check: `node .\server\test-bootstrap-server.js` passed. Decrypted
    self-check responses now show first row forward as `progress=10`,
    `gold=18`, `get_exp=3`; second row first forward as `progress=9`,
    `gold=35`, `get_exp=6`.
  - Runtime check: attempted `fast-health`, but ARM19 primary
    `127.0.0.1:5583` was offline; per rules ran `repair-adb`, which timed out
    without `restartAllowed=true`. `adb devices -l` only showed other device
    serials, so no ARM19 gameplay claim was made.
  - Conclusion: server-only faithful no-branch walking is implemented and
    covered by encrypted self-check, but not yet ARM19-accepted. Next runtime
    frontier is to restore ARM19 transport, then validate
    `/area -> /floor -> /get_floor -> /explore` screenshot/route with nonzero
    EXP/Gold and 10% progress.
- ARM19 ADB transport diagnosis:
  - Frontier: every new gameplay goal reaches real-device validation, then
    stalls before client evidence can be collected.
  - Hypothesis: the recurring blocker is the emulator/ADB control plane, not
    the current exploration server route.
  - Command: `fast-health`, `adb devices -l`, process/port inspection, and
    manual `adb connect 127.0.0.1:5583`.
  - Observed: `fast-health` failed with `adb-transport`; ADB listed only
    Android 12/x86_64 devices `emulator-5554` and `emulator-5560`; the ARM19
    `kssma_arm19` processes were still running on ports `5582,5583`, but ADB
    did not list `127.0.0.1:5583` or `emulator-5582`, and manual connect
    returned connection refused / device not found.
  - Conclusion: ARM19 is currently a live-but-detached emulator process. Next
    work should repair runtime helper classification/restart policy before
    continuing gameplay validation.
- ARM19 ADB stability fix:
  - Frontier: the runtime helper needed to classify the live-but-detached ARM19
    state and recover without turning gameplay validation into manual ADB work.
  - Changed one variable: `work/kssma-runtime.ps1` / `work/kssma-runtime-lib.ps1`
    only. Added transport classes, hardened ADB failure detection, made getprop
    require non-empty stdout, added `self-check-transport`, and let `repair-adb`
    warm-restart only `detached-arm19`.
  - Checks: `self-check-transport` passed 6/6 fake cases; `node
    .\server\test-bootstrap-server.js` passed.
  - Runtime result: initial `fast-health` failed with `adb-transport` while
    `emulator.exe` / `emulator-arm.exe` for `kssma_arm19` were still running on
    `5582,5583`. `repair-adb` performed the warm restart; the command returned
    exit code 0 but emitted no JSON in that first detached run. Post-check
    `fast-health` then passed with `armeabi-v7a`, Android `4.4.2`, boot `1`;
    `status` showed new ARM19 PIDs and `lastRestartReason = automatic warm
    restart after detached-arm19`.
  - Follow-up: health-state `repair-adb` now emits JSON and does not restart.
    If another real detached event occurs, confirm the new warm-restart branch
    also emits JSON; the transport recovery itself is accepted.
- Other main-menu buttons:
  - Several routes are known from button triage, but only implement them one frontier at a time.

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
- Process lessons:
  `docs/reverse-archive/process-lessons-20260627.md`

## Compaction Note

This file was compacted on 2026-06-27 from 2269 lines / 236228 bytes into a startup index.
Do not paste old archive material back into this file. Add new detailed experiments to a topic
archive when they are no longer current, and keep this file focused on accepted facts, active
frontiers, and hard "do not repeat" constraints.
