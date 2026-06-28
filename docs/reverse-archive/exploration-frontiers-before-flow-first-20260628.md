# Exploration Frontier Archive Before Flow-First Reset

Moved out of `reverse-notes.md` on 2026-06-28 when `work/kssma-runtime.ps1 flow`
became the default gameplay acceptance path. These entries remain evidence, but they are no longer the startup index.

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
    region's six normal rows to `server/bootstrap-server.js`; `/floor` now
    returns six `floor_info` rows with process-local progress, `/get_floor`
    mirrors the requested row, and `/exploration/explore` advances move count
    with truncated progress, deterministic normal Gold, and normal EXP.
    Random events, guardian, rewards, background, and native patch are
    unchanged.
  - Server check: `node .\server\test-bootstrap-server.js` passed. Decrypted
    self-check responses show first row forward as `progress=10`, `gold=18`,
    `get_exp=3`; second row first forward as `progress=9`, `gold=35`,
    `get_exp=6`; after two first-row explores, `/floor` contains row id 2
    with `<progress>20</progress>`.
  - ARM19 check: `fast-health` passed on `127.0.0.1:5583`; `patch-lib` and
    final `install-check` verified installed/source
    `work/librooneyj-exploration-area-return-rerequest.so` SHA-256
    `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`.
  - Runtime artifacts: `work/kssma-runtime-exploration-mainline-*`.
  - Observed: fresh route order reached `/exploration/area ->
    /exploration/floor -> /exploration/get_floor -> /exploration/explore ->
    /exploration/explore`; the accepted area-1 click decrypted to
    `area_id=0`, `floor_id=2`, `check=1`, then two forwards decrypted to
    `area_id=0`, `floor_id=2`, `auto_build=1`. Responses logged
    `progress=10`, then `progress=20`, both with `gold=18` and `getExp=3`.
    Screenshot `work/kssma-runtime-exploration-mainline-step12-forward20.png`
    shows the exploration main progress at 20%.
  - Rejected during run: reversing `floor_info` XML order made visible row
    title/cost mapping inconsistent and was reverted. Natural XML order is
    kept; the client initially displays the high-numbered end of the list, and
    a swipe exposes `区域 1`.
  - Current limits: returning from exploration main via the visible return
    button re-entered `/exploration/area`, not the floor list; re-requested
    `/floor` response size increased after progress, but the current floor-list
    screenshot still does not visibly draw the 20% progress value.
  - Conclusion: first-region no-branch walking through two forwards is now
    ARM19-accepted. Next frontiers are separate: exact exploration-main
    `back` behavior to floor list, floor-list progress visual consumer, then
    100% floor-clear/next-floor continuation.
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
- Exploration media fields:
  - Frontier: entering a floor reaches exploration_main, but the visible stage
    background is wrong and stage BGM was missing.
  - Hypothesis: both are `/connect/app/exploration/get_floor` value-domain
    issues, not hierarchy/native state issues.
  - Changed/observed: `bg=exploration` reached exploration_main but screenshot
    `work/kssma-runtime-exploration-bg-main2.png` showed black/UI-sheet
    fragments, so it is rejected. `bg=bg` plus `bgm=sarch1` sent
    `/exploration/get_floor`, then crashed; logcat
    `work/kssma-runtime-exploration-media-bg2-main2-logcat.txt` shows
    `_AnmExpWalk::setPropertyValues -> rooney::res::loadImage ->
    jni_loadTexture`.
  - Static evidence: `_ExpBgmComponent::playBgm` prefixes `bgm_` before
    `AudioMan::playBgm`, and `download/sound/bgm_sarch1.ogg` exists. The server
    now sends `bgm=sarch1`, not `bgm_sarch1`.
  - Offline preview: `node .\work\extract-exploration-media-preview.js`
    self-checks the AES resource decoder against `mainbg_an_0_0`, then decoded
    52 PNG candidates into `work/exploration-media-preview/` and generated
    `contact-sheet.png`. Visual triage showed `exp_sarch` and `exploration`
    are UI atlases, not walking backgrounds; `battle_ef_bgXX` are full scene
    backgrounds.
  - Accepted background: server now sends `<bg>battle_ef_bg15</bg>`. Runtime
    route order reached `/exploration/area -> /exploration/floor ->
    /exploration/get_floor`; the accepted floor tap decrypted to `area_id=0`,
    `floor_id=7`, `check=1`, and screenshot
    `work/kssma-runtime-exploration-media-bg15-main.png` shows a proper
    sea/coast exploration scene instead of UI-sheet fragments. Activity stayed
    `RooneyJActivity`; no `Fatal signal`, `jni_loadTexture`, or resource-load
    crash was observed. `battle_ef_bg15` is accepted as the current non-eye-
    straining fallback; exact outer-region background mapping remains open.
  - Runtime control note: this validation exposed two non-gameplay issues:
    `repair-adb` recovered a getprop-timeout transport stall but emitted no
    JSON, and the login helper hit a WebView XPath parse bug. Do not treat
    those as exploration media failures.

- Exploration six-region area list and region backgrounds:
  - Frontier: the previous media note incorrectly treated the six rows as six
    floor backgrounds. Corrected understanding: the six wiki rows are outer
    secret areas/regions; each region contains its own internal `区域 N` rows.
  - Changed one variable: server exploration data only. `/exploration/area`
    now returns six cached wiki region names from
    `work/external-data/normalized/exploration-focus.json`: `人魚の断崖`,
    `燐光の湖`, `錯乱の平原`, `叡智の草原`, `猛獣の砂丘`, and
    `祝福を授ける山`. `/exploration/floor` now returns the selected region's
    own internal rows: 6, 9, 10, 10, 15, and 20 rows respectively. No native,
    APK, or resource files changed.
  - Background value-domain: `/exploration/get_floor` now chooses background by
    outer region, not by every individual internal row: `人魚の断崖 ->
    battle_ef_bg15`, `燐光の湖 -> battle_ef_bg03`, `錯乱の平原 ->
    battle_ef_bg12`, `叡智の草原 -> battle_ef_bg08`, `猛獣の砂丘 ->
    battle_ef_bg17`, `祝福を授ける山 -> battle_ef_bg00`. These are
    content-matched decoded PNG choices from
    `work/exploration-media-preview/contact-sheet.png`, not yet canonical
    masterdata mappings.
  - Server check: `node .\server\test-bootstrap-server.js` passed. It now
    asserts six area-list rows, 70 total cached internal rows, second region's
    nine-row floor list, and region-specific `/get_floor` bg/area_name values.
  - Conclusion: `Local Area` is removed from the server exploration payload.
    The current accepted mapping is wiki-region names plus visually matched
    region backgrounds. Next runtime validation should check visible area-list
    rows and one non-first-region descent; do not reopen this as a six-floor
    background problem.

- Exploration background candidate expansion:
  - Hypothesis: the previous 52-image preview was too narrow because it only
    scanned name-matched files in `save/download/rest`.
  - Command: `python .\work\build-background-candidate-sheets.py`.
  - Result: AES decode self-check passed against `mainbg_an_0_0`; the script
    found 5,565 PNG resources and 1,591 large/background-like candidates.
    Directory distribution: `image/adv` 1,284, `image/boss` 147, `rest` 130,
    `pack/mainbg` 16, plus small gacha/card groups. The focused
    `adv_bg`/`adv_bg_fog` set has 131 scene-sized 960x640 images.
  - Artifacts: manifest and TSV lists are in `work/background-candidates/`;
    contact sheets are in `work/background-candidates/sheets/`.
  - Conclusion: the old `rest/battle_ef_bg*` mapping is only a temporary
    accepted fallback, not the full background search space. `人魚の断崖`
    should be re-selected from the full candidate sheets; visible beach/coast
    candidates include `image/adv/adv_bg14`, `adv_bg26`, `adv_bg27`,
    `adv_bg28`, `adv_bg37`-`adv_bg41`, and their `adv_bg_fog*` variants.

- Exploration per-area background source audit:
  - Frontier: determine whether a local or web source maps exploration
    sub-areas to walking background ids, after user evidence showed one outer
    area can use different bgs (`人魚の断崖` area 1/2 = `adv_bg14`, area 3 =
    `adv_bg26`).
  - Command: local `rg`/`rg -a` sweep for `adv_bg14`, `adv_bg26`, Mermaid
    Cliffs names, `areaN.jpg`, `bgName`, `adv_bg%d`, `dungeon_%d_%d.pack`,
    resource route XML, layout XML, sdcard master database names, and external
    normalized wiki data; web searches checked atwiki/FC2/Fandom/Famitsu-style
    sources for a background map.
  - Result: `adv_bg14`, `adv_bg26`, and fog variants are present in local
    `advbg` packs and are loadable through the `adv` resource route;
    `layout_exploration_main.xml` consumes `/get_floor <bg>` as `bgName`. No
    local table maps `outer area + sub-area -> adv_bg*`; the current sdcard dump
    lacks a dungeon/exploration master table, despite `local_battle_player.xml`
    advertising `dungeon_rev area_id=0..6`. Web/wiki sources found
    names/mechanics/screenshots but no authoritative walking-background table.
  - Artifact: `work/exploration-bg-source-audit-20260628.md`.
  - Conclusion: implement a small per-area background override table with
    source/confidence notes, seeded by the two user-proven Mermaid Cliffs
    mappings, and fall back to a per-outer-area/default bg only where evidence
    is missing.

- Exploration zh-Fandom area names:
  - Frontier: area names must come from the Chinese wiki source, not from an
    agent-made translation.
  - Command: inspected cached zh-Fandom `探索` page
    `work/external-data/raw/zh-fandom/pages/117.json` and normalized
    `work/external-data/normalized/exploration-focus.json`; live Fandom API is
    currently Cloudflare-blocked, so the cached pageid/revid/timestamp remain
    the auditable source.
  - Result: the zh-Fandom page prose/table labels are Chinese, but the six
    exploration area headings are still mixed Japanese strings:
    `人魚の断崖`, `燐光の湖`, `錯乱の平原`, `叡智の草原`, `猛獣の砂丘`,
    `祝福を授ける山`. The cached normalized JSON already uses these names.
    Local 4399/962 article caches discuss exploration mechanics but do not
    provide a usable six-area name table.
  - Artifact: `work/exploration-zh-area-names-card-20260628.md`.
  - Conclusion: keep these zh-Fandom headings as current visible area names.
    Do not substitute unproven simplified translations such as `人鱼断崖` until
    a stronger CN-client or Chinese-wiki source proves them. Background id
    selection remains a separate screenshot/resource override problem.

- Exploration six-region temporary `adv_bg` map:
  - Frontier: `/connect/app/exploration/get_floor <bg>` value selection for the
    six current outer areas.
  - Hypothesis: user-specified region-level `adv_bg*` values are better
    temporary walking backgrounds than the old `battle_ef_bg*` fallback while
    per-floor canonical mapping remains unknown.
  - Changed one variable: server-side region background table only. Every floor
    still inherits its outer area's `regionBg`; no area names, BGM, progress,
    hierarchy, native patch, or resource files changed.
  - Mapping: `人魚の断崖 -> adv_bg14`, `燐光の湖 -> adv_bg11`,
    `錯乱の平原 -> adv_bg12`, `叡智の草原 -> adv_bg15`,
    `猛獣の砂丘 -> adv_bg37`, `祝福を授ける山 -> adv_bg42`.
  - Static resource check: all six values are present in
    `work/background-candidates/adv-bg.tsv` as 960x640 `image/adv/adv_bg*`
    resources.
  - Server check: `node .\server\test-bootstrap-server.js` passed. Direct
    local XML checks show `0:7 bg=adv_bg14 bgm=sarch1 name=人魚の断崖`,
    `1:16 bg=adv_bg11 bgm=sarch1 name=燐光の湖`, and the fifth/sixth
    region samples still return `adv_bg37`/`adv_bg42`.
  - ARM19 check: `fast-health` passed on `127.0.0.1:5583`
    (`armeabi-v7a`, Android `4.4.2`, boot `1`). Installed/source native
    baseline was re-verified after repatching
    `work/librooneyj-exploration-area-return-rerequest.so` to SHA-256
    `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`.
  - Runtime artifacts: `work/kssma-runtime-exploration-advbg-*`.
    First accepted floor tap decrypted to `area_id=0`, `floor_id=7`,
    `check=1`; screenshot
    `work/kssma-runtime-exploration-advbg-area0-main.png` shows the
    `adv_bg14` sea/coast background. Returning to the area list and selecting
    the second region emitted `/exploration/floor` with `area_id=1`; the
    accepted second-region floor tap decrypted to `area_id=1`, `floor_id=16`,
    `check=1`; screenshot
    `work/kssma-runtime-exploration-advbg-area1-main.png` shows the
    `adv_bg11` green ruin/lake background. Activity stayed
    `RooneyJActivity`; no `Fatal signal`, `SIGSEGV`, `jni_loadTexture`, or
    texture-load crash was observed.
  - BGM note: `/get_floor` remains `bgm=sarch1`; this run only verified that
    the background change did not remove or rename the accepted BGM field.
  - Conclusion: region-level temporary `adv_bg` mapping is accepted for the
    first two runtime samples and server-covered for all six regions. The next
    background frontier is an explicit per-floor override table when more
    screenshot evidence is available.

- Runtime native baseline guard:
  - Frontier: server-only/background tests kept colliding with old exploration
    hierarchy behavior because installed `librooneyj.so` could be silently
    reset to a non-accepted version.
  - Root cause: `work/kssma-runtime-lib.ps1 Resolve-ApkPath` chose the newest
    `work\*signed.apk` when `patch-lib` or `install-apk` omitted `-ApkPath`.
    The newest signed APKs (`million-cn-exploration-floorlist-xmlfix-signed.apk`
    and `million-cn-animationguard-signed.apk`) embed stock-like
    `librooneyj.so` SHA-256
    `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`, not
    the accepted exploration patch. Old docs also presented animationguard as a
    native baseline command.
  - Changed one variable: runtime control only. `patch-lib` and `install-apk`
    now require explicit `-ApkPath`; no latest-APK guessing is allowed.
    `patch-lib` checks installed/source SHA before force-stopping and pushing,
    so matching native bytes produce `status=already-matched` and no device
    mutation. Added `ensure-exploration-baseline`, which compares the installed
    library to `work/librooneyj-exploration-area-return-rerequest.so`
    (`8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`) and
    patches only on mismatch.
  - Check: `patch-lib` and `install-apk` without `-ApkPath` both failed
    locally in under 100 ms with `failureClass=source-required`, empty
    `stages`, and no ADB/device mutation. `node
    .\server\test-bootstrap-server.js` still passed. `ensure-exploration-baseline`
    is the only accepted automatic native correction for exploration runtime
    checks.
  - Conclusion: `librooneyj.so` can no longer change just because a runtime
    helper guessed an APK. Future server-only/background validation should use
    `fast-health`, server status, and optionally `ensure-exploration-baseline`;
    it must not use generic `patch-lib` or `install-apk` without explicit
    intent.

- Exploration smoke flow runner:
  - Frontier: manual exploration validation was spending most time on
    screenshot/OCR timing and imprecise taps instead of request/state evidence.
  - Hypothesis: a single logged flow can replace the per-click manual loop if
    it owns the server, waits on routes/params, captures key screenshots, and
    writes a structured failure class.
  - Changed one variable: runtime automation/logging only. Added
    `work/kssma-runtime.ps1 flow -Scenario exploration-smoke` and
    `flow -Scenario self-check`; server gameplay XML/native behavior was not
    changed for this runner. `/connect/app/exploration/get_floor` response logs
    now include `regionId`, `floorId`, and `bg` for request-log assertions.
  - Checks: `powershell ... .\work\kssma-runtime.ps1 flow -Scenario self-check`
    passed, including route/param matching and WebView notice classifier
    guards. `node .\server\test-bootstrap-server.js` passed.
  - ARM19 check: artifact
    `work/kssma-flow-exploration-smoke-dev21-area1-two-step-smoke` passed on
    `127.0.0.1:5583`. Route sequence was
    `/connect/app/notification/post_devicetoken -> /connect/app/login ->
    /connect/app/exploration/area -> /connect/app/exploration/floor area_id=0
    -> /connect/app/exploration/get_floor area_id=0 floor_id=7 check=1 ->
    /connect/app/exploration/area -> /connect/app/exploration/floor area_id=1
    -> /connect/app/exploration/get_floor area_id=1 floor_id=16 check=1`.
    The second-region `get_floor` response logged `regionId=1`,
    `floorId=16`, and `bg=adv_bg11`.
    Screenshots cover main menu, area list, floor list, stage page, returned
    area list, selected second area, second-region floor list, and
    second-region stage page. Logcat had no `Fatal signal`, `SIGSEGV`,
    `JResourceLoader`, `loadTexture`, or blocking `contents_miss` evidence.
  - Rejected/learned during development: treating a transient native mainmenu
    view as a WebView notice caused a blind top-right tap into gacha; the
    notice closer now requires a real WebView and uses Back first. A full ARM19
    warm restart can re-extract stock-like `librooneyj.so` from the installed
    APK into app-lib; `ensure-exploration-baseline` caught and repaired that
    once by patching only the accepted `.so`.
  - Current scope: v1 `exploration-smoke` proves the stable core hierarchy
    loop and covers a second-region descent. The second region requires a
    two-step gesture: tap its list row to make it the current top item, then
    tap the current item to enter. Single-tap row attempts in artifacts
    `dev18`/`dev19` and `work/kssma-flow-area1-calibration-*` are rejected as
    incomplete automation, not gameplay failures.
