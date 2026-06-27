# Exploration Floorlist Deadends 20260625 20260627

Exploration initial status and route/schema baseline.

Source: `reverse-notes.md` before compaction, archived in full at `reverse-notes-full-before-compaction-20260627.md`.

<!-- original lines 365-384 -->

## Exploration reconstruction status

- Runtime is confirmed suitable: Android 4.4.2/API19 ARM `emulator-5582` enters the main menu and can drive exploration; do not switch back to Android 12 or x86/Houdini runtimes for this APK.
- `server/bootstrap-server.js` now answers encrypted:
  - `POST /connect/app/exploration/area`
  - `POST /connect/app/exploration/floor`
- `server/test-bootstrap-server.js` covers both encrypted routes and passed after adding the current exploration XML fields.
- `AreaInfoTagParser` fields confirmed from `librooneyj.so`:
  - `id`, `name`, `x`, `y`, `prog_area`, `prog_item`, `area_type`
- `ExplorationFloorTagParser` fields confirmed:
  - `area_id`, `boss_down`, `floor_info_list`
- `FloorInfoTagParser` fields confirmed:
  - `id`, `type`, `unlock`, `progress`, `cost`, `boss_id`, `found_item_list`
- ARM19 retest with `<id>2</id>`, `<type>0</type>`, and `<unlock>1</unlock>`:
  - `/connect/app/exploration/area` returns 200 and renders `Local Area` on the map.
  - `/connect/app/exploration/floor` returns 200, decrypts through the client, and does not crash.
  - UI still stays on the area map after selecting the area; waiting 20s does not produce another request.
- Native notes:
  - `_ExplorationModel::update(TiXmlElement)` recognizes the floor response and calls `_ExplorationFloorTagParser::parse` then `_ExplorationModel::init(ExplorationFloorTagData)`.
  - `_ExplorationModel::init(ExplorationFloorTagData)` copies `area_id`, `boss_down`, and `floor_info_list` into model offsets `0x50`, `0x54`, and `0x58`.

<!-- original lines 640-682 -->

## Exploration floor state-only diagnostic

- Frontier: `/connect/app/exploration/floor` returns 200, but the client remains on the area map instead of showing `floor_list`.
- Hypothesis: the layout floor command sends the request but leaves `_ExplorationArea` in the area-list state, so `_ExplorationArea::preUpdate()` never enters the state-3 floor-list branch.
- Changed one variable: restored the failed error-gate diagnostic at `librooneyj.so+0x0034204E` to the stock `21d0`, then added only a diagnostic write after `_ExplorationArea::Floor::exec` triggers the model: `librooneyj.so+0x00340A9C 01a894f68ffb -> 0323eb63c046`, disassembling as `movs r3,#3; str r3,[r5,#0x3c]; nop`. This deliberately skips the copied-area vector destructor and is not a final patch.
- Server check: `node .\server\test-bootstrap-server.js` passed after rebuilding `work\million-cn-animationguard-signed.apk`.
- ARM19 check: installed the rebuilt APK, restored hosts and mount, then manually launched on `127.0.0.1:5583` after confirming `ro.product.cpu.abi=armeabi-v7a`, Android `4.4.2`, `sys.boot_completed=1`, and `/storage/sdcard/.../save/download/rest/treasurebox` exists. Artifact prefix: `work/explore-state3-floorcmd-20260625-1755`.
- Observed: server reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, `/connect/web/`, `/connect/app/exploration/area` 200, and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Screenshot `work/explore-state3-floorcmd-20260625-1755-floor.png` still shows the area map and `Local Area`, not a floor list. Activity stayed `com.test.RooneyJActivity`. Pulled `/data/app-lib/com.square_enix.million_cn-2/librooneyj.so` and verified installed bytes: `0x340a9c=0323eb63c046`, `0x34204e=21d00023`.
- Conclusion: state write alone is not sufficient. Together with the earlier mounted run where only `0x34204E 21d0 -> 21e0` also failed, the next diagnostic should test the two gates together because static `preUpdate` requires both `state==3` and the no-error branch before `createFloorList()`.
- Next: run exactly one combination diagnostic: keep the state write and re-enable the error-gate bypass. If that still fails, stop patching these two gates and inspect floor model data / `createFloorList()` population or callback timing instead.

## Exploration floor combined gate diagnostic

- Frontier: determine whether the visible floor-list blocker is simply the combination of two preUpdate gates: `_ExplorationArea` state must be 3 and `_ExplorationModel::isError()` must take the no-error branch.
- Hypothesis: the prior diagnostics failed because each only opened one of the two gates. Opening both should allow `preUpdate` to call `createFloorList()` and show `floor_list`.
- Changed one variable: kept the state-write diagnostic at `librooneyj.so+0x00340A9C` and re-enabled the error-gate bypass at `librooneyj.so+0x0034204E 21d0 -> 21e0`. No server XML, resource, emulator, route, or click-coordinate change.
- Server check: `node .\server\test-bootstrap-server.js` passed. Output APK bytes were verified as `0x340a9c=0323eb63c046` and `0x34204e=21e00023`.
- ARM19 check: installed the rebuilt APK, restored hosts and mount, verified installed `/data/app-lib/com.square_enix.million_cn-1/librooneyj.so` bytes as `0x340a9c=0323eb63c046` and `0x34204e=21e00023`, then launched and tapped through main menu -> exploration -> area. Artifact prefix: `work/explore-combo-floorcmd-20260625-1808`.
- Observed: server reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, `/connect/web/`, `/connect/app/exploration/area` 200, and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Screenshot `work/explore-combo-floorcmd-20260625-1808-floor.png` still shows the area map and `Local Area`, not a floor list. Activity stayed `com.test.RooneyJActivity`; logcat showed no fatal signal, texture crash, or missing resource evidence.
- Conclusion: opening those two gates at the chosen points is still not sufficient. Static `update` evidence now matters more: in the state-4 area-list branch, after `getSelected("area_list", touch)` and a selected tag check, `0x0034149A..0x0034149C` writes `state=0`, which can plausibly overwrite the `Floor::exec` state write after the floor command has already triggered the request.
- Next: move the diagnostic away from `Floor::exec` and test the cleaner native state transition point: change only `0x0034149A movs r3,#0` to `movs r3,#3` so the original state-4 branch exits into floor-wait state without skipping the copied-area vector destructor. Keep or drop the error-gate bypass based on the exact next hypothesis; do not keep the destructor-skipping `0x00340A9C` patch as a final path.

## Exploration state-4 exit diagnostic

- Frontier: `/exploration/floor` 200 still leaves the client on the area map.
- Hypothesis: after `area_list` selection, `_ExplorationArea::update` state-4 branch writes `state=0`, covering the floor-wait state before `preUpdate` can build the floor list.
- Changed one variable: restored the destructor-skipping `0x00340A9C` diagnostic to stock bytes `01a894f68ffb`, kept the already-tested no-error branch bypass at `0x0034204E=21e0`, and changed only `librooneyj.so+0x0034149A 0023 -> 0323`, so the original `str r3,[r4,#0x3c]` writes `state=3` instead of `state=0`. No server XML, resource, emulator, route, or click-coordinate change.
- Server check: `node .\server\test-bootstrap-server.js` passed. Output APK bytes were verified as `0x340a9c=01a894f68ffb`, `0x34149a=0323e363`, and `0x34204e=21e00023`.
- ARM19 check: installed the rebuilt APK, restored hosts and mount, verified installed bytes as `0x340a9c=01a894f68ffb`, `0x34149a=0323e363`, `0x34204e=21e00023`, then launched and tapped main menu -> exploration -> area. Artifact prefix: `work/explore-state4exit-20260625-1823`.
- Observed: server reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, `/connect/web/`, `/connect/app/exploration/area` 200, and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Screenshot `work/explore-state4exit-20260625-1823-floor.png` still shows the area map and `Local Area`, not a floor list. Activity stayed `com.test.RooneyJActivity`; logcat had no fatal signal, texture crash, or missing resource evidence.
- Conclusion: state forcing at the tested transition points is not producing the floor-list observable. Do not keep stacking state patches. The active gap is now likely data/model/layout population: whether `_ExplorationFloorTagParser` fills the same `floor_info_list` that `createFloorList()` consumes, whether our `<exploration_floor>` shape/value domain is wrong, or whether another completion callback/flag is missing.
- Next: restore failed diagnostics from `work/build-animation-nullguard.py` and perform a static parser/model/createFloorList pass before any more runtime APK patches.

## Exploration return mainmenu route fix

- Frontier: exploration area page can load, but pressing the right-side return button showed the generic "cannot connect to server" modal.
- Hypothesis: the return button does reach the local server, but it calls `/connect/app/mainmenu` while the server only implemented `/connect/app/mainmenu/update`, causing the client to treat the missing route as a connection failure.
- Changed one variable: added a `POST /connect/app/mainmenu` handler that reuses the already-proven `MAINMENU_UPDATE_XML` payload. This intentionally keeps return behavior identical to the minimal main-menu update path until native/runtime evidence requires a split.
- Server check: `node .\server\test-bootstrap-server.js` passed, including a new assertion that `/connect/app/mainmenu?cyt=1` decrypts to `MAINMENU_UPDATE_XML`.
- ARM19 check: restarted the human helper server so the new handler was live, recovered ARM19 ADB from a stale `127.0.0.1:5583 offline` transport, verified `emulator-5582` as `armeabi-v7a` / Android `4.4.2`, restored hosts and mount, launched the game, clicked main menu exploration at `1090,245`, then clicked the exploration page return button at `1090,585`.
- Observed: server log recorded `POST /connect/app/exploration/area?cyt=1` with encrypted 200, then `POST /connect/app/mainmenu?cyt=1` with encrypted 200, `bytes=576`, `source="minimal mainmenu"`. Screenshot `work/return-fix-after-return.png` shows the normal main menu after return, with no "cannot connect server" modal. Activity stayed `com.test.RooneyJActivity`; logcat tail had no `Fatal`, `SIGABRT`, `SIGSEGV`, `JResourceLoader`, `getSDPackFile`, or missing-file evidence.
- Conclusion: the exploration-page return failure was a missing server route, not a stopped server, hosts issue, resource miss, or APK problem. The return-to-main-menu path is fixed for the current local baseline.
- Next: continue the real exploration frontier separately: `/connect/app/exploration/floor` returns 200 but still does not populate/show `floor_list`.

<!-- original lines 751-1373 -->

## Exploration floor createFloorList reachability

- Frontier: `/connect/app/exploration/floor` returns encrypted 200 but the visible UI stays on the area map instead of showing `floor_list`.
- Hypothesis: Linnaeus/Locke suggested a cheap value-domain test: change only the `EXPLORATION_FLOOR_XML` floor `<id>` from `2` to `1`, leaving the area response and APK logic unchanged, to see whether the floor list appears.
- Changed one variable: temporarily changed only `server/bootstrap-server.js` `EXPLORATION_FLOOR_XML` `<floor_info><id>` from `2` to `1` and updated the self-check assertion. After the runtime result showed no visible improvement, this temporary protocol change was reverted.
- Server check: `node .\server\test-bootstrap-server.js` passed with the temporary `id=1` candidate and passed again after reverting to `id=2`.
- ARM19 check:
  - First run used the current installed native lib and artifacts `work/kssma-runtime-explore-floor-id1-after-floor-*`. Server saw `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`.
  - That run crashed with `Fatal signal 4 (SIGILL)` at `pc 003420ce /data/app-lib/com.square_enix.million_cn-2/librooneyj.so (_ExplorationArea::preUpdate()+429)`, exactly the earlier `createFloorList` diagnostic probe location. This proves stock control flow naturally reaches the `createFloorList` call after the floor response.
  - Rebuilt the default non-diagnostic APK with `python .\work\build-animation-nullguard.py`, applied only the native fast path `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 patch-lib -ApkPath .\work\million-cn-animationguard-signed.apk`, and verified installed bytes: `0x3420ce=fff77dfc`, `0x34204e=21d0`, `0x340a9c=01a894f68ffb`, `0x34149a=0023`.
  - Second run used artifacts `work/kssma-runtime-explore-floor-id1-stock-after-floor-*`. Server again saw `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Activity stayed `com.test.RooneyJActivity`, logcat had no fatal signal or resource-miss evidence, but screenshot `work/kssma-runtime-explore-floor-id1-stock-after-floor.png` still shows the `Local Area` map, not a floor list.
- Observed: `id=1` is not sufficient. The important new evidence is not the candidate value; it is that the client reaches the `createFloorList` call naturally and then returns without visible list creation.
- Conclusion: stop blind XML value guessing at this frontier. The next unknown is inside or immediately before `createFloorList`: whether `_ExplorationModel+0x58` has a nonzero `floor_info_list` vector, whether `_ExplorationFloorTagParser`/`_ExplorationModel::init` failed to populate it, or whether `createFloorList` builds items that stay hidden because required item fields/layout tags are missing.
- Next: the next real-device experiment must prove one of these observables, in order: `createFloorList` vector count, parser/init population of `model+0x58`, or visible list item creation. Do not change floor XML values again until one of those observables points at a specific missing field/value.

## Exploration command route static map

- Frontier: after `floor_list` becomes visible, floor-row, forward, next-floor, and return clicks need route evidence before adding more server handlers.
- Hypothesis: existing exploration layout commands and annotated native notes can map enough command owners to route strings without running the emulator or editing XML/server code.
- Command/static pass: wrote `work/exploration-command-route-map.md`. Read only the requested exploration layout XML, existing `work/*exploration*` / `work/*annotated*` evidence, and this notes file.
- Observed:
  - `layout_exploration_area.xml:210` behavior `get_floor` issues command `floor`; `work/exploration-annotated-strings.txt:312` shows `_ExplorationArea` triggering `get_floor`; `work/exploration-annotated-strings.txt:920,975` shows `_ExplorationModel::floor(int)` building `area_id` and calling `Model::connect(0x15, params)`. Prior runtime evidence maps this to `/connect/app/exploration/floor` with decrypted `area_id=0`.
  - Floor-row selection is a different edge: `work/exploration-ui-disasm-annotated.txt:583-586` shows `_ExplorationArea::update` copying the `model+0x58` floor vector and calling `_ExplorationModel::move(area_id, floor_info, false)`, but the allowed annotations do not include the `move` connect id or route.
  - `foward`/`foward2` are statically tied to `exploration/explore` by route string and `_ExploreTagParser` response branch at `work/exploration-model-update-disasm.txt:69,121`, but the command-to-connect call and request keys are still missing.
  - `next_floor` remains open among `exploration/get_floor`, `exploration/floor`, or `exploration/explore`; no allowed native command handler was found.
  - Area-page return/back is proven separately by `_TownModel::mainmenu()` and prior runtime `/connect/app/mainmenu`; walking-scene `back`/`return_town` still need handler evidence.
- Dead ends: no explicit `Model::connect` call was found in allowed exploration annotations for `foward`, `foward2`, `next_floor`, `battle`, `fairyHistory`, `boss_lose`, `fairy_lose`, or `reward_check`. `boss_lose` and `reward_check` have no matching extracted exploration route string.
- Conclusion: only area `floor` -> `/exploration/floor` and area-page return -> `/mainmenu` are high-confidence closed edges. `foward`/`foward2` -> `/exploration/explore` is medium confidence; `next_floor` and floor-row click require `_ExplorationModel::move` / command dispatch recovery before server implementation.
- Next: static recover `_ExplorationModel::move(int, smart_ptr<FloorInfoTagData>, bool)` and the command dispatch owner for `foward`/`next_floor`; runtime validation should only click a floor row after `floor_list` is visible and should collect the next route plus decrypted params, not add a route first.

## Exploration value-domain static pass

- Frontier: even after area/floor parser fields are known, `area/floor/bg/bgm/boss/card/item` values need static value-domain evidence so the server does not blindly guess XML values.
- Hypothesis: bundle/local XML, masterdata/resource samples, and the 140330 save dump can provide usable values, but parser/schema evidence and layout/resource consumers must stay separate.
- Command/static pass: read the required repo context plus `work/exploration-static-roadmap-20260626.md`; inspected only allowed bundle trees, `work/million_cn/sdcard_dump`, and existing cards/notes. Wrote:
  - `work/value-domain-cards/exploration-area.md`
  - `work/value-domain-cards/exploration-floor.md`
  - `work/value-domain-cards/exploration-explore.md`
- Observed:
  - `local_battle_player.xml` has `dungeon_rev` entries for `area_id=0..6`; prior runtime already proved `area_id=0` can render a local area and produce decrypted `/exploration/floor` request `area_id=0`.
  - No bundled `exploration_area`, `exploration_floor`, or `exploration_explore` response sample was found in the allowed apktool/jadx bundle XML. Layout files only provide consumer bindings, not response schema.
  - `rule_resource.xml` maps exploration area scene `3002` to `exp_map_cloud01`, `exp_map_cloud02`, `exp_map_bg`, `exploration_place`; exploration main scene `3005` to `exp_sarch`, `exploration`, `cmn_window`, `cmn_cardface`.
  - `rule_resource_route.xml` maps `bgm*` to `save/download/sound/*.ogg`, `card*`/`thumbnail*` to `save/download/image/card/`, `adv*` to `save/download/image/adv/`, `boss*` to `save/download/image/boss/`, and `master*` to `save/database/`.
  - The save dump contains `bgm_sarch1/2/3.ogg`, `bgm_common1.ogg`, exploration rest resources such as `rja_exp_floor_list`, `rja_exp_walk`, `rja_exp_area_name`, `rja_exp_sp_item`, and item resource families `item_*`, `common_item_*`, `mh_*`, `rja_exp_mh_*`.
  - A minimal static parse of `master_item` found 58 records; ids including `5`, `6`, `42`, `44`, `45`, `46`, `48`, `58`, `61`, `63`, `65`, `74`, `76`, `78`, `81`, `201`, `203`, `204`, `208`, `210`, and `8001` have exploration-related resource coverage.
  - A minimal static parse of `master_boss` found 285 records and sample chains such as `boss_id=1` name `机械巨人` with image candidate `170`; `boss_full170` exists. This shows boss master id and boss image id can differ.
  - Existing `master-resource-map` / owner-card cards prove card ids `9`, `30`, `101`, and `179` are resource-safe candidates when a schema needs a user-card/master-card chain, but `leader_serial_id=2367` is not a `master_card_id`.
- Minimal usable value sets:
  - Area baseline: `area_id=0`, `locations=0`, one `area_info` with `id=0`, `name=Local Area`, `x=0`, `y=0`, `area_type=1`, `prog_area=0`, `prog_item=0`.
  - Floor baseline: `area_id=0`, `boss_down=0`, one `floor_info` with `id=2`, `type=0`, `unlock=1`, `progress=0`, `cost=1`, `boss_id=0`, empty `found_item_list`.
  - Explore no-branch candidates after schema proof: `bgmName=bgm_sarch1`, `bgName=exp_sarch`, `areaName=Local Area`, `progress=1`, `gold=0`, `getExp=0`, boss/fairy/event sentinel values `0`, and no reward object.
- Dead ends:
  - No original area/floor/explore response XML sample was found in the allowed bundle sources.
  - No master floor table or original floor id/type/unlock/progress/cost source was found.
  - `floor_info/id=1` was already tried and did not fix visible floor-list creation; do not repeat it as a value sweep.
  - Do not treat `boss_full<N>` filenames as direct `boss_id` values; `master_boss` shows a separate image id.
  - Do not treat `leader_serial_id=2367` as a card master/resource id.
- Conclusion: the current area/floor values are usable as a local diagnostic baseline, not as original data. The next blocker is still whether `_ExplorationArea::createFloorList()` sees floor vector count `0` or `>0`; value-domain evidence should be used after that observable points at parser/model population or UI/item construction.
- Next: run the count probe described in `work/exploration-floorlist-probe-card.md`, or statically recover `_ExploreTagParser` before emitting any `/exploration/explore` XML.

## Exploration floor count probe preparation and runtime harness block

- Frontier: classify the `/connect/app/exploration/floor` 200 -> no visible `floor_list` blocker by proving whether `_ExplorationArea::createFloorList()` sees `_ExplorationModel+0x58` vector count `0` or `>0`.
- Hypothesis: a two-branch native SIGILL probe at `librooneyj.so+0x00341A34/0x00341A36` can classify the floor vector before any UI item construction or resource lookup.
- Changed one variable: generated `work/librooneyj-exploration-count-probe.so` from `work/installed-lib-stock-createfloor.so`, changing only `0x00341A34: 01 E1 -> 00 DE` and `0x00341A36: 9B 46 -> 01 DE`. The patched window was `00 2A 00 DC 00 DE 01 DE`.
- Runtime control fixes made during setup:
  - `work/kssma-runtime-lib.ps1` `fast-health` now gives the classic ARM19 `getprop` sequence 2s instead of 1s; direct ADB proved the old 1s timeout could return partial `armeabi-v7a / 4.4.2` without `sys.boot_completed=1`, causing false `adb-transport` failures.
  - `Invoke-EnsureRuntime` cache validation now uses the same 2s health read.
  - `restart-runtime` and fresh emulator start now invalidate `baselineOk/hostsOk/mountOk/displayOk/audioOk/packageOk`, because a reboot reset `/system/etc/hosts` while `runtime-state.json` still claimed `hostsOk=true`.
- ARM19 check:
  - `patch-lib -ApkPath .\work\librooneyj-exploration-count-probe.so` succeeded and installed the diagnostic native library.
  - First `run -DriveLogin -Tag exploration-count-probe-login` failed before driving login because `/system/etc/hosts` had reset to only `127.0.0.1 localhost` while stale state claimed hosts were valid; `kssma-runtime.ps1 hosts` repaired the mapping.
  - Second `run -DriveLogin -Tag exploration-count-probe-login2` reached `RooneyJActivity`, and server saw `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, then `/connect/web/`.
  - The one-shot notice handler pressed Android Back on the daily `/connect/web/` notice and produced an exit confirmation dialog (`确定结束游戏吗?`), then hung long enough for the outer command to time out. No `/exploration/area`, `/exploration/floor`, or target SIGILL was observed in this run.
  - After clicking `No`, current UI was a native `android.view.View` under `RooneyJActivity`; manual taps at known exploration coordinates `1090,235` and `760,280` produced no exploration request, so the run was not in a proven main-menu state.
- Restore check: restored the stock native library with `patch-lib -ApkPath .\work\million-cn-animationguard-signed.apk`. The helper's post-verify timed out, but direct pull verified installed bytes at `0x00341A30` are stock `00 2A 00 DC 01 E1 9B 46`; no diagnostic UDF probe remains installed.
- Observed: the count-probe hypothesis remains valid but was not classified. The blocker was runtime harness entrance reliability, not floor XML evidence. Do not interpret this run as proof of empty vector or UI item failure.
- Conclusion: before rerunning the count probe, harden the login/notice path so `run -DriveLogin -DismissNoticeWebView` ends in a proven main-menu observable and never presses Back into the app-level exit dialog without confirming WebView state transition.
- Next: fix the notice/main-menu harness first, then rerun exactly the same count probe and collect only three observables: server `/exploration/area`, server `/exploration/floor`, and SIGILL PC `00341a34` vs `00341a36`.

## Runtime control long-tail false result hardening

- Frontier: runtime entrypoints still had long-tail false success/failure cases before the next real ARM19 gameplay observable.
- Hypothesis: bounded per-property health reads, reboot-aware baseline cache invalidation, and structured patch-lib verification failures reduce noise without changing APK or server protocol.
- Changed one variable: only `work/kssma-runtime-lib.ps1` runtime control logic. `fast-health` now reads the three allowed properties as separate bounded `getprop` commands with one retry; runtime state records `/proc/uptime` and invalidates baseline cache if uptime moves backward; `patch-lib`/`install-check` distinguish `pm path` or pull timeout from real `package-missing` and return structured verify data.
- Server check: not run; server protocol was not touched.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health` returned `ok=true`, serial `127.0.0.1:5583`, ABI `armeabi-v7a`, Android `4.4.2`, boot `1`, with separate `getprop-abi`, `getprop-release`, `getprop-boot`, and `boot-fingerprint` stages.
- Observed: parse check passed for `work/kssma-runtime-lib.ps1`; fast-health completed in about 3.3s and did not require repair or restart.
- Conclusion: the previous 1s/2s combined getprop false `adb-transport` path is narrowed, stale post-reboot baseline cache has a cheap invalidation signal, and patch-lib verification timeouts no longer masquerade as package absence.
- Next: rerun the exploration count probe only after the login/notice harness has a proven main-menu observable; if patch-lib reports `patch-verify-timeout`, verify with `install-check` or rerun patch-lib after ADB settles instead of reinstalling blindly.

## Notice harness no-Back guard

- Frontier: `run -DriveLogin -DismissNoticeWebView` could press Android Back on a daily `/connect/web/` notice and land in the exit confirmation dialog instead of proving main-menu state.
- Hypothesis: the notice helper should treat `sceneto://2100` / main-menu evidence as the first-class success signal, then handle exit confirmation explicitly with No/cancel, never Back as the default action.
- Changed one variable: updated `C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1` only. Added exit-confirmation detection, explicit No/cancel handling, main-menu proof gating, and removed the unconditional Back press from the normal notice path.
- Server check: not run; server/protocol unchanged.
- ARM19 check: syntax-only check passed for the edited script; no runtime regression run yet.
- Observed: helper now prefers `looks_main_menu`, `sceneto://2100`, or an explicit exit-confirmation No tap before any fallback taps. The normal path no longer uses Back.
- Conclusion: the harness failure mode is narrowed. Next runtime check should prove that `-DriveLogin -DismissNoticeWebView` either lands on the main menu or returns a clear failure class when the confirmation dialog cannot be handled.
- Next: rerun the one-shot helper with the same tag family and verify the summary records `sceneto_2100_seen=True` or a direct main-menu screenshot before any exploration input.

## Exploration floor count probe classified non-empty

- Frontier: `/connect/app/exploration/floor` returns encrypted 200 but the visible UI stays on the area map instead of showing `floor_list`.
- Hypothesis: the two-branch native SIGILL probe at `librooneyj.so+0x00341A34/0x00341A36` can classify whether `_ExplorationArea::createFloorList()` sees `_ExplorationModel+0x58` floor vector count `<=0` or `>0`.
- Changed one variable: installed only `work/librooneyj-exploration-count-probe.so` with `work/kssma-runtime.ps1 patch-lib`; no server XML, resource, Java, manifest, or emulator target change. After the experiment, restored stock native from `work/million-cn-animationguard-signed.apk` and verified matching SHA-256.
- Server check: `node .\server\test-bootstrap-server.js` passed before the runtime run.
- ARM19 check:
  - `fast-health` returned `ok=true` on `127.0.0.1:5583`, Android `4.4.2`, ABI `armeabi-v7a`, boot `1`.
  - `ensure-baseline` hit the hot baseline cache without hosts/mount/display/audio/package repair.
  - The first one-shot login run reached `RooneyJActivity` but its final screenshot was `CONNECTING...`; after the one-shot server exited, the daily WebView notice loaded as a white page with an `X` close button. This proves `drive_login_status=reached-rooney` alone is not a main-menu proof.
  - With the helper server running, tapping the visible WebView `X` at `1154,28` produced a real main-menu screenshot `work/kssma-runtime-exploration-count-probe-after-notice-x.png`.
  - Cleared logcat, restarted the helper server, tapped main-menu exploration at `1090,235`, and observed `/connect/app/exploration/area` encrypted 200.
  - Tapped the area card at `760,280`, and observed `/connect/app/exploration/floor` encrypted 200 with decrypted `area_id=0`.
- Observed:
  - `work/kssma-runtime-exploration-count-probe-after-floor-requests.txt` records `/connect/app/exploration/area`, then `/connect/app/exploration/floor` with `area_id=0`.
  - `work/kssma-runtime-exploration-count-probe-after-floor-logcat.txt` records `Fatal signal 5 (???) at 0xa3471a36`, then `Process com.square_enix.million_cn ... has died`.
  - The probe at `0x00341A36` is the `count > 0` branch; the `0x00341A34` empty-vector branch was not hit.
- Conclusion: the floor list is not missing because `_ExplorationModel+0x58` is empty. The parser/model path has at least one floor entry by the time `createFloorList()` evaluates the vector. Stop pursuing empty `floor_info_list` or blind floor XML value guesses at this frontier.
- Next: statically and/or diagnostically inspect the non-empty path inside `_ExplorationArea::createFloorList()`: floor-list item construction, required `FloorInfoTagData` fields, layout/model bindings for `floor_list`, and any visibility/selection/update condition after the vector count check.

## Exploration floor UI static handoff

- Frontier: `_ExplorationArea::createFloorList()` sees nonempty `model+0x58`, but the floor list is still not visible after `/connect/app/exploration/floor` returns 200.
- Static pass: wrote `work/schema-cards/exploration-floor-ui.md`. No server, APK, runtime, or XML changes.
- Observed:
  - `createFloorList()` allocates `_AnmExplorationList`, sets inner type 6, reads optional `FloorInfoTagData+0x18` found items, then still continues through `setMinusPoint()`, `drawTextFloor()`, and pushes a `BasicComponent` into `_ExplorationArea+0x7c/+0x80`. Empty `found_item_list` is not enough to explain a missing row.
  - The vector-capacity path at `0x00341BDE -> 0x00341EF2` calls the vector insert-overflow helper and returns to cleanup, so initial empty capacity is not an early return.
  - Corrected string resolution in `preUpdate()` shows `0x003420BA` triggers `floor_list_active`, `0x003420E2` puts `f_focus`, `0x003420F6` puts `floor_list`, `0x0034214A` puts `remake=true`, and `0x00342160` triggers `floor_list_active2`.
  - `layout_exploration_area.xml` defines `floor_list` as a scene `v_list` with `auto="false"` and params `focus=f_focus`, `list=floor_list`, `remake=remake`. `floor_list_active2` and `floor_list_true` call `action floor_list remake`; `floor_list_active` only changes visibility/placeview/title and does not call remake.
- Conclusion: the current strongest hypothesis is no longer schema/value. It is UI timing: native can trigger `floor_list_active`/`floor_list_active2` before freshly-created `f_focus` and `floor_list` data are published with `putData()`. If `v_list` remake is edge-triggered, later `putData()` may leave a nonempty native list invisible.
- Next: the next real-device observable should classify the post-create `_ExplorationArea+0x7c` count and which behavior path ran (`floor_list_active` vs `floor_list_active2`). If post-create count is `>0`, test exactly one post-`putData("floor_list")` remake/trigger change. Do not return to id=1, empty vector, broad FloorInfo XML guesses, or fake found items without new evidence.
## Exploration floor four-way post-create probe

- Frontier: `/connect/app/exploration/floor` returns encrypted 200 but the visible `floor_list` is not shown.
- Hypothesis: `createFloorList()` may already produce scene list components, while the UI list stays stale because `floor_list_active`/`remake` ordering happens before `putData(floor_list)`.
- Changed one variable: patched only `librooneyj.so+0x003420DC..0x003420ED` in `work/librooneyj-exploration-postcreate-fourway-probe.so` with a four-way SIGILL classifier. No server XML, APK resources, emulator target, hosts, mount, or click coordinates were changed.
- Server check: existing `node .\server\test-bootstrap-server.js` passed before runtime; persistent helper server served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with encrypted 200 responses.
- ARM19 check: `fast-health` succeeded on `127.0.0.1:5583`; `ensure-baseline` used a fresh baseline cache; `patch-lib` verified installed SHA-256 `84502B00EF8077DB2A6838387910C6D00011383A639AAFEEBCFF375BE71644F1`. Login reached `RooneyJActivity`; then helper server was started, logcat cleared, and taps hit main menu exploration then `Local Area`. Artifacts: `work/kssma-runtime-exploration-fourway-login-*` and `work/kssma-runtime-exploration-fourway-after-click-*`.
- Observed: server log recorded `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Logcat then crashed at `Fatal signal 4 (SIGILL) at 0xa34720ea`; tombstone backtrace maps `#00 pc 003420ea /data/app-lib/com.square_enix.million_cn-2/librooneyj.so (_ExplorationArea::preUpdate()+457)`. Register state included `r3=00000008`, `r5=00000056`, and memory near `_ExplorationArea+0x7c/+0x80` showed begin/end difference `8`.
- Conclusion: after `createFloorList()`, the scene-side floor list vector is non-empty, and the natural path is `floor_list_active`, not `floor_list_active2`. The blocker is no longer schema population, floor id value, empty `floor_info_list`, or missing found-item XML. The active gap is that this path makes `floor_list` visible but does not perform a post-`putData(floor_list)` list remake/update.
- Next: test exactly one post-data refresh fix. Prefer a minimal native/layout ordering patch that triggers `floor_list_true`/`remake` after `putData(floor_list)` or otherwise forces `_PickList` to consume the already-populated scene list. Do not return to blind floor XML or state-forcing patches.
## Exploration post-data remake experiment

- Frontier: scene-side `floor_list` vector is non-empty after `createFloorList()`, but visible `floor_list` is still absent.
- Hypothesis: triggering existing `floor_list_active2` after `putData(floor_list)` may make the manual v_list consume the new list.
- Changed one variable: patched only `work/librooneyj-exploration-postdata-remake-experiment.so`: `librooneyj.so+0x0034210C 4f e7 -> 19 e0` to branch from after `putData(floor_list)` into the existing `floor_list_active2/remake` path, and `librooneyj.so+0x0034216E ad e7 -> 1e e7` so that path returns to the normal update loop instead of re-running `createFloorList()`. No server XML, APK resources, emulator target, hosts, mount, or click coordinates changed.
- Server check: `node .\server\test-bootstrap-server.js` passed; helper server later served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with encrypted 200 responses.
- ARM19 check: `fast-health` passed on `127.0.0.1:5583`; `patch-lib` verified SHA-256 `8CEDFF15D94B5403605605FCB7315D4850CB18F237140F59D3E38107F7C12863`; login reached `RooneyJActivity`; taps hit exploration and `Local Area`. Artifacts: `work/kssma-runtime-exploration-postdata-remake-login-*` and `work/kssma-runtime-exploration-postdata-remake-after-floor-*`.
- Observed: requests reached `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Top activity stayed `RooneyJActivity`; logcat showed no `Fatal signal`, `SIGILL`, `SIGSEGV`, `SIGABRT`, `JResourceLoader`, `getSDPackFile`, or `loadTexture` failure. Screenshot `work/kssma-runtime-exploration-postdata-remake-after-floor.png` still shows the area map and `Local Area`, not a visible floor list.
- Conclusion: post-data `floor_list_active2/remake` alone is not sufficient. The remaining gap is probably not the behavior trigger itself, but that the manual `v_list` still has not run `updateProperty`/`setPropertyValues`/`setRecords` against the new scene data.
- Next: instrument or patch the property-update path for `floor_list` specifically. Do not return to server XML, floor id, found items, or state-forcing patches.

## External wiki data pipeline branch

- Frontier: understand the original game systems and recover service-database candidates from external sources without disturbing the current startup/protocol mainline.
- Hypothesis: a separate zero-dependency Node pipeline can treat Fandom/atwiki/Wayback as evidence sources, cache raw wiki revisions, normalize system/card entities, and produce a database candidate report while keeping all data out of `bootstrap-server.js`.
- Changed one variable: added only external-data tooling under `work/`: `kssma-external-wiki-fetch.js`, `kssma-external-wiki-extract.js`, `kssma-external-wiki-report.js`, and generated `work/external-data-branch-20260626.md`. Generated raw/normalized/SQLite artifacts live under ignored `work/external-data/`.
- Server check: `node .\server\test-bootstrap-server.js` passed after the pipeline work; no local protocol response changed.
- External-data check:
  - `node .\work\kssma-external-wiki-fetch.js --source zh-fandom --limit 20 --refresh` produced 10 pages and 16 image refs; Fandom blocks Node fetch with Cloudflare, so the script uses a PowerShell `Invoke-WebRequest` fallback when `fetch` receives 403.
  - `node .\work\kssma-external-wiki-fetch.js --source en-fandom --limit 20 --refresh` produced 20 pages.
  - `node .\work\kssma-external-wiki-extract.js` produced 107 JSONL entities and rebuilt `work/external-data/kssma-external.sqlite` with 107 rows.
  - `node .\work\kssma-external-wiki-report.js` wrote `work/external-data-branch-20260626.md`.
- Observed: entity counts are `card=20`, `combo=20`, `skill=19`, `system_page=14`, `fairy_or_boss=4`, `source_page=30`. The English `Arbitrator Knight` sample extracts `rarity=3`, `cost=8`, `NLv1 HP=1680`, `NLv1 ATK=2450`, and illustrator `Katsumi Enami`. The Chinese `新手指南` sample extracts system rules including `AP每3分鐘回復1點`, `BC每1分鐘回復1點`, `等級上限是350級`, Gacha cost rules, and friend cap text.
- Conclusion: external wiki data is now a reproducible evidence source, not server truth. It can provide game-system summaries and value/domain candidates, but route XML fields still require native parser/schema evidence before server integration.
- Next: expand source coverage beyond the 20-page smoke sample only when a specific subsystem needs data. For server use, create a route-specific handoff that names one external entity/value, its source revision, the matching local master/native consumer, and the runtime observable to validate.

## Exploration post-data updateProperty experiments

- Frontier: `createFloorList()` produces a non-empty scene-side vector and `/connect/app/exploration/floor` returns 200, but the visible UI stays on the area map instead of switching to floor list.
- Hypothesis: after `putData("floor_list")`, forcing `_Layout::updateProperty()` or `_Layout::updateProperty(hash("floor_list"))` would make the `v_list` consume the new scene data and render records.
- Changed one variable:
  - First generated `work/librooneyj-exploration-postdata-updateproperty-experiment.so`, branching from `librooneyj.so+0x00342108` into `_Dummy::update` as a code cave. This was rejected because login crashed before any exploration request; logcat stack showed `_Dummy::update(smart_ptr<_MtTouchEvent> const&)+18`, proving `_Dummy::update` is live code and not a safe cave.
  - Reworked the same experiment into `work/librooneyj-exploration-postdata-updateproperty-rodata-cave.so`, using the zero-filled `.rodata` window at `0x003E7720` as a temporary executable cave after a simple reference scan found no direct absolute or common PC-relative refs in that 192-byte zero run. The cave loaded `LayoutScene+0x24 -> _Layout*`, called `_Layout::updateProperty()` at `0x0038E948`, restored `state=2`, and returned to `0x00341FAE`.
  - Then generated `work/librooneyj-exploration-postdata-updateproperty-floorhash.so`, using the same `.rodata` cave but recomputing `hash("floor_list")` from string `0x003E24C0` and calling `_Layout::updateProperty(hash)` at `0x0038E81C`.
- Server check: `node .\server\test-bootstrap-server.js` passed before the native runtime experiments. Helper server later served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with encrypted 200 responses and decrypted `area_id=0`.
- ARM19 check:
  - `patch-lib` installed the rodata update-all experiment and verified SHA-256 `33A62BD359161ABB49266C42559E76BCB69726667B8FF692891A5266D3FDA1D9`.
  - Login reached visible main menu under `RooneyJActivity`; no `Fatal signal`, `SIGILL`, `SIGSEGV`, `SIGABRT`, `_Dummy::update`, or `pc 003e772*` crash was observed.
  - Taps hit `/connect/app/exploration/area`, then `/connect/app/exploration/floor`; screenshot `work/kssma-runtime-exploration-postdata-updateproperty-rodata-after-floor.png` still showed the area map with `Local Area`, not a floor list.
  - `patch-lib` installed the targeted `floor_list` updateProperty experiment and verified SHA-256 `E7CD642E190388E715C573D305F599C7191C3F9DF0E00CFADBF4865B865FF73B`.
  - Login again reached visible main menu under `RooneyJActivity`; taps hit `/connect/app/exploration/area`, then `/connect/app/exploration/floor`; screenshot `work/kssma-runtime-exploration-postdata-updateproperty-floorhash-after-floor.png` still showed the area map with `Local Area`.
- Observed:
  - Using `_Dummy::update` as a cave is a proven bad patch carrier; it is executed during normal login/main-menu flow.
  - The `.rodata` zero-window cave is sufficient for temporary native-only experiments on ARM19, but it should remain an experiment carrier until a safer long-term patch carrier is validated.
  - Neither post-data `_Layout::updateProperty()` update-all nor direct `_Layout::updateProperty(hash("floor_list"))` made the visible floor list appear.
  - XML-side `remake/auto` is lower confidence: layout XML exposes only `remake` and `auto` actions for `floor_list`, and a stronger native post-data `floor_list_active2/remake` experiment already failed.
- Conclusion: the floor-list blocker is probably not just a missing layout behavior trigger or missing `_Layout::updateProperty` call after `putData("floor_list")`. The next gap is deeper: either the `floor_list` component binding does not map through the expected property path at this moment, or `_PickList::setRecords` receives an unsuitable record container/content despite the scene-side vector being non-empty.
- Next: instrument a later consumer, not another scene-trigger experiment. Classify whether `_PickList::setPropertyValues` sees a `list` property for this component, and whether `_PickList::setRecords` is called with the `floor_list` vector pointer and a positive count. Do not repeat `_Dummy::update` caves, XML `remake/auto`, post-data `floor_list_active2`, update-all, or direct `updateProperty(floor_list)` without new evidence.

## Exploration PickList consumer probes

- Frontier: `/connect/app/exploration/floor` returns 200 and `_ExplorationArea+0x7c/+0x80` holds a non-empty scene-side `floor_list`, but the visible UI remains on the area map.
- Hypothesis A: the post-data direct `_Layout::updateProperty(hash("floor_list"))` experiment failed because it never reached `_PickList::setRecords`.
- Changed one variable: generated `work/librooneyj-exploration-picklist-setrecords-probe.so` from the stock patched native. The patch used the existing `.rodata` cave at `0x003E7720`, set a scratch flag only after the `/floor` post-data point, called `_Layout::updateProperty(hash("floor_list"))`, and hooked `_PickList::setRecords` entry to SIGILL only when that flag was set. Classifier PCs were `0x003E77A4` for null records, `0x003E77A6` for empty records, and `0x003E77A2` for positive records.
- Observed A:
  - `patch-lib` installed SHA-256 `29E0C6FDA17C0F6052B24804808FE75293B3354FEC62B16EAE232EDFD0C3DBC2`.
  - Login reached `RooneyJActivity` without hitting the probe.
  - Runtime requests reached `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`.
  - Logcat hit `Fatal signal 4 (SIGILL)` at `pc 003e77a2`; backtrace was `_PickList::setPropertyValues(...)+412 -> _Layout::updateProperty(unsigned long)+238 -> 0x003e7743`.
- Conclusion A: direct post-data `_Layout::updateProperty(hash("floor_list"))` does reach `_PickList::setPropertyValues` and `_PickList::setRecords` with a positive record count. The blocker is after or inside PickList record consumption, not an absent layout property update or empty list pointer.
- Hypothesis B: `remake=true` must be present before the `floor_list` property update, so a combined post-data `putData("remake", true) -> updateProperty(hash("floor_list"))` should rebuild the visible list.
- Changed one variable:
  - First generated `work/librooneyj-exploration-remake-updateproperty-combo.so`, but it stored `remake=true` on stack. This crashed at `/floor` with `SIGSEGV` at stack address `0xbeace400`, so the experiment was rejected as a bad value-lifetime carrier.
  - Regenerated as `work/librooneyj-exploration-remake-updateproperty-combo-bss.so`, storing the bool in a `.bss` scratch address `0x00446574` before calling `LayoutScene::putData(hash("remake"), &bool)` and `_Layout::updateProperty(hash("floor_list"))`.
- Observed B:
  - `patch-lib` installed BSS version SHA-256 `78BA3CCB46B5051E52ADE2A1765B75965413AC24418D10ACD5AA19E45C8C2D61`.
  - Login reached `RooneyJActivity`.
  - A first click sequence reached only `/connect/app/exploration/area`; screenshot stayed on the area-selection map, so the area-card tap was repeated without restarting.
  - The repeated area-card tap reached `/connect/app/exploration/floor` 200 with decrypted `area_id=0`, then crashed with `SIGSEGV` at `0xbeace400` again. Activity returned to the launcher.
- Conclusion B: simply forcing `remake=true` plus `updateProperty(floor_list)` at this post-data point is not a safe fix. Even with stable bool storage, the path trips a stack/iterator lifetime fault during PickList/layout handling.
- Cleanup: restored the installed native to stock patched `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified installed SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: stop trying more scene-level `remake`/`updateProperty` combinations. Inspect `_PickList::setRecords` and the draw/update invalidation path after positive records: whether it requires a stable `BasicComponent` item shape, a separate dirty flag, a `make/remake` method on `_PickList`, or an item renderer resource binding. The next useful probe should classify the post-`setRecords` internal state or the draw path, not another server XML field or behavior trigger.

## Exploration external system logic focus

- Frontier: targeted external data is needed for the active `/connect/app/exploration/floor` blocker, where `createFloorList()` has already produced a non-empty scene-side vector but the visible `floor_list` still does not render.
- Hypothesis: cached zh Fandom pages can provide original exploration system logic and value-domain candidates for AP cost, area/floor count, rewards, factor slots, and guardians, while still keeping the current blocker focused on the later UI consumer rather than server XML guessing.
- Changed one variable: added `work/kssma-external-exploration-focus.js`, which reads only cached `zh-fandom` raw revisions for `探索` and `新手指南`, parses the exploration region/floor tables, writes ignored normalized data to `work/external-data/normalized/exploration-focus.json`, and writes the tracked handoff `work/exploration-external-system-logic-20260626.md`. No server, runtime, APK, native, or XML response change.
- Observed:
  - Source revisions are `探索` pageid `117`, revid `7930`, timestamp `2013-08-25T08:56:49Z`, and `新手指南` pageid `110`, revid `14604`, timestamp `2014-04-22T12:45:47Z`.
  - The external exploration system is region -> area/floor -> walking progress -> 100% -> next area/floor, with each move consuming AP and producing EXP/Gold plus at most one side event such as AP/BC recovery, fairy encounter, card, factor fragment, other-player encounter, or no event.
  - The cached `探索` table parses into 6 regions and 70 area/floor rows: `人魚の断崖` 6, `燐光の湖` 9, `錯乱の平原` 10, `叡智の草原` 10, `猛獣の砂丘` 15, `祝福を授ける山` 20. AP cost candidates are `1..6`; region image refs are `File:area1.jpg` through `File:area6.jpg`; each row has three item/factor slots.
  - `新手指南` cross-checks AP recovery as 1 per 3 minutes, BC recovery as 1 per 1 minute, and card inventory cap 350 blocking exploration/gacha.
- Conclusion: external data supports `floor_info.cost` as AP cost, `progress` as walking progress, `found_item_list` as row reward/icon or later reward-pool data, and `boss_id` as guardian/clear logic. It does not explain the current invisible `floor_list`, because native/runtime evidence already proved non-empty model and scene vectors.
- Next: keep server XML stable. The next useful observable is still `_PickList::setPropertyValues` and `_PickList::setRecords`: prove whether the manual `v_list` receives the `list=floor_list` binding and positive records. Do not expand area data, fake found items, sweep costs, or use guardian/boss values before that consumer is classified.

## Exploration PickList setRecords branch classification

- Frontier: `/connect/app/exploration/floor` returns 200 and direct post-data `_Layout::updateProperty(hash("floor_list"))` reaches `_PickList::setRecords` with positive records, but the floor list is still not visible.
- Hypothesis: direct `updateProperty(floor_list)` failed because `_PickList::setRecords` hit its early-return path before copying records, rebuilding buttons, creating buffers, or creating the vertical list.
- Changed one variable: generated temporary native-only probe `work/librooneyj-exploration-setrecords-branch-probe.so` from the stock native. The patch set a scratch flag only after the `/floor` post-data point, then classified `_PickList::setRecords`: `0x003E7782` meant early return at `0x002D2DBE`; `0x003E77AA` meant the rebuild path reached past `createOffImage(10)` / `createVerticalList`.
- Server check: `node .\server\test-bootstrap-server.js` passed before the runtime experiment.
- ARM19 check:
  - `fast-health` passed on `127.0.0.1:5583` with ABI `armeabi-v7a`, Android `4.4.2`, and `sys.boot_completed=1`.
  - `patch-lib` installed the probe and verified SHA-256 `9B4228681AD4C85D040A0250319C48F0B9E6F7E209B64F4F154AFF0DCCF70A5F`.
  - `run -DriveLogin -Observe Requests,Activity,Logcat,Screenshot` reached the visible main menu under `RooneyJActivity`; the helper reported a known notice-WebView XML-selection failure, but the screenshot confirmed the menu was already usable.
  - Manual taps reached `/connect/app/exploration/area` 200, then `/connect/app/exploration/floor` 200 with decrypted `area_id=0`.
- Observed: after `/floor`, logcat hit `Fatal signal 5` at `0xa34d87aa`, which maps to probe PC `0x003E77AA`. This is the post-rebuild classifier, not the early-return classifier.
- Conclusion: for the direct post-data `updateProperty(floor_list)` path, `_PickList::setRecords` does not early-return. It reaches the rebuild path after `createOffImage` / `createVerticalList`. The explicit `remake` / `+0x7d` theory is therefore not the current blocker for this path.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: inspect the post-rebuild draw/update state instead of changing server XML or forcing `remake`. Useful next probes are `_PickList+0xAC` records, `+0x94` buttons, `+0xA0` buffers, `+0x7E` vertical-list init, `+0x08` visibility, `+0xB8` draw mode, then `_PickList::draw`, `_PickList::drawRecord`, and `_AnmExplorationList::draw`.
- Do not repeat: server field sweeps for `floor_info`, found-item/cost/boss guessing, direct updateProperty early-return probes, or scene-level `putData("remake")` experiments without a new observable.

## Exploration floor_list XML attribute separator experiment

- Frontier: `/connect/app/exploration/floor` returns 200, native scene-side `floor_list` is non-empty, and direct post-data `updateProperty(floor_list)` can reach `_PickList::setRecords`, but the visible UI remains on the area map.
- Hypothesis: `layout_exploration_area.xml` has a malformed floor-list tag, `<v_list type="avairable"name="floor_list" ...>`, so the component or its `name` may not be bound correctly. Adding the missing space may let existing `visible/action target="floor_list"` behavior address the list.
- Changed one variable: added an opt-in `KSSMA_FIX_EXPLORATION_FLOOR_LIST_XML=1` path to `work/build-animation-nullguard.py` and built `work/million-cn-exploration-floorlist-xmlfix-signed.apk`, changing only the asset marker to `<v_list type="avairable" name="floor_list" ...>`. No server XML or native probe was changed for this experiment.
- Static check:
  - The malformed tag is present in both extracted apktool and jadx resources.
  - The original base APK `assets/bundle/layout_exploration_area.xml` has the same malformed line, so this is not a local apktool edit regression.
  - Standard XML parsers reject the file at line 44, column 26, but the game has its own layout loader and can still render the area screen, so parser strictness alone is not proof.
- Server check: `node .\server\test-bootstrap-server.js` passed after the build-script change.
- ARM19 check:
  - `fast-health` passed on `127.0.0.1:5583`.
  - Full `install-apk` hit the known Android 4.4 long install timeout, but `pm path` later showed `/data/app/com.square_enix.million_cn-1.apk`, activity `baseDir` used that path, and the installed APK byte size matched `work/million-cn-exploration-floorlist-xmlfix-signed.apk` at `304645957` bytes.
  - Login reached a visible main menu. Manual taps hit exploration and `Local Area`.
- Observed: server log reached `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Logcat had no `Fatal signal`, `SIGILL`, `SIGSEGV`, `SIGABRT`, `JResourceLoader`, `getSDPackFile`, or `loadTexture` failure. Screenshot `work/kssma-runtime-exploration-floorlist-xmlfix-after-floor-retry.png` still shows the area map with `Local Area`, not a floor list.
- Conclusion: fixing only the missing XML attribute separator is not sufficient. The malformed tag remains a plausible contributor to target visibility/action binding, but the floor-list blocker also needs a post-`putData(floor_list)` refresh or a deeper draw/update fix.
- Next: while the XML-fix APK is installed, test exactly one native-only post-data `updateProperty(hash("floor_list"))` patch. This combines two previously isolated partial hypotheses without changing server XML: target binding may now work, and the list may finally consume the already-created records.
- Do not repeat: XML-fix-only APK install unless testing a clean baseline regression; it has already failed to make the floor list visible.

## Exploration XML-fix plus post-data updateProperty experiment

- Frontier: XML-fix-only failed, while the earlier post-data `updateProperty(hash("floor_list"))` path proved that `_PickList::setRecords` can receive positive records.
- Hypothesis: the malformed `floor_list` XML target binding and the missing post-data refresh were two halves of the same failure; with the XML-fix APK installed, the same native post-data `updateProperty(hash("floor_list"))` should finally make the floor list visible.
- Changed one variable: installed only native patch `work/librooneyj-exploration-postdata-updateproperty-floorhash.so` on top of the already-installed XML-fix APK. No server XML, click coordinates, emulator target, or resource file changed during this experiment.
- Server check: `node .\server\test-bootstrap-server.js` had passed after the XML-fix build; the server response code was unchanged for the combined check.
- ARM19 check: `patch-lib` verified SHA-256 `E7CD642E190388E715C573D305F599C7191C3F9DF0E00CFADBF4865B865FF73B`. Login reached a visible main menu under `RooneyJActivity`; manual taps hit exploration and `Local Area`.
- Observed: server requests reached `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Screenshot `work/kssma-runtime-exploration-xmlfix-updateproperty-after-floor.png` still shows the area map with `Local Area`, not a floor list. Logcat showed no `Fatal signal`, `SIGILL`, `SIGSEGV`, `SIGABRT`, `JResourceLoader`, `getSDPackFile`, or `loadTexture` failure; the only notable noise was the known APN permission warning.
- Conclusion: XML target cleanup plus direct post-data `updateProperty(floor_list)` is still insufficient. The remaining blocker is after `setRecords` rebuild or outside the target component draw traversal, not server floor XML and not just the malformed attribute separator.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`. The XML-fix resource APK remains installed.
- Next: build a native-only draw-chain classifier. First prove whether the rebuilt floor-list item renderer is reached at all, preferably through `_AnmExplorationList::draw*`; if it is not reached, classify whether the exact `_PickList` rebuilt by `setRecords` is ever drawn.
- Do not repeat: XML-only install, XML plus direct updateProperty, server `floor_info` field sweeps, found-item guesses, AP/cost/boss value guesses, or scene-level `remake` forcing without a new draw-path observable.

## Exploration target PickList draw-entry classification

- Frontier: direct post-data `updateProperty(hash("floor_list"))` reaches `_PickList::setRecords` with positive records and reaches the rebuild path, but the visible floor list still does not appear.
- Hypothesis: the rebuilt floor-list `_PickList` might not be part of the layout draw traversal at all; if so, later work should inspect visibility/component binding instead of row renderer state.
- Changed one variable: generated temporary native-only probe `work/librooneyj-exploration-picklist-draw-entry-probe.so`. The patch reused the proven post-`/floor` path to set a scratch flag and call `_Layout::updateProperty(hash("floor_list"))`, stored the exact `_PickList*` at `setRecords` post-rebuild point `0x002D2ED8` (`r8 == this`), and hooked `_PickList::draw` entry `0x002D20A8` to SIGILL only when `r0` equals that saved pointer. No server XML, APK resource, emulator target, or click coordinate changed.
- Server check: `node .\server\test-bootstrap-server.js` passed before runtime; helper server later served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with encrypted 200 responses.
- ARM19 check:
  - `fast-health` passed on `127.0.0.1:5583`, though elapsed time was still above the desired sub-second target.
  - `patch-lib` installed the probe and verified SHA-256 `9E2C0449CBFA45895B2C7641CFB468F93AEF003708AD34ABBDB1A1BB359C0C67`.
  - Login reached a visible main menu under `RooneyJActivity`. The known notice WebView XML-selection bug occurred in the helper, but screenshot `work/kssma-runtime-exploration-picklist-draw-entry-login.png` showed the main menu was usable.
  - Manual taps reached exploration and `Local Area`.
- Observed: requests reached `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`. Logcat hit `Fatal signal 4 (SIGILL)` at `pc 003e778a`, the probe's target `_PickList::draw` classifier. Backtrace included `_Composite::draw -> _Layout::draw -> LayoutScene::drawLayout -> _ExplorationArea::render`, proving the saved floor-list PickList is in the draw traversal.
- Conclusion: the blocker is not that the rebuilt target PickList is absent from layout drawing. The next gap is inside `_PickList::draw` / `_PickList::drawRecord`: possible classifiers are `+0x7e` init flag, `+0x94` button vector count, `+0xb8` draw mode, record-loop entry, and item renderer/vtable `+0xa0`.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`. The XML-fix resource APK remains installed.
- Next: build one native-only field classifier at `_PickList::draw` entry for the saved target. It should distinguish `+0x7e == 0`, `+0x94 count == 0`, `+0xb8` not in drawable mode, and "record loop should be reachable"; only after the last case should work move to `_PickList::drawRecord` or `_AnmExplorationList::draw`.
- Do not repeat: target draw-entry-only probe, server XML field sweeps, XML-fix plus updateProperty, or scene-level remake/updateProperty combinations without a more specific draw-state observable.

## Exploration target PickList draw-state classification

- Frontier: the saved floor-list `_PickList*` is in `_Composite::draw -> _Layout::draw -> _ExplorationArea::render`, but the visible floor list still does not appear.
- Hypothesis: `_PickList::draw` might be called for the target object but immediately fail because `+0x7e` is not initialized or the `+0x94` button vector is empty.
- Changed one variable: generated temporary native-only probe `work/librooneyj-exploration-picklist-draw-state-probe.so`. It kept the same post-`/floor` `updateProperty(hash("floor_list"))` and saved target `_PickList*`, then hooked `_PickList::draw` only for that object. Classifier PCs were `0x003E77AC` for `+0x7e == 0`, `0x003E77AE` for `+0x94` button count `0`, and `0x003E77AA` for both checks passing.
- Server check: helper server served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with encrypted 200 responses; decrypted floor request was `area_id=0`.
- ARM19 check:
  - `patch-lib` installed the probe and verified SHA-256 `4E49DF38371EBDCA0836AFFA62CE6E387E28AA3BD858BE31C292383BA6E465DD`.
  - Login reached visible main menu under `RooneyJActivity`. The known notice WebView helper XML-selection bug recurred, but screenshot `work/kssma-runtime-exploration-picklist-draw-state-login.png` showed the menu was usable.
  - Manual taps reached exploration and `Local Area`.
- Observed: after `/connect/app/exploration/floor` 200, logcat hit `Fatal signal 4 (SIGILL)` at `pc 003e77aa`. Backtrace again included `_Composite::draw -> _Layout::draw -> LayoutScene::drawLayout -> _ExplorationArea::render`.
- Conclusion: for the rebuilt target floor-list PickList, `_PickList::draw` sees `+0x7e != 0` and a non-empty `+0x94` button vector. The visible-list failure is not missing PickList initialization and not missing button creation. The next frontier is deeper in the record rendering path: `_PickList::drawRecord`, `+0xb8` draw mode, `drawBuffer()`, or `_AnmExplorationList::draw(graphics,x,y,bool)` through vtable `+0x9c`.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`. The XML-fix resource APK remains installed.
- Next: use static evidence from `_PickList::drawRecord` and `_PickList::drawBuffer` before another runtime run. The most useful probe should distinguish whether target `drawRecord` enters drawable mode (`+0xb8 == 2`) and whether row content reaches `_AnmExplorationList::draw(graphics,x,y,bool)` via vtable `+0x9c`.
- Do not repeat: draw-entry or `+0x7e/+0x94` probes; both are now proven good for the target object.

## Exploration drawBuffer probe rejected due to register clobber

- Frontier: the saved floor-list `_PickList*` reaches `_PickList::draw`, has `+0x7e != 0`, and has a non-empty `+0x94` button vector; the next unknown is whether target row buffering/rendering reaches `_PickList::drawBuffer`.
- Hypothesis: hooking `_PickList::drawBuffer(int, vector<BufferImage>&)` at `0x002D2210` and trapping only when `r0` equals the saved floor-list `_PickList*` can classify whether the target list reaches offscreen row buffer generation.
- Changed one variable: generated and installed temporary native-only probe `work/librooneyj-exploration-picklist-drawbuffer-probe.so`, SHA-256 `3CE2BDDFFAF5A7CA25D1267421A515FB1F0CA33895AB8F057A95527E49AAED2F`. The probe reused the proven post-`/floor` target-save path, but its `drawBuffer` hook reused `r2` as a scratch register before replaying the original prologue.
- Server check: unchanged server XML; the helper server recorded only `/connect/app/exploration/area` 200 for this run.
- ARM19 check: the installed native has since been restored to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Observed: before `/connect/app/exploration/floor` was requested, the client crashed with `SIGSEGV` at `pc 002d222e`, backtrace `_PickList::drawBuffer(int, vector<_PickList::BufferImage>&)+29 -> _PickList::createBuffers()+136 -> _PickList::task()+500`. The fault address was `0x00000004`.
- Conclusion: reject this probe as invalid product evidence. `r2` is the live buffer-vector argument at `drawBuffer` entry; clobbering it made unrelated area-screen `_PickList::drawBuffer` calls crash before the floor-list observable.
- Next: build a corrected drawBuffer classifier that preserves `r0/r1/r2/r3` for non-target calls before replaying the original prologue. Do not infer anything about floor-list visibility, floor XML, or row renderer state from this bad crash.

## Exploration target PickList drawBuffer reached

- Frontier: the saved floor-list `_PickList*` reaches `_PickList::draw`, has `+0x7e != 0`, has a non-empty `+0x94` button vector, and still does not visibly replace the area map with the floor list.
- Hypothesis: the target floor-list PickList may still fail before row-buffer generation; a corrected `_PickList::drawBuffer` classifier can prove whether the exact saved PickList reaches offscreen buffer creation without corrupting non-target list calls.
- Changed one variable: generated and installed temporary native-only probe `work/librooneyj-exploration-picklist-drawbuffer-preserve-probe.so`, SHA-256 `22D6D413F42B09AF84E428FB0FC016AB44E40641C19D884086DFC388090AD79D`. It reused the proven post-`/floor` target-save path, hooked `_PickList::drawBuffer` at `0x002D2210`, preserved `r2/r3` before scratch loads, and trapped only when `r0` matched the saved floor-list PickList.
- Server check: `node .\server\test-bootstrap-server.js` passed before this probe sequence. During runtime, helper server served `/connect/app/exploration/area` 200 and `/connect/app/exploration/floor` 200 with decrypted `area_id=0`.
- ARM19 check:
  - An intermediate `patch-lib` attempt exposed a runtime-control failure: `127.0.0.1:5583` disappeared while the classic ARM process still listened on ports, `[::1]:5583` showed offline, and `repair-adb` hung for more than 80s without JSON. A guarded `restart-runtime -Force -Reason "ADB transport stuck..."` restored primary serial; this is runtime-control evidence, not exploration evidence.
  - After restart, `fast-health` passed on `127.0.0.1:5583`, `ensure-baseline` repaired hosts/mount and verified display/audio/package, and `patch-lib` installed the preserve probe with matching SHA-256.
  - Login reached a visible main menu under `RooneyJActivity`; the known notice WebView XML-selection bug appeared in the helper but the screenshot showed the main menu was usable.
  - Manual taps hit exploration then `Local Area`.
- Observed:
  - Requests artifact `work/kssma-runtime-exploration-picklist-drawbuffer-preserve-after-floor-requests.txt` records `/connect/app/exploration/area` then `/connect/app/exploration/floor`.
  - Logcat artifact `work/kssma-runtime-exploration-picklist-drawbuffer-preserve-after-floor-logcat.txt` records `Fatal signal 4 (SIGILL)` at `pc 003e7798`.
  - Backtrace maps `#00 pc 003e7798` to the corrected probe, then `#01 _PickList::createBuffers()+136`, `#02 _PickList::task()+500`, and `#03 _PickList::setRecords(...)+360`.
- Conclusion: the target floor-list PickList does reach `_PickList::createBuffers()` and calls `_PickList::drawBuffer()` during `setRecords`. The blocker is no longer missing layout draw traversal, missing PickList initialization, missing button creation, or failure to enter row-buffer generation.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`. The XML-fix resource APK remains installed.
- Next: inspect row content rendering inside `_PickList::drawBuffer`, especially the vtable `+0x9c` calls around `0x002D2288/0x002D2292` and `0x002D22E4`, and `_AnmExplorationList::draw(graphics,x,y,bool)` at `0x0022F5E0`. The next useful probe should classify whether the actual `_AnmExplorationList` renderer is called and whether it exits early or draws fully; do not repeat PickList entry, `+0x7e/+0x94`, or drawBuffer-entry probes.

## Exploration AnmExplorationList draw-entry reached

- Frontier: the saved floor-list `_PickList*` reaches `_PickList::drawBuffer()`, but the visible UI still stays on the area map instead of showing floor rows.
- Hypothesis: `_PickList::drawBuffer()` may call the row renderer vtable slot `+0x9c`, specifically `_AnmExplorationList::draw(graphics,x,y,bool)` at `0x0022F5E0`, after `/connect/app/exploration/floor`.
- Changed one variable: generated and installed temporary native-only probe `work/librooneyj-exploration-anm-draw-entry-only-probe.so`, SHA-256 `2C773BAC470FCD1EE150EC72F3AE69DEBD18B2D617F336C50DC31F0A231FE5E1`. It reused the proven post-`/floor` flag, post-data `_Layout::updateProperty(hash("floor_list"))`, and target-save path, but changed only the `_AnmExplorationList::draw` entry cave to SIGILL when the post-`/floor` flag is set. Server XML, APK resources, emulator target, and click coordinates were unchanged.
- Server check: `node .\server\test-bootstrap-server.js` passed before the runtime experiment. During runtime, `work/kssma-server.ps1` served both `/connect/app/exploration/area` and `/connect/app/exploration/floor`; decrypted floor request was `area_id=0`.
- ARM19 check: `fast-health` and `ensure-baseline` passed on `127.0.0.1:5583`; `patch-lib` verified the probe hash. Login reached a visible main menu under `RooneyJActivity`; the one-shot run stopped its own helper server afterward, so a persistent helper server was restarted before manual exploration taps.
- Observed:
  - `work/kssma-runtime-exploration-anm-draw-entry-after-floor-requests.txt` records `/connect/app/exploration/area` followed by `/connect/app/exploration/floor`.
  - `work/kssma-runtime-exploration-anm-draw-entry-after-floor-logcat.txt` records `Fatal signal 4 (SIGILL)` at `pc 003e7798`.
  - Backtrace maps `#00 pc 003e7798` to the probe, then `#01 pc 002d2293 _PickList::drawBuffer(...)+130`, `#02 _PickList::createBuffers()+136`, `#03 _PickList::task()+500`, and `#04 _PickList::setRecords(...)+360`.
- Conclusion: the actual floor-list row renderer is reached from `_PickList::drawBuffer()` during row-buffer creation. The blocker is now inside `_AnmExplorationList::draw` / its helper calls, or after row-buffer generation during composition, not an absent row renderer call.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: statically inspect `_AnmExplorationList::draw`, `sub_22f584`, and `sub_22f060`. The next probe should classify whether the renderer has valid internal animation/resource fields (`+0x28`, `+0x34`, `+0x38`, `+0x40`, selected `+0x48/+0x4c`) and whether `sub_22f060` reaches its final draw call.
- Do not repeat: PickList entry, draw-state, drawBuffer-entry, or row-renderer-entry probes; all are now proven for the target path.

## Exploration target PickList drawRecord high-y cull

- Frontier: the saved floor-list `_PickList*` reaches `_PickList::drawBuffer()` and `_AnmExplorationList::draw()` during row-buffer creation, but the visible UI still stays on the area map instead of showing floor rows.
- Hypothesis: final screen composition may still reject the target row inside `_PickList::drawRecord()` even after row buffers and row renderer are valid.
- Changed one variable: generated and installed temporary native-only probe `work/librooneyj-exploration-drawrecord-entry-classifier.so`, SHA-256 `1D41240F56962E69DAD181E615898938DDCA1D309F067054D6685CB1A348E615`. It reused the proven post-`/floor` flag, post-data `_Layout::updateProperty(hash("floor_list"))`, and target-save path, but changed only `_PickList::drawRecord` entry classification. Server XML, APK resources, emulator target, and click coordinates were unchanged.
- Server check: helper server served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with encrypted 200 responses; decrypted floor request was `area_id=0`.
- ARM19 check: login reached visible main menu under `RooneyJActivity`; manual taps reached exploration and `Local Area`. The ADB input shell command timed out after the taps, but the server log and observe artifacts prove both exploration routes were handled.
- Observed:
  - `work/kssma-runtime-exploration-drawrecord-entry-after-timeout-logcat.txt` records `Fatal signal 4 (SIGILL)` at `pc 003e7ed2`.
  - Backtrace maps the trap to `_PickList::draw(smart_ptr<IMtGraphics>&)+216`, then the saved target draw path.
  - The classifier maps `0x003e7ed2` to the high-Y cull branch in `_PickList::drawRecord`: mode was `2`, the low-Y cull passed, `+0xa0` buffer count was non-empty, `+0xac` record index was in range, and the record pointer was non-null.
  - Crash registers showed `r2=0x178` and `r3=0x1f4`, matching `y=500` greater than the visible threshold `0x178` (`376`).
- Conclusion: the target floor-list is created, receives records, creates buffers, calls the row renderer, and enters final draw, but the first target row is culled below the visible window. The blocker is now list geometry/scroll/placement or stale PickList state, not server floor XML, not missing row renderer, and not missing records.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: statically derive `_PickList::draw`'s y formula and the meaning of fields `+0x30`, `+0x34`, `+0x54`, `+0x5c`, `+0x60`, `+0x64`, `+0x68`, `+0x84`, `+0x88`, `+0x94`, `+0xa0`, `+0xac`, and `+0xb8`. The next runtime probe should classify why `drawRecord` receives `y=500` when the layout declares `center_top=85`, `item_left=205`, `width=200`, `height=57`, `reverse=true`, `auto=false`, and `sclip=true`.
- Do not repeat: server `floor_info` field sweeps, XML-only install, post-data updateProperty/remake probes, PickList draw entry/state/drawBuffer probes, or `_AnmExplorationList::draw` entry probes.

## Exploration natural drawRecord high-y cull

- Frontier: determine whether the `drawRecord y=500` high-Y cull is a product-path problem or an artifact caused by the earlier forced post-data `_Layout::updateProperty(hash("floor_list"))` diagnostic path.
- Hypothesis: if the earlier high-Y cull was only caused by forced `updateProperty`, then removing that call and letting the natural `/exploration/floor` flow run should avoid the same target `_PickList::drawRecord` trap.
- Changed one variable: generated `work/librooneyj-exploration-natural-drawrecord-classifier.so`, SHA-256 `6462E213890F4F84ED361BB249A05E546FA7238136F9158BED5C006B74D21946`, by taking the previous drawRecord classifier and NOPing only the cave block that called `_Layout::updateProperty(hash("floor_list"))`. The patch still set the post-`/floor` flag, saved the next `_PickList*` at the proven `setRecords` post-rebuild point, and classified `_PickList::drawRecord`. No server XML, APK resources, emulator target, or click coordinates changed.
- Server check: `node .\server\test-bootstrap-server.js` passed before runtime. During runtime, helper server recorded `/connect/app/exploration/area` and `/connect/app/exploration/floor` with encrypted 200 responses; decrypted floor request was `area_id=0`.
- ARM19 check: `fast-health` and `ensure-baseline` passed on `127.0.0.1:5583`; `patch-lib` verified the diagnostic native hash. Login reached visible main menu under `RooneyJActivity`. Manual taps hit exploration and `Local Area`. Artifacts: `work/kssma-runtime-exploration-natural-drawrecord-login-*` and `work/kssma-runtime-exploration-natural-drawrecord-after-floor-*`.
- Observed: `work/kssma-runtime-exploration-natural-drawrecord-after-floor-logcat.txt` records `Fatal signal 4 (SIGILL)` at `pc 003e7ed2`. Registers again showed `r2=0x178` and `r3=0x1f4`, matching the high-Y cull case.
- Conclusion: the high-Y cull is not merely a forced `updateProperty` artifact. The natural `/exploration/floor` path also reaches a target PickList drawRecord state where final row y is 500 and is culled below the visible window.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: do not repeat the forced-vs-natural distinction. The remaining question is why the product path leaves the target list at stale/incorrect visual state, and whether the saved PickList is definitively `floor_list` rather than `area_list`.

## Exploration zero +0x84 visual probe failed

- Frontier: test whether the high-Y cull alone is sufficient to explain the missing visible floor list.
- Hypothesis: if the only remaining blocker is the target PickList entrance offset `+0x84=500`, then clearing `+0x84` to `0` immediately after natural post-`/floor` `setRecords` should make the floor list visible.
- Changed one variable: generated `work/librooneyj-exploration-natural-zero84-visual.so`, SHA-256 `5D8D49C3CBB77DDA1F29554AD72332A00FA62E1271AB4658C142CC240BA3F31F`. It set the post-`/floor` flag without forced `updateProperty`, hooked the proven `setRecords` post-rebuild point, saved `r8` as the target PickList, and wrote `target+0x84 = 0`. It did not hook `drawRecord`, did not SIGILL intentionally, and did not change server XML/resources/emulator/click coordinates.
- Server check: unchanged server XML; requests artifact `work/kssma-runtime-exploration-zero84-visual-after-floor-requests.txt` records `/connect/app/exploration/area` and `/connect/app/exploration/floor` with decrypted `area_id=0`.
- ARM19 check: `patch-lib` verified SHA-256 `5D8D49C3CBB77DDA1F29554AD72332A00FA62E1271AB4658C142CC240BA3F31F`. Login reached visible main menu; manual taps reached exploration and `Local Area`. Activity stayed `RooneyJActivity`; logcat had no `Fatal signal`, `SIGILL`, `SIGSEGV`, `SIGABRT`, `JResourceLoader`, `getSDPackFile`, or `loadTexture` failure.
- Observed: screenshot `work/kssma-runtime-exploration-zero84-visual-after-floor.png` still shows the area-selection map with `Local Area`, not a visible floor list.
- Conclusion: clearing `+0x84` after the saved `setRecords` point is not sufficient. Either the saved object is not yet proven to be the visible `floor_list` component, or the blocker also includes higher-level `setPropertyValues`/visibility/data-binding state. Do not treat high-Y as the sole root cause.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: inspect `_PickList::setPropertyValues`, `_PickList::action`, `_Layout::updateProperty`, and `LayoutScene::putData` to prove how `list`, `focus`, and `remake` are consumed, and to classify whether the captured PickList is definitively `floor_list`.

## Exploration forced floor-list zero +0x84 visual probe failed

- Frontier: test whether high-Y cull is sufficient on the stronger `updateProperty(hash("floor_list"))` target, whose identity is backed by XML data-key binding rather than the natural first `setRecords` capture.
- Hypothesis: if the confirmed `floor_list` target is hidden only because `_PickList+0x84` remains `500`, then forcing `updateProperty(hash("floor_list"))` and clearing that target's `+0x84` should make the floor list visible.
- Changed one variable: generated and installed `work/librooneyj-exploration-forced-update-zero84-visual.so`, SHA-256 `C2AD824D91D81E6B6F52D33C9960FFACA926BF55D0E27139C36410974BCF4EBE`. It kept the earlier forced post-data `_Layout::updateProperty(hash("floor_list"))`, restored `_PickList::drawRecord` to stock, saved the forced `setRecords` target, and wrote `target+0x84 = 0`. Server XML, APK resources, emulator target, and click coordinates were unchanged.
- Server check: `node .\server\test-bootstrap-server.js` passed before runtime.
- ARM19 check: `fast-health` and `ensure-baseline` passed on `127.0.0.1:5583`; `patch-lib` verified the probe hash. Login reached `RooneyJActivity`; helper server was restarted after the one-shot login harness stopped its own server. Manual taps reached exploration and `Local Area`.
- Observed: `work/kssma-runtime-exploration-forced-zero84-after-floor-requests.txt` records `/connect/app/exploration/area` and `/connect/app/exploration/floor` with decrypted `area_id=0`. `work/kssma-runtime-exploration-forced-zero84-after-floor-logcat.txt` has no fatal signal and no resource/texture miss. Screenshot `work/kssma-runtime-exploration-forced-zero84-after-floor.png` still shows the area-selection map with `Local Area`, not the floor list.
- Conclusion: clearing `+0x84` is not sufficient even on the stronger forced `floor_list` update path. The missing floor-list screen is not explained by high-Y cull alone; the next proof must classify component identity and higher-level `setPropertyValues`/action/visibility state before another visual patch.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: build a runtime identity classifier. Save `_ExplorationArea*` at the floor path, then hook `_PickList::setRecords` and compare its `records` argument with saved `this+0x7c` (`floor_list`) and `this+0x70` (`area_list`). Do not continue patching `+0x84` until that identity is proven.

## Exploration floor_list setRecords identity proven

- Frontier: prove whether the traced `_PickList::setRecords` target after `/connect/app/exploration/floor` is really the scene-side `floor_list`, not an area-list or unrelated v_list.
- Hypothesis: after the floor response path saves `_ExplorationArea*`, a floor-only classifier that traps only when `_PickList::setRecords(records)` receives `records == saved_ExplorationArea + 0x7c` should identify the true `floor_list` consumer without crashing earlier area-stage list updates.
- Changed one variable: generated and installed `work/librooneyj-exploration-setrecords-flooronly-classifier.so`, SHA-256 `22E7FF18CCF91592E8BD836E2C3590AA72D74F2800379B7EB0B0AFB1FCFE97A3`. It used `0x004493AC` as BSS scratch, saved `_ExplorationArea*` in the floor path, and hooked `_PickList::setRecords` to replay normally unless `records == saved + 0x7c`, where it executed `udf #1` at `pc 0x003e777c`. Earlier identity classifier attempts using an absolute file offset or `.text` scratch were rejected as probe bugs, and the first valid broad classifier trapped an area-stage unknown before `/exploration/floor`, so it was not floor evidence.
- Server check: `node .\server\test-bootstrap-server.js` passed. During runtime, `work/kssma-runtime-exploration-setrecords-flooronly-after-floor-requests.txt` recorded `/connect/app/exploration/area` followed by `/connect/app/exploration/floor`; decrypted floor request was `area_id=0`.
- ARM19 check: `fast-health` passed on `127.0.0.1:5583`; `patch-lib` verified the floor-only probe hash. Login reached `RooneyJActivity`; helper server was restarted after the one-shot login harness; manual taps hit exploration and area.
- Observed: `work/kssma-runtime-exploration-setrecords-flooronly-after-floor-logcat.txt` recorded `Fatal signal 5` at `0xa34d577c`, which maps to `librooneyj.so+0x003e777c`, the probe's only `floor_list` identity trap.
- Conclusion: the target consumed by `_PickList::setRecords` is definitively the scene-side `_ExplorationArea+0x7c` `floor_list`. The remaining blocker is after positive `floor_list` records reach the PickList: draw geometry, visibility/action state, or final composition, not server floor XML and not wrong list identity.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: statically derive `_PickList::draw` / `_PickList::drawRecord` y-position and visibility state, especially fields `+0x30`, `+0x34`, `+0x54`, `+0x5c`, `+0x60`, `+0x64`, `+0x68`, `+0x84`, `+0x88`, `+0x94`, `+0xa0`, `+0xac`, and `+0xb8`. Do not repeat identity probes, server XML sweeps, post-data `updateProperty`, or `+0x84`-only visual patches without new field evidence.

## Exploration floor_list y-source classified

- Frontier: the true scene-side `floor_list` PickList reaches final `_PickList::drawRecord()`, but the first row is culled because final `y=500`.
- Hypothesis: final `drawRecord` y may come from the PickList entrance offset `_PickList+0x84`, or from the row/button object's own y-coordinate. If `_PickList+0x84` is 500 at the moment of final draw, the remaining fix point is the action/property path that writes this offset, not server data or row item construction.
- Changed one variable: generated and installed `work/librooneyj-exploration-y-source-probe.so`, SHA-256 `9C7034613E5A9B7EE150B194C4F5418BEC258F13AFCF520A23AC84972D15B8C9`. It reused the proven natural post-`/floor` flag and post-rebuild PickList save, then hooked only `_PickList::drawRecord` for the saved target. Classifier PCs were `0x003e7e94` for `_PickList+0x84 == 0`, `0x003e7e96` for `_PickList+0x84 == 500`, `0x003e7e98` for `final_y == +0x84`, and `0x003e7e9a` for other mixed geometry.
- Server check: `node .\server\test-bootstrap-server.js` passed. Runtime requests artifact `work/kssma-runtime-exploration-y-source-after-floor-requests.txt` recorded `/connect/app/exploration/area` then `/connect/app/exploration/floor`; decrypted floor request was `area_id=0`.
- ARM19 check: `fast-health` passed on `127.0.0.1:5583`; `patch-lib` verified the y-source probe hash. Login reached `RooneyJActivity`; helper server was restarted after the login harness; manual taps reached exploration and area.
- Observed: `work/kssma-runtime-exploration-y-source-after-floor-logcat.txt` recorded `Fatal signal 4 (SIGILL)` at `pc 003e7e96`. Registers included `r2=000001f4` and `r3=000001f4`.
- Conclusion: at final draw, the saved true `floor_list` PickList has `_PickList+0x84 == 500`, and that is the y-offset causing the row to be culled. The row renderer, records, buffers, and list identity are valid. The next fix should prevent or undo the `+0x84=500` action/property state for this path; do not return to floor XML, row values, or row renderer probes.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next: statically and diagnostically classify which `_PickList::action` command writes `+0x84=500` for `floor_list`. Candidate stock path is `_PickList::action` at `0x002d332c..0x002d3336`, which stores `500` to `+0x84` and `0` to `+0x54` after matching a command such as `remake`/`moving`. A useful visual fix should target that writer or immediately after it, not `setRecords` post-rebuild where a later action can restore the 500 offset.

## Exploration action84 fix y-check classified

- Frontier: verify whether targeting the `_PickList::action` `+0x84=500` writer is enough to change the final `floor_list` draw geometry.
- Hypothesis: if the true `floor_list` PickList is being pushed off-screen by the action writer at `0x002d332c`, then clearing `+0x84` both after the proven `setRecords` save point and inside the `action` writer for the saved PickList should make final `_PickList::drawRecord()` observe `_PickList+0x84 == 0`.
- Changed one variable: generated and installed `work/librooneyj-exploration-action84-fix-ycheck.so`, SHA-256 `3882B36AF0FA089A3746AA3ABC7A8F555C60DB4F47BA2169712529F4D7513F72`. It saved the proven floor-list PickList, cleared `target+0x84` after `setRecords`, intercepted the `0x002d332c` writer so only the saved target receives `0` instead of `500`, and then used `_PickList::drawRecord` SIGILL classifiers: `0x003e7f0e` for `+0x84 == 0`, `0x003e7f10` for `+0x84 == 500`, and `0x003e7f12` for other.
- Runtime correction: an earlier no-trap run was invalid because pulling `/data/app-lib/com.square_enix.million_cn-1/librooneyj.so` showed stock SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`, not the y-check probe. After reinstalling, `patch-lib` verified installed SHA-256 `3882B36AF0FA089A3746AA3ABC7A8F555C60DB4F47BA2169712529F4D7513F72` at `/data/app-lib/com.square_enix.million_cn-1/librooneyj.so`.
- Server check: `node .\server\test-bootstrap-server.js` passed. The helper server then recorded `/connect/app/exploration/area` and `/connect/app/exploration/floor` with decrypted `area_id=0`.
- Observed: `work/kssma-runtime-exploration-action84-fix-ycheck-after-floor4-logcat.txt` recorded `Fatal signal 4 (SIGILL)` at `pc 003e7f0e`; registers included `r2=00000084` and `r3=00000000`. This is the classifier for final `floor_list` `_PickList+0x84 == 0`.
- Conclusion: the `action84` interception does reach the true floor-list PickList and clears the final draw offset. If the non-SIGILL visual build still shows the area map, then the remaining blocker is no longer high-Y cull alone; it is visibility, draw order, clipping, alpha, or another scene/layout state that keeps the correctly-positioned `floor_list` from being visible.
- Next: rerun the same fix without the `_PickList::drawRecord` trap and collect screenshot plus logcat. Do not repeat schema, identity, count, row-renderer, or `+0x84` classifier probes unless the installed native hash or request chain differs.

## Exploration action84 visual fix failed

- Frontier: test whether the now-proven `+0x84 == 0` action fix is sufficient to make `floor_list` visible.
- Hypothesis: if high-Y cull was the only remaining blocker, the non-SIGILL action84 fix should show the floor list after `/connect/app/exploration/floor`.
- Changed one variable: installed `work/librooneyj-exploration-floorlist-action84-fix.so`, SHA-256 `B34C8519302FA4FBBF00BAC5D3DA951347C96B4A855ED6FEA360440AB60FC9F7`. It is the y-check fix without the `_PickList::drawRecord` trap.
- Server check: `node .\server\test-bootstrap-server.js` passed. Runtime reached `/connect/app/exploration/area` and `/connect/app/exploration/floor`; `work/kssma-runtime-exploration-action84-visualfix-after-floor-requests.txt` shows decrypted `area_id=0`.
- ARM19 check: `patch-lib` verified installed SHA-256 `B34C8519302FA4FBBF00BAC5D3DA951347C96B4A855ED6FEA360440AB60FC9F7`. Login reached `RooneyJActivity`; helper server was restarted manually after the login harness stopped its own server.
- Observed: logcat artifact `work/kssma-runtime-exploration-action84-visualfix-after-floor-logcat.txt` has no fatal signal or resource/texture miss. Screenshot `work/kssma-runtime-exploration-action84-visualfix-after-floor.png` still shows the area-selection map and `Local Area`, not the floor list.
- Conclusion: clearing the final `floor_list` PickList y-offset is not sufficient. The next root-cause search must move above draw geometry to scene/layout state: visibility flags, draw order, clipping/alpha, or the active behavior leaving `area_map`/`area_list` in front.
- Next: statically inspect `layout_exploration_area.xml` behavior and native visibility/action handlers for `floor_list_active`, `floor_list_active2`, `floor_list_true`, `area_map`, `area_list`, and `floor_list`. Do not repeat `+0x84` probes without a new observable.

## Exploration post-floor retap still selects area

- Frontier: after `/connect/app/exploration/floor` returns 200 and the non-SIGILL action84 fix is installed, determine whether the visible `Local Area` card is actually a floor-row screen disguised as the old area card, or whether the old area-list path is still the active touch target.
- Hypothesis: if `floor_list` is active despite the stale-looking screenshot, tapping the visible card again should call the later floor-row route instead of the area-to-floor route.
- Changed one variable: no code changed. With `work/librooneyj-exploration-floorlist-action84-fix.so` still installed, tapped the same visible card coordinates once more after the first `/exploration/floor` response.
- Server check: persistent helper server stayed on ports `50005` and `10001`; `fast-health` returned Android `4.4.2` / `armeabi-v7a` / boot completed on `127.0.0.1:5583`.
- ARM19 check: `work/kssma-runtime-exploration-after-floor-visible-card-retap-requests.txt` recorded a new `POST /connect/app/exploration/floor` with decrypted `area_id=0`. `work/kssma-runtime-exploration-after-floor-visible-card-retap-logcat.txt` had no fatal signal. Screenshot `work/kssma-runtime-exploration-after-floor-visible-card-retap.png` still shows the area-selection map.
- Observed: the retap did not produce a later floor-row route. It repeated the area-to-floor request.
- Conclusion: the remaining blocker is not merely that a hidden/unstyled floor row looks like the area card. The foreground touch path still behaves as `area_list` or equivalent area-selection state after floor data has been fetched.
- Next: inspect the native selection path and layout visibility/action state for `area_list` vs `floor_list`. A useful next probe should classify which PickList receives `getSelected` on the retap, or which component remains visible/frontmost, rather than trying more floor XML or `+0x84` patches.

## Exploration post-floor retap getSelected classified

- Frontier: prove which native selection branch handles the tap after `/connect/app/exploration/floor` has returned.
- Hypothesis: if the floor screen is truly active, the next card tap should enter the `state==2` floor-row branch at `_ExplorationArea::update+0x112` / `0x003413c6`; if it is still area-selection, it should enter one of the area `getSelected` branches.
- Changed one variable: installed native-only classifier `work/librooneyj-exploration-retap-getselected-classifier.so`, SHA-256 `5E23670527EA2E7D26942B370152457DD34CA3202C0DA3D0B2D5CED7CAFA47E6`. It set a BSS flag only after the `/floor` post-data point, then trapped only on successful `getSelected` return at:
  - `0x003e7776` = `state==0` area/focus branch after `0x00341376`;
  - `0x003e77b6` = `state==2` floor-row branch after `0x003413c6`;
  - `0x003e7e76` = `state==4` explicit `area_list` branch after `0x00341484`.
  A prior broad update-entry classifier `work/librooneyj-exploration-retap-state-classifier.so` was rejected because it crashed with SIGSEGV near the patch cave before `/exploration/floor`; do not use that run as client logic evidence.
- Server check: persistent helper server served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with decrypted `area_id=0`. Artifact `work/kssma-runtime-exploration-retap-getselected-classifier-requests.txt` records the first two requests; the follow-up retap artifact `work/kssma-runtime-exploration-retap-getselected-afterfloor-retap-requests.txt` has no new request because the classifier trapped first.
- ARM19 check: `patch-lib` verified the installed hash, login reached `RooneyJActivity`, and the third tap after `/floor` crashed as intended.
- Observed: `work/kssma-runtime-exploration-retap-getselected-afterfloor-retap-logcat.txt` records `Fatal signal 4 (SIGILL)` at `pc 003e7776`. This maps to the `state==0` area/focus `getSelected` branch, not the `state==2` floor-row branch and not the `state==4` explicit area-list branch.
- Conclusion: after floor data has been fetched, `_ExplorationArea+0x3c` is back at `0` by the time the next tap is handled. The blocker is a state/foreground transition problem: floor data and floor PickList exist, but the scene does not remain in floor-row selection state.
- Next: statically classify writes to `_ExplorationArea+0x3c` between the `/floor` post-data point and the next tap. The fix should preserve `state=2` after floor-list creation or prevent the later reset to `0`, then validate that the next tap reaches `_ExplorationModel::move(...)` instead of `/exploration/floor`.

## Exploration post-floor state-zero writer classified

- Frontier: identify which `_ExplorationArea+0x3c = 0` write runs after `/connect/app/exploration/floor` and before the next tap is handled as `state==0`.
- Hypothesis: one of the known state-zero writes is executing after the floor post-data point and overwriting the intended `state=2`.
- Changed one variable: installed native-only classifier `work/librooneyj-exploration-state-zero-writer-classifier.so`, SHA-256 `32AABEBB5BE4B517C25E83729992535B18641A675A18E34BF69EED22BD196C28`. It set the same BSS flag after the `/floor` post-data point, then trapped only when a flagged state-zero write was reached:
  - `0x003e7772` = `0x0034149a` state4 selected area-list zero;
  - `0x003e77b2` = `0x00341538` state2 reset zero;
  - `0x003e7e72` = `0x003415e2` focus/end area branch zero;
  - `0x003e7eb2` = `0x00342050` preUpdate model-error zero.
- Server check: runtime served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with decrypted `area_id=0`; artifact `work/kssma-runtime-exploration-state-zero-writer-classifier-requests.txt`.
- ARM19 check: `patch-lib` verified installed hash; login reached `RooneyJActivity`; manual taps reached area then floor.
- Observed: `work/kssma-runtime-exploration-state-zero-writer-classifier-logcat.txt` hit `Fatal signal 4 (SIGILL)` at `pc 003e7e72`. Backtrace included `_Layout::getFocus(unsigned long) const`, matching the focus/end branch, not the explicit area-list selected branch and not the model-error branch.
- Conclusion: the floor response sets up floor data, but the area focus/end update path at `0x003415e2..0x003415e4` later writes `_ExplorationArea+0x3c = 0`. This explains why the next tap enters `state==0` and repeats `/exploration/floor`.
- Next: test one minimal native fix: after the `/floor` post-data flag is set, make `0x003415e2` preserve `state=2` instead of writing `0`. Then validate the next tap no longer repeats `/exploration/floor` and ideally reaches the floor-row `_ExplorationModel::move(...)` path.

## Exploration failed state2-preserve sprint audit

- Frontier: after `/connect/app/exploration/floor` returns 200, keep `_ExplorationArea+0x3c` in the state-2 floor-row selection path long enough for the next tap to reach `_ExplorationModel::move(...)` instead of repeating `/exploration/floor`.
- Hypothesis: preserving `state=2` after the floor-list `putData` path and preventing the focus/end zero writer should make the next card tap enter the `floor_list` selection branch.
- Changed one variable at a time:
  - Installed `work/librooneyj-exploration-preserve-state2-after-floor.so`, SHA-256 `20030DD87A207C2AD5D38E093D9AA0AB8376A67963AC44B397035359CF713753`.
  - Installed `work/librooneyj-exploration-state2-entry-negative-classifier.so`, SHA-256 `F6808D38DB4F7CFB2AA9E9189E952092CF15DFC4400FC71DB0509CEF43B582BA`.
  - Rebuilt corrected probes `work/librooneyj-exploration-state2-entry-corrected-classifier.so`, SHA-256 `BEF0637EE9D76B2BBFAEE5C373800A13DD8FD7044FD6B6582F982D4258767279`, and `work/librooneyj-exploration-postfloor-state-entry-classifier.so`, SHA-256 `3216B3388844B18D9D8770CBF2E8434FE4415AA0A80AB5E42FD9435C49BC4735`.
- Server check: `node .\server\test-bootstrap-server.js` still passed before these native-only runs; server XML was not changed.
- ARM19 check:
  - `patch-lib` verified installed hashes for the tested probes.
  - Login reached `RooneyJActivity` in the recorded runs.
  - Manual exploration taps produced `/connect/app/exploration/area` and `/connect/app/exploration/floor` requests in the post-floor classifier run; artifacts include:
    - `work/kssma-runtime-exploration-state2-entry-negative-classifier-*`
    - `work/kssma-runtime-exploration-state2-entry-corrected-classifier-*`
    - `work/kssma-runtime-exploration-postfloor-state-entry-classifier-*`
- Observed:
  - `preserve-state2-after-floor` stopped the immediate repeated `/exploration/floor` in one visual run, but still left the screenshot on the area map and did not produce a later floor-row route.
  - `state2-entry-negative-classifier` trapped at `pc 003e7f06`, but this probe is rejected as clean product evidence: its state2-entry replay path could force non-state2 traffic into the floor branch, so it can only suggest that forced `floor_list getSelected` may return negative.
  - `state2-entry-corrected-classifier` trapped at `pc 003e77aa`, but this probe is also insufficient as post-floor evidence because it had no post-floor gate and could fire before `/connect/app/exploration/floor`.
  - `postfloor-state-entry-classifier` trapped at `pc 003e77c2`; registers showed `r3=00000004`, meaning the flagged update entry saw `_ExplorationArea+0x3c == 4`, not `2`. The trap occurred before the tail-captured `/floor` response line, proving the `0x00342108` flag point is not a safe floor-only anchor by itself.
- Conclusion:
  - The useful new fact is narrower than the intended fix: state preservation at `0x003415e2` alone is not enough, and a later/adjacent state flow can leave the scene in state `4` at update entry.
  - The failed sprint did not produce a valid final fix. It produced a corrected next frontier: classify every post-`0x00342108` write to `_ExplorationArea+0x3c` and identify the writer that overwrites or bypasses state `2`.
  - Do not use the rejected `state2-entry-negative` or ungated `state2-entry-corrected` trap PCs as proof that the natural post-floor state2 branch is entered.
- Next:
  - Run exactly one state-writer classifier from `work/build-exploration-postfloor-state-writer-classifier.py`.
  - Success for that next run is one concrete trap PC mapped to a state writer such as `0x00342036` state1-to-state4, `0x00341538` state2-reset-zero, `0x003415e2` focus-end-zero, or `0x00342050` preUpdate-error-zero.
  - Stop after that one run and write the result before attempting any fix.
- Do not repeat:
  - `state2-entry-negative-classifier` as product evidence.
  - Ungated state2-entry traps.
  - Server floor XML field sweeps.
  - `+0x84`-only visual fixes.
  - Any native probe whose branch replay was not disassembled and checked before install.

## Process hard-stop lesson from the failed exploration sprint

- Failure mode: the work drifted from “run static/runtime loop until fixed” into repeated probe construction without a deliverable boundary. Several probes produced invalid or ambiguous evidence, and the findings were not written down before starting the next probe.
- Required correction:
  - Future tasks must be cut into one frontier with one success criterion and one stop condition.
  - A 90-minute work block must end with a committed conclusion in `reverse-notes.md`, even if the conclusion is “probe invalid.”
  - Two consecutive patches without a new route/logcat/native-PC/screenshot/activity observable require a hard stop.
  - A bad probe must be documented as bad before any successor uses its result.
  - Native probes must include byte checks, cave checks, disassembly of replay branches, and trap PC map before `patch-lib`.
- Current safe next action: build and run only `work/build-exploration-postfloor-state-writer-classifier.py`, then stop and record the single writer result.

## Exploration post-floor state-writer classifier hit initModel path

- Frontier: after `/connect/app/exploration/floor` returns 200, identify the next `_ExplorationArea+0x3c` writer before attempting another floor-list or floor-row fix.
- Hypothesis: the corrected post-floor state-writer classifier should trap on exactly one state writer after the `/floor` path, giving a concrete next static branch to explain.
- Changed one variable: generated and installed only `work/librooneyj-exploration-postfloor-state-writer-classifier.so`, SHA-256 `D07E21CD70ABC2A5FF24002770FC1A50C540CFB20AB21A7F7E87E3AE129B4F42`. Server XML, resources, APK Java, click coordinates, and response shapes were not changed.
- Static gate:
  - Source stock native hash was `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
  - Builder verified original bytes, code cave zero space, replay branches, and trap PC map.
  - Trap map included `0x003e7f72` = writer `0x00340e8c`, label `initmodel-state1`, write `state=1`.
- Server check: `node .\server\test-bootstrap-server.js` passed before runtime. Persistent helper server later served `/connect/app/exploration/area` and `/connect/app/exploration/floor` with encrypted 200 responses.
- ARM19 check:
  - Initial `fast-health` hit an ADB transport failure; `repair-adb` returned no JSON; `diagnose` allowed restart, so `restart-runtime -Force -Reason "fast-health adb-transport failed; repair-adb returned no JSON; diagnose restartAllowed=true and primary 127.0.0.1:5583 not found"` was used.
  - `ensure-baseline` then passed; helper commands continued to report primary TCP `127.0.0.1:5583` as connectable but offline for direct getprop, with healthy ARM19 legacy serial `emulator-5582` used by the harness/observe path.
  - `patch-lib` verified installed hash matched the classifier hash.
- Runtime:
  - Login reached visible main menu under `RooneyJActivity`.
  - Manual tap `1090,250` hit main-menu exploration and produced `/connect/app/exploration/area`.
  - Manual tap `730,280` hit `Local Area` and produced `/connect/app/exploration/floor` with decrypted `area_id=0`.
  - Artifacts:
    - `work/kssma-runtime-exploration-postfloor-state-writer-classifier-*`
    - `work/kssma-runtime-exploration-postfloor-state-writer-after-area-tap-*`
    - `work/kssma-runtime-exploration-postfloor-state-writer-after-floor-tap-*`
- Observed:
  - `work/kssma-runtime-exploration-postfloor-state-writer-after-floor-tap-requests.txt` records `/connect/app/exploration/area` then `/connect/app/exploration/floor` with decrypted `area_id=0`.
  - `work/kssma-runtime-exploration-postfloor-state-writer-after-floor-tap-logcat.txt` records `Fatal signal 4 (SIGILL)` at `pc 003e7f72`.
  - Backtrace top is the classifier cave; by the generated map this is `initmodel-state1`, writer `0x00340e8c`, not `focus-end-zero`, `state2-reset-zero`, `state1-to-state4`, or `preUpdate-error-zero`.
- Conclusion:
  - The next post-floor writer observable is an init/model path that writes `_ExplorationArea+0x3c = 1`.
  - This is a new/other path relative to the planned four branch cases. Do not jump directly to `focus-end-zero`, `state2-reset-zero`, `state1-to-state4`, or `preUpdate-error-zero` fixes from this run.
  - Static inspection of `work/exploration-ui-disasm-annotated.txt` shows `0x00340e8c` is inside `_ExplorationArea::initModel(SceneInitializer)`, immediately after `LayoutScene::putModel("nScene", ...)`, and performs normal scene initialization (`state=1`, clears offsets `0x54/0x48/0x4c`, sets `0x50` and `0x56`). It is not a floor-row selection writer and should not be patched as a product fix.
  - Because the classifier flag is set at `0x00342108`, and earlier evidence already proved that anchor is not floor-only, this trap most likely exposes an over-broad flag window or a scene re-init path after the selected floor response. Treat it as a probe-boundary finding, not as proof that `initModel` is the root cause.
  - The route frontier remains before floor-row movement; do not implement `/connect/app/exploration/explore` until `Model::connect(0x17)` is statically closed and a floor-row click emits that route.
- Cleanup: restored installed native to stock `work/million_cn/apktool/lib/armeabi/librooneyj.so`; `patch-lib` verified installed SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
- Next:
  - Replace the broad `0x00342108` flag anchor before any next state-writer probe. A useful next observable should set the flag only after the decrypted `/exploration/floor` model update has completed, or should gate on the known floor-model/list object identity, so initModel and unrelated scene setup writes do not trap.
  - Only after the anchor is narrowed, classify whether the natural path progresses `state=1 -> state=4`, reaches `focus-end-zero`, or reaches `state2-reset-zero` before the next tap.

## Exploration sticky floor-list mode patch accepted

- Frontier: `/connect/app/exploration/floor` returned 200 and populated the scene-side floor list, but the scene stayed visually on the area card path and the next tap repeated `/exploration/floor`.
- Hypothesis: a gated native patch in `_ExplorationArea::preUpdate()` can force the existing `floor_list_active2` path only when the model floor vector is non-empty, preserving the floor-list UI without changing XML/server/resource data.
- Changed one variable:
  - Added `work/build-exploration-sticky-floorlist-mode.py`.
  - Generated `work/librooneyj-exploration-sticky-floorlist-mode.so`, SHA-256 `2A12D64209E287F4470F66915D6BFC9DD56B5DADAEAE2156085480073784A0F6`.
  - Native-only install via `work/kssma-runtime.ps1 patch-lib`; server XML, resources, Java, APK packaging, and floor response fields were not changed.
- Static gate:
  - Builder verified stock SHA-256 `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
  - Builder verified original bytes at `0x00341f26`, `0x002d2ed8`, and `0x002d332c`.
  - Builder verified zero code caves at `0x003e7720..0x003e77df` and `0x003e7e60..0x003e7edf`.
  - Branch map:
    - `0x00341f26 -> 0x003e7720`; non-empty `model+0x58/+0x5c` floor vector branches to existing `0x00342142` (`floor_list_active2` path); empty/null/state2 cases resume at `0x00341f2a`.
    - `0x002d2ed8 -> 0x003e77a0`, saving the generated floor-list PickList while the gate flag is set and clearing its `+0x84`.
    - `0x002d332c -> 0x003e7e60`, preserving normal `+0x84=500` behavior except for the saved floor-list PickList target.
  - Trap map: none; this is a branch-gated product patch, not a classifier.
- Checks:
  - `node .\server\test-bootstrap-server.js` passed.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health` passed on ARM19 (`armeabi-v7a`, Android `4.4.2`, boot completed), with the known primary TCP serial offline warning and healthy `emulator-5582` legacy serial.
  - `patch-lib` verified installed SHA-256 equals source SHA-256: `2A12D64209E287F4470F66915D6BFC9DD56B5DADAEAE2156085480073784A0F6`.
- Runtime artifacts:
  - Main menu: `work/kssma-runtime-sticky-floorlist-mainmenu-*`.
  - After exploration tap: `work/kssma-runtime-sticky-floorlist-after-explore-*`.
  - After area tap and `/floor`: `work/kssma-runtime-sticky-floorlist-after-floor-*`.
  - After floor-row tap: `work/kssma-runtime-sticky-floorlist-after-floor-tap-*`.
- Observed:
  - Tap `1090,250` from main menu produced `/connect/app/exploration/area`.
  - Tap `730,280` on `Local Area` produced `/connect/app/exploration/floor` with decrypted `area_id=0`.
  - Screenshot `work/kssma-runtime-sticky-floorlist-after-floor.png` shows the floor-list UI, not the old area card: title `Local Area`, one row displaying `区域 1`.
  - Tap `720,270` on that row did not repeat `/connect/app/exploration/floor`.
  - Instead it emitted `/connect/app/exploration/get_floor` with decrypted params `area_id=0`, `floor_id=2`, `check=1`.
  - Because `/connect/app/exploration/get_floor` is not implemented in the server yet, the client then showed the normal network error popup on `work/kssma-runtime-sticky-floorlist-after-floor-tap.png`. Activity stayed in `RooneyJActivity`; no tombstone/SIGILL/crash was observed.
- Conclusion:
  - The floor-list mode switch is now proven by screenshot and route behavior.
  - The previous two-day blocker was not an XML field sweep problem; forcing the existing native floor-list-active path behind a real floor-vector gate is enough to preserve the floor list and unblock the next route.
  - The next frontier moves from floor-list visibility to implementing or analyzing `/connect/app/exploration/get_floor` / route id `0x17` response semantics.
- Do not repeat:
  - Floor XML field/value sweeps for this symptom.
  - `+0x84`-only visual fixes.
  - Broad `0x00342108` post-floor anchoring as floor-only proof.
