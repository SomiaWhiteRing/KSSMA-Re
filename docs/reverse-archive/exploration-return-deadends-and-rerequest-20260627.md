# Exploration Return Deadends And Rerequest 20260627

Hierarchy regression, latch/area_list_sp return dead ends, classifiers, and accepted area re-request return fix.

Source: `reverse-notes.md` before compaction, archived in full at `reverse-notes-full-before-compaction-20260627.md`.

<!-- original lines 1497-2237 -->

## Exploration hierarchy regression audit

- Frontier: user-reported regression after the minimal-loop patch: tapping
  exploration can land directly on the floor list, and returning to the秘境列表
  can show an empty list. The intended hierarchy is exploration -> 秘境列表 ->
  楼层列表 -> 关卡, with returns moving one level up.
- Hypothesis: `/connect/app/exploration/area` was incorrectly carrying nested
  `floor_info_list` data. Combined with the accepted sticky native patch's
  broad "floor vector non-empty" gate, this can make the area-list stage look
  like a floor-list stage before the user selects a秘境, or after stale floor
  data remains in the model.
- Changed one variable:
  - Removed nested `<floor_info_list>` from `EXPLORATION_AREA_XML`.
  - Tightened the server self-check so `/exploration/area` must not include
    `<floor_info_list>` or `<floor_info>`.
  - Left `/exploration/floor`, `/exploration/get_floor`, and `/exploration/explore`
    response fields unchanged.
- Server check:
  - `node .\server\test-bootstrap-server.js` passed. The encrypted
    `/exploration/area` response size dropped from 928 bytes to 592 bytes,
    confirming the floor-list data was removed from the area-list response.
- Runtime check:
  - Planned observable was one manual ARM19 path: main menu -> exploration must
    show the秘境列表 first, then tapping `Local Area` must emit
    `/connect/app/exploration/floor` and show the floor list.
  - This could not be completed in this run because `fast-health` failed with
    `failureClass="adb-transport"` after `adb connect 127.0.0.1:5583` returned
    connected but all primary getprops reported `device offline`; legacy
    `emulator-5582` getprops then timed out.
  - Per AGENTS.md, ran only the recommended
    `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 repair-adb`.
    It failed without JSON output and without a `restartAllowed=true` result, so
    no emulator restart was attempted.
  - A parallel `patch-lib` attempt made during the initial health failure timed
    out and produced no installed-hash proof; treat it as invalid runtime setup,
    not client behavior evidence.
- Observed:
  - Only server/static evidence is valid for this entry.
  - No new screenshot, route, activity, or installed native hash was collected
    after the hierarchy fix because the ARM19 ADB transport was unhealthy.
- Conclusion:
  - The server-side hierarchy bug is real and fixed: area-list XML no longer
    embeds floor-list XML.
  - Runtime acceptance remains open. If the direct-to-floor-list symptom
    persists after this server fix, the next one-variable change should narrow
    `work/build-exploration-sticky-floorlist-mode.py` so the floor-list gate is
    fresh-response scoped, not merely "model floor vector non-empty".
  - The exploration background is a separate value-domain problem for
    `/exploration/get_floor` field `bg`; do not change it by guess while the
    hierarchy runtime observable is blocked.
- Next:
  - Restore ARM19 ADB health first. Then rerun exactly one hierarchy check with
    artifact prefix `work/kssma-runtime-exploration-hierarchy-*`.
  - Success is screenshot proof of `秘境列表` after the exploration entry,
    screenshot proof of `楼层列表` only after selecting `Local Area`, and a
    non-empty秘境列表 after returning one level.

## Exploration hierarchy correction narrowed to fresh floor response

- Frontier: the accepted sticky floor-list patch can still explain the
  user-reported hierarchy regression because it forced floor-list mode whenever
  the model floor vector was non-empty. That is too broad for stepwise
  navigation; stale floor data can exist when entering exploration or returning
  from the floor list.
- Hypothesis: floor-list forcing should run only after stock
  `_ExplorationArea::preUpdate()` has already reached the fresh floor-response
  path, not at function entry and not merely because `model+0x58/+0x5c` is
  non-empty.
- Changed one variable:
  - Updated `work/build-exploration-sticky-floorlist-mode.py` so the native hook
    moved from `0x00341f26` to `0x003420b6`.
  - The new hook point is after stock checks for state-3 floor handling,
    no-error, `+0x55 == 0`, and `+0x56 != 0`. The cave clears `+0x56`, marks the
    saved floor-list PickList flag, and branches to existing
    `floor_list_active2`.
  - Kept the earlier `setRecords` saved-PickList and `+0x84` guards unchanged.
- Static gate:
  - Builder verified stock SHA-256
    `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`.
  - Builder verified original bytes at `0x003420b6`, `0x002d2ed8`, and
    `0x002d332c`.
  - Builder verified code caves before writing.
  - Generated `work/librooneyj-exploration-sticky-floorlist-mode.so`, SHA-256
    `485477C9FDC17698D1F5593EB133909357172820C8AB0497D77FB7B61711CCD0`.
  - Branch map:
    - `0x003420b6 -> 0x003e7720`; stock `+0x56` fresh floor path ->
      `0x00342142`.
    - `0x002d2ed8 -> 0x003e77a0`; resume `0x002d2edc`.
    - `0x002d332c -> 0x003e7e60`; resume `0x002d3332`.
  - Trap map: none; this is a branch-gated product patch candidate.
- Server check:
  - `node .\server\test-bootstrap-server.js` passed. `/exploration/area`
    remains free of `<floor_info_list>` and `<floor_info>`.
- ARM19 check:
  - Not installed or runtime-validated. `fast-health` timed out after the prior
    ADB transport failure, and `repair-adb` had already failed without
    `restartAllowed=true`. Per AGENTS.md, no emulator restart or patch-lib
    install was attempted.
- Observed:
  - Static evidence only. There is no installed SHA-256 proof for this new
    native candidate yet, so it is not runtime evidence.
- Conclusion:
  - The hierarchy fix now has two parts ready for validation: area-list XML no
    longer carries floor-list data, and native floor-list forcing is scoped to
    the stock fresh floor-response branch.
  - The next valid runtime must first restore ADB health, then install this
    `.so` with `patch-lib` and verify installed/source SHA-256 equality before
    collecting screenshots or requests.
- Next:
  - One ARM19 hierarchy run only: main menu -> exploration must show non-empty
    秘境列表; tapping `Local Area` must emit `/exploration/floor` and show
    楼层列表; Back from floor list must show non-empty 秘境列表, not an empty list
    and not direct floor-list entry.

## Exploration main background value-domain opened

- Frontier: user reports the exploration floor/main background is visibly
  wrong. Current `/connect/app/exploration/get_floor` sends `<bg>exp_sarch</bg>`.
- Hypothesis: `bg` is a real consumed value, but `exp_sarch` is only a
  diagnostic candidate copied from available resources, not proven original
  floor background data.
- Static evidence:
  - `work/exploration-get-floor-schema-card-20260627.md` confirms
    `/exploration/get_floor` owns field `bg`.
  - `layout_exploration_main.xml` binds `exploration_bg` param `bgName` to
    `exp_model.bgName`.
  - `rule_resource.xml` maps exploration main scene `3005` to `exp_sarch` and
    `exploration`; exploration area scene `3002` to `exp_map_bg` and
    `exploration_place`.
  - The save dump contains `exp_sarch`, `exp_map_bg`, `exploration`, and
    `exploration_place`.
- Artifact:
  - Added `work/exploration-bg-value-card-20260627.md`.
- Conclusion:
  - Do not treat `exp_sarch` as accepted visual truth. It is currently only a
    working value that lets `exploration_main` render.
  - The next background fix should be exactly one `get_floor.bg` value change,
    but only after finding a stronger value source for area_id/floor_id. Do not
    combine that visual field change with the hierarchy/native patch runtime.

## Exploration hierarchy runtime acceptance blocked by ADB transport

- Frontier: validate the corrected hierarchy on ARM19: main menu -> exploration
  must show non-empty 秘境列表; selecting `Local Area` must emit
  `/connect/app/exploration/floor` and show 楼层列表; returning from 楼层列表
  must show a non-empty 秘境列表 rather than direct floor-list entry or an empty
  list.
- Hypothesis: the current two-part fix should preserve the hierarchy because
  `/exploration/area` no longer embeds floor data and
  `work/build-exploration-sticky-floorlist-mode.py` now hooks only the stock
  fresh floor-response path at `0x003420b6`.
- Static/server check:
  - `node .\server\test-bootstrap-server.js` passed.
  - `work/kssma-server.ps1 stop; start; status` restarted the helper server on
    the current code. Status showed PID `70000`, `Port50005=True`,
    `Port10001=True`, `Health50005=True`.
  - `python .\work\build-exploration-sticky-floorlist-mode.py` passed static
    validation and regenerated
    `work/librooneyj-exploration-sticky-floorlist-mode.so` with SHA-256
    `485477C9FDC17698D1F5593EB133909357172820C8AB0497D77FB7B61711CCD0`.
- ARM19 check:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health`
    failed with `failureClass="adb-transport"` and `restartAllowed=false`.
    The primary `adb-connect-primary` stage timed out; later getprop probes
    reported `device '127.0.0.1:5583' not found`; legacy
    `emulator-5582` probes also reported not found.
  - Ran only the recommended
    `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 repair-adb`.
    It exited `1` with no JSON/stdout and no `restartAllowed=true`.
- Observed:
  - No `patch-lib` was attempted for this run.
  - No installed/source native SHA proof, screenshot, request chain, activity,
    or logcat artifact was collected after the failed health gate.
- Conclusion:
  - Runtime acceptance is blocked by ADB transport, not by a new client
    behavior observable.
  - This run is invalid as product behavior evidence. The corrected server XML
    and fresh-response native candidate remain ready for the next valid ARM19
    run.
- Next:
  - Restore ARM19 ADB health outside gameplay logic, then rerun
    `fast-health`.
  - Only after `fast-health` passes: run
    `patch-lib -ApkPath .\work\librooneyj-exploration-sticky-floorlist-mode.so`
    and require installed/source SHA-256 equality before collecting hierarchy
    screenshots.

## Exploration hierarchy runtime acceptance: floor response still returns to area foreground

- Frontier: validate the corrected exploration descent after the emulator was
  restarted: main menu -> exploration -> non-empty 秘境列表 -> Local Area ->
  楼层列表, and prove the next click is no longer another `/exploration/floor`.
- Hypothesis: removing `floor_info_list` from `/exploration/area` plus the
  fresh floor-response native gate at `0x003420b6` should keep the first screen
  as area list and switch to floor list only after `/exploration/floor`.
- Static/server/native gate:
  - `node .\server\test-bootstrap-server.js` passed before runtime.
  - `work/build-exploration-sticky-floorlist-mode.py` regenerated
    `work/librooneyj-exploration-sticky-floorlist-mode.so` with SHA-256
    `485477C9FDC17698D1F5593EB133909357172820C8AB0497D77FB7B61711CCD0`.
  - `patch-lib -ApkPath .\work\librooneyj-exploration-sticky-floorlist-mode.so`
    installed successfully. Source SHA-256 and pulled installed
    `work/kssma-runtime-exploration-hierarchy-installed-librooneyj.so` SHA-256
    both equal `485477C9FDC17698D1F5593EB133909357172820C8AB0497D77FB7B61711CCD0`.
- Runtime:
  - User had closed the emulator. `ensure-runtime` restarted ARM19, then
    `fast-health` passed through the healthy legacy serial `emulator-5582`
    (`Android 4.4.2`, `armeabi-v7a`, boot `1`). The primary TCP alias
    `127.0.0.1:5583` remained noisy/offline, but helper commands used the
    healthy ARM19 legacy serial.
  - Login reached `com.square_enix.million_cn/com.test.RooneyJActivity`.
  - Artifact prefix:
    `work/kssma-runtime-exploration-hierarchy-*`.
- Observed:
  - Tapping the main-menu exploration button emitted only
    `/connect/app/exploration/area`; screenshot
    `work/kssma-runtime-exploration-hierarchy-after-explore.png` shows the
    non-empty `Local Area` 秘境列表. This fixes the direct-to-floor-list symptom.
  - Tapping `Local Area` emitted `/connect/app/exploration/floor` with decrypted
    `area_id=0`; screenshots
    `work/kssma-runtime-exploration-hierarchy-after-area.png` and
    `work/kssma-runtime-exploration-hierarchy-after-area-wait.png` still show
    `Local Area` / `选择秘境`, not a floor row.
  - Tapping the same visible row again emitted another
    `/connect/app/exploration/floor` with decrypted `area_id=0`, not
    `/connect/app/exploration/get_floor`.
  - `RooneyJActivity` stayed resumed; no crash or fatal native signal was seen
    in the collected logcat. The repeated APN permission `SecurityException`
    remains the known network-agent noise.
- Conclusion:
  - Hierarchy acceptance is partial and not complete. `/exploration/area` no
    longer pollutes the client with floor data, so entry now correctly starts at
    秘境列表.
  - The floor response still does not put the actual selectable foreground into
    floor-list mode. The next click repeats `/exploration/floor`, proving the
    client still treats the foreground item as an area item.
  - Do not work on `get_floor`, `explore`, or the exploration background until
    this foreground/state switch is fixed.
- Next frontier:
  - Native-only: inspect the fresh `/exploration/floor` response path around
    `_ExplorationArea::preUpdate`, especially the state writer for
    `_ExplorationArea+0x3c` and whichever PickList/action target controls the
    visible/selectable foreground. The current `0x003420b6` gate changes the
    request ordering enough to preserve 秘境列表 entry, but it is insufficient to
    make the floor list selectable.

## Exploration area-floor latch patch rejected: bad entry replay

- Frontier: reuse the accepted broad sticky floor-list behavior without
  reintroducing direct main-menu -> floor-list entry. The candidate adds a
  fresh `/exploration/floor` latch and allows the old entry-point force only
  while that latch is set.
- Hypothesis: a latched `_ExplorationArea::preUpdate()` entry gate can preserve
  main-menu -> 秘境列表 while still forcing the real floor-list foreground after
  `/connect/app/exploration/floor`.
- Changed one variable:
  - Added `work/build-exploration-area-floor-latch.py`.
  - Generated and installed
    `work/librooneyj-exploration-area-floor-latch.so`, SHA-256
    `72C2970FF0CCD23BBFCB90531D3C3634CBDF0A6836528DFC0C06796B26F85A24`.
  - `patch-lib` verified installed/source SHA-256 equality.
- Static/server checks:
  - Builder verified stock SHA-256
    `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`,
    patch-site original bytes, code caves, and branch map.
  - `node .\server\test-bootstrap-server.js` passed.
- Runtime artifacts:
  - Login/main menu:
    `work/kssma-runtime-exploration-area-floor-latch-login-*`.
  - After exploration tap:
    `work/kssma-runtime-exploration-area-floor-latch-after-explore-*`.
- Observed:
  - Login reached visible main menu.
  - Tapping exploration emitted `/connect/app/exploration/area`.
  - Client then crashed with `Fatal signal 11`; activity returned to launcher.
  - Logcat maps `pc a34829ec` to `librooneyj.so+0x003409ec`, the stock helper
    called from `_ExplorationArea::preUpdate()` after the patched entry point.
  - Registers showed `r1=0x30`, matching a bad resume state where the hook's
    false path clobbered the stock `r3=[this+0x5c]` and resumed at
    `0x00341f2a` without replaying it.
- Conclusion:
  - This installed latch build is rejected as a bad native patch. The crash is
    not product evidence about `/exploration/area` or XML.
  - Fix only the entry hook replay: before the false resume to `0x00341f2a`,
    restore stock state `r1=0` and `r3=[r4+0x5c]`.

## Exploration hierarchy latch v2: descent fixed, return area-list empty

- Frontier: validate the repaired area/floor latch after fixing the bad
  `_ExplorationArea::preUpdate()` entry replay.
- Hypothesis: restoring `r3=[this+0x5c]` on the latch false path should keep
  stock area-list initialization stable while preserving the fresh
  `/exploration/floor` latch.
- Changed one variable:
  - Updated `work/build-exploration-area-floor-latch.py` entry cave replay.
  - Generated and installed
    `work/librooneyj-exploration-area-floor-latch.so`, SHA-256
    `E256649C8F0E8630F9BFE88137886F8D69A3BC2A6FBB122F7C06D25A49A3BE3B`.
  - `patch-lib` verified installed/source SHA-256 equality.
- Static/server checks:
  - Builder verified stock SHA-256, patch-site original bytes, code caves, and
    branch map.
  - `node .\server\test-bootstrap-server.js` passed.
- Runtime artifacts:
  - Login/main menu:
    `work/kssma-runtime-exploration-area-floor-latch-v2-login-*`.
  - After exploration tap:
    `work/kssma-runtime-exploration-area-floor-latch-v2-after-explore-*`.
  - After `Local Area` tap:
    `work/kssma-runtime-exploration-area-floor-latch-v2-after-area-*`.
  - After floor-list return button:
    `work/kssma-runtime-exploration-area-floor-latch-v2-after-floor-back-*`.
- Observed:
  - Tapping exploration emitted only `/connect/app/exploration/area`; screenshot
    shows non-empty `Local Area` 秘境列表. No fatal signal was observed.
  - Tapping `Local Area` emitted `/connect/app/exploration/floor` with decrypted
    `area_id=0`; screenshot shows the floor list row `区域 1`.
  - Pressing the in-scene return button from floor list emitted no new request
    and stayed in `RooneyJActivity`, but screenshot returned to the map with an
    empty area-list foreground: no `Local Area` card was visible.
- Conclusion:
  - The latch idea now fixes the downward hierarchy: 首页 -> 秘境列表 -> 楼层列表.
  - The remaining defect is only the floor-list -> area-list return foreground:
    state resets to area mode, but the `area_list` PickList is not visible or
    remade.
- Next frontier:
  - Patch exactly the state2 reset return path at `0x00341538` to trigger the
    existing `area_list_sp` behavior, which is a real XML `behavior` and only
    does `visible area_list=true` plus `action area_list remake`.

## Exploration hierarchy latch v3: area_list_sp return hook insufficient

- Frontier: fix only the floor-list -> area-list return foreground after v2
  proved the downward hierarchy works.
- Hypothesis: stock return state resets mode to area state but does not remake
  the area list because `area_list_true` is misspelled as `behaviar`; explicitly
  triggering the valid `area_list_sp` behavior at the state2 reset path should
  restore the `Local Area` row.
- Changed one variable:
  - Updated `work/build-exploration-area-floor-latch.py` so the state2 reset
    hook at `0x00341538` clears the latch, writes `_ExplorationArea+0x3c = 0`,
    and invokes `_Layout::event(hash("area_list_sp"))`.
  - Generated and installed
    `work/librooneyj-exploration-area-floor-latch.so`, SHA-256
    `BE137C3F76FDE8D08CB8641975CC1C37C4541B7D726926C9F1834F5406FBEB5B`.
  - `patch-lib` verified installed/source SHA-256 equality.
- Static/server checks:
  - Builder verified stock SHA-256, patch-site original bytes, code caves, and
    branch map including the state2 reset cave at `0x003e7ee0`.
  - `node .\server\test-bootstrap-server.js` passed.
- Runtime artifacts:
  - Login/main menu:
    `work/kssma-runtime-exploration-area-floor-latch-v3-login-*`.
  - After exploration tap:
    `work/kssma-runtime-exploration-area-floor-latch-v3-after-explore-*`.
  - After `Local Area` tap:
    `work/kssma-runtime-exploration-area-floor-latch-v3-after-area-*`.
  - After floor-list return button:
    `work/kssma-runtime-exploration-area-floor-latch-v3-after-floor-back-*`.
- Observed:
  - Main menu -> exploration still emitted only `/connect/app/exploration/area`
    and showed the non-empty `Local Area` 秘境列表.
  - `Local Area` -> floor still emitted `/connect/app/exploration/floor` with
    decrypted `area_id=0` and showed the floor row `区域 1`.
  - Pressing the in-scene return button emitted no new request and did not
    crash, but screenshot
    `work/kssma-runtime-exploration-area-floor-latch-v3-after-floor-back.png`
    still shows the area map with an empty foreground: no `Local Area` card.
- Conclusion:
  - The downward latch remains valid, but the return defect is not solved by
    firing `area_list_sp`.
  - Do not keep adding behavior-name triggers for return. The next useful
    observable is native state/data around the area-list PickList on return:
    whether the original area-list PickList still has records/buttons, whether
    it is being drawn, and whether the visible foreground is the expected
    object.

## Exploration hierarchy latch v4: state1 return rebuild hook insufficient

- Frontier: fix only the floor-list -> area-list return after v3 proved
  `area_list_sp` was insufficient.
- Hypothesis: writing `_ExplorationArea+0x3c = 1` on the state2 return path
  should ask next `preUpdate()` to rerun the stock `createAreaList()` path,
  rebuilding area data instead of only firing a UI behavior.
- Changed one variable:
  - Updated `work/build-exploration-area-floor-latch.py` state2 reset cave to
    clear the latch, write state=1, and resume stock at `0x0034153c`; removed
    the `area_list_sp` event call.
  - Generated and installed
    `work/librooneyj-exploration-area-floor-latch.so`, SHA-256
    `81365902BFF8AA925476852D908DA1C5E02F8B43DE57FDC64A6DD23DAED3DE57`.
  - `patch-lib` verified installed/source SHA-256 equality.
- Static/server checks:
  - Builder verified stock SHA-256, patch-site original bytes, code caves, and
    branch map; trap map none.
  - `node .\server\test-bootstrap-server.js` passed.
- Runtime:
  - Restarted ARM19 only after `fast-health` failed, `repair-adb` produced no
    recovery, and `diagnose` reported `restartAllowed=true`. Follow-up
    `fast-health` passed via `emulator-5582`; primary `127.0.0.1:5583` remained
    noisy/offline.
  - Artifacts:
    `work/kssma-runtime-exploration-area-floor-latch-v4-login-*`,
    `work/kssma-runtime-exploration-area-floor-latch-v4-after-explore-*`,
    `work/kssma-runtime-exploration-area-floor-latch-v4-after-area-*`,
    `work/kssma-runtime-exploration-area-floor-latch-v4-after-floor-back-*`.
- Observed:
  - Exploration entry emitted `/connect/app/exploration/area` and showed
    non-empty `Local Area`.
  - Tapping `Local Area` emitted `/connect/app/exploration/floor` with decrypted
    `area_id=0` and showed floor row `区域 1`.
  - Floor-list return emitted no request, no crash, activity remained
    `RooneyJActivity`, but screenshot still showed empty area foreground with no
    `Local Area`.
- Conclusion:
  - Downward hierarchy remains fixed, but one-level return from floor list to
    area list is still not fixed.
  - Returning with state=1 and stock `createAreaList` scheduling is not
    sufficient.
  - Since v3 (`area_list_sp`) and v4 (`state=1`) are consecutive return patches
    with no new return observable, stop the native return patch loop now.
- Next:
  - Next valid round must be classifier/read-only, not product patch: identify
    the actual `area_list` PickList on return and classify records/buttons/draw/
    visibility, or recover the real stock return path object/state. Do not
    patch more behavior names or state writes without that evidence.

## Exploration area return classifier: scene vector empty, vector-only rebuild insufficient

- Frontier: diagnose floor-list -> area-list return without guessing more
  behavior names, state values, or `area_list_sp` calls.
- Hypothesis: the correct entry path and the broken return path diverge at one
  of model area data, scene-side area vector, PickList records, or visibility /
  foreground state.
- Changed one variable:
  - Added `work/build-exploration-area-return-classifier.py`, a native
    classifier based on the area/floor descent latch. It saves the correct-entry
    area-list context and traps at `_ExplorationArea::update` state2 return with
    PC-mapped UDFs.
  - Classifier builder verified stock SHA-256
    `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`, patch
    bytes, executable zero caves, branch replay, and trap map.
  - Classifier `.so` SHA-256:
    `17EB2A54B2214B37D4F2D29E202FD0B941101C8EE2F495E08AC8AA3516257B8B`;
    `patch-lib` verified installed/source equality.
- Static/server checks:
  - `python .\work\build-exploration-area-return-classifier.py` passed.
  - `node .\server\test-bootstrap-server.js` passed.
- Runtime:
  - `fast-health` passed on ARM19. Product flow reached `Local Area`, then
    floor row `区域 1`, then the in-scene floor-list return button.
  - Artifacts:
    `work/kssma-runtime-exploration-area-return-classifier-*`.
- Observed:
  - Return hit classifier PC `librooneyj.so+0x00010288`.
  - Trap map meaning: scene-side `_ExplorationArea+0x70` area vector count is
    zero. Model-side area vector was already proven non-empty before this trap.
- Product branch tried:
  - Updated `work/build-exploration-area-floor-latch.py` state2 return cave to
    clear the latch, call `_ExplorationArea::createAreaList()` at `0x00341788`,
    then resume stock return events with state reset to `0`.
  - Product `.so` SHA-256:
    `414B3E056F99D28B707E424F801BD63F30D40EECB234E795287A30E0BB2F4EEC`;
    `patch-lib` verified installed/source equality.
  - Artifacts:
    `work/kssma-runtime-exploration-area-return-product-area-*`,
    `work/kssma-runtime-exploration-area-return-product-floor-*`,
    `work/kssma-runtime-exploration-area-return-product-return-*`.
- Observed product result:
  - Descent still works: main menu -> `/connect/app/exploration/area` ->
    non-empty `Local Area`; `Local Area` -> `/connect/app/exploration/floor` ->
    floor row `区域 1`.
  - Floor-list return no longer traps or crashes, but screenshot
    `work/kssma-runtime-exploration-area-return-product-return.png` still shows
    the area map with empty foreground: no `Local Area` card.
- Conclusion:
  - Scene-side area vector emptiness is real, but vector-only rebuild is not
    enough. The remaining defect is now narrowed to post-rebuild area-list
    PickList records/remake/visibility/foreground.
  - Do not add another product return patch before a new classifier distinguishes
    records from draw/visibility/foreground after the vector rebuild.

## Exploration area return post-rebuild classifier: data present, foreground/remake missing

- Frontier: continue from the vector-only rebuild failure without adding another
  blind product patch.
- Hypothesis: after rebuilding the scene-side area vector, the remaining empty
  foreground is either missing PickList records/draw state or an area-list
  foreground/remake visibility problem.
- Changed one variable:
  - Extended `work/build-exploration-area-return-classifier.py` with
    `POST_REBUILD=1` mode. This mode performs the same state2-return
    `createAreaList()` rebuild as the failed product patch, then traps at the
    classifier point.
  - Rebuild-classifier `.so` SHA-256:
    `D4398334CF2F51640DAAA8B26DCF9B418BD3077317BCB63016DF079BDAEFA3FC`;
    `patch-lib` verified installed/source equality.
- Static/server checks:
  - `$env:POST_REBUILD='1'; python .\work\build-exploration-area-return-classifier.py`
    passed.
  - `node .\server\test-bootstrap-server.js` passed.
- Runtime:
  - Flow `main menu -> Local Area -> 区域 1 -> return` hit classifier PC
    `librooneyj.so+0x00010282`.
  - Artifacts:
    `work/kssma-runtime-exploration-area-return-rebuild-classifier-*`.
- Observed:
  - Trap `0x00010282` maps to: model area vector non-empty, scene-side area
    vector non-empty, captured area-list PickList present, PickList records
    count non-zero, draw flag `+0x7e` non-zero, scroll/offset `+0x84` zero.
- Conclusion:
  - After `createAreaList()`, the area data and PickList records are healthy.
    The empty foreground is now narrowed to foreground/visibility/remake event
    routing.
  - The next product patch may combine the two separately insufficient fixes:
    state2 return rebuilds area vector and then invokes the valid
    `area_list_sp` behavior to show/remake `area_list`. This is not the v3
    blind behavior-only patch; it is gated by the post-rebuild classifier result.

## Exploration area return combo patch bad probe: wrong event/string anchors

- Frontier: apply one product return patch after the post-rebuild classifier
  proved area data, PickList records, draw flag, and scroll offset were healthy.
- Hypothesis: the state2 return path could call `createAreaList()` and then
  trigger the same area-list behavior event used by the successful entry path.
- Changed one variable:
  - Modified `work/build-exploration-area-floor-latch.py` state2 return cave to
    call `createAreaList()`, compute a behavior hash from the assumed
    `area_list_sp` string pointer, then call the assumed layout event function.
  - Generated and installed
    `work/librooneyj-exploration-area-floor-latch.so`, SHA-256
    `6A26C2D20E65C042BF3C1A4DBE20E68E5F477BFFAB30FFE48DADF33DF51CF7A6`;
    `patch-lib` verified installed/source SHA-256 equality.
- Observed:
  - Descent still worked: main menu -> non-empty `Local Area`, then
    `Local Area` -> floor row `区域 1`.
  - Pressing the floor-list return button crashed.
  - Logcat artifact:
    `work/kssma-runtime-exploration-area-return-final2-return-logcat.txt`.
  - Crash PC mapped to `librooneyj.so+0x001f420e`, symbolized as
    `LayoutScene::ScrollCompound::exec(int)+33`, with fault address
    `0x43640000`.
  - The assumed `AREA_LIST_SP_STRING=0x000c6b81` bytes are
    `ntE\0_ZN17_AnmExpCardHolder...`, not `area_list_sp`.
- Conclusion:
  - This is a bad product patch/probe. Do not use `0x001f4200` as a layout
    behavior event function, and do not use `0x000c6b81` as the `area_list_sp`
    string anchor.
  - Revert to the safe vector-only return rebuild baseline before any new
    runtime run. Next recovery must use static evidence for the real behavior
    event call path or avoid behavior-event calls entirely.

## Exploration area return vtable area_list_sp: event call valid but too early

- Frontier: fix floor-list -> area-list return after the post-rebuild classifier
  proved area data, PickList records, draw flag, and scroll offset were present.
- Hypothesis: the previous crash came from bad function/string anchors, so using
  the stock `_ExplorationArea::update()` event convention (`GetHashCode(name)`
  then `this->vtable+0x54`) with the real string `area_list_sp` at
  `0x003e2518` should remake the area list after `createAreaList()`.
- Changed one variable:
  - Updated `work/build-exploration-area-floor-latch.py` so the state2 return
    cave clears the latch, calls `createAreaList()`, then triggers
    `area_list_sp` through `this->vtable+0x54`.
  - Builder verified the real string bytes at `0x003e2518` equal
    `area_list_sp\0`, stock SHA-256, patch-site original bytes, caves, and
    branch replay.
  - Generated and installed
    `work/librooneyj-exploration-area-floor-latch.so`, SHA-256
    `04139469F7938CFA6B73D2D0CB3D9BA915064D430746452DBC6B187EF088E3C8`;
    `patch-lib` verified installed/source SHA-256 equality.
- Static/server checks:
  - `python .\work\build-exploration-area-floor-latch.py` passed.
  - `node .\server\test-bootstrap-server.js` passed.
- Runtime:
  - `fast-health` passed on ARM19 via the healthy legacy serial
    `emulator-5582`; primary `127.0.0.1:5583` remained noisy/offline for direct
    getprops.
  - Artifacts:
    `work/kssma-runtime-exploration-area-return-vtable-login-*`,
    `work/kssma-runtime-exploration-area-return-vtable-area-*`,
    `work/kssma-runtime-exploration-area-return-vtable-floor-*`,
    `work/kssma-runtime-exploration-area-return-vtable-return-*`.
- Observed:
  - Main menu -> exploration emitted only `/connect/app/exploration/area` and
    screenshot `work/kssma-runtime-exploration-area-return-vtable-area.png`
    shows non-empty `Local Area`.
  - `Local Area` -> floor emitted `/connect/app/exploration/floor` with
    decrypted `area_id=0`, and screenshot
    `work/kssma-runtime-exploration-area-return-vtable-floor.png` shows floor
    row `区域 1`.
  - Floor-list return emitted no new request and did not crash, but screenshot
    `work/kssma-runtime-exploration-area-return-vtable-return.png` still shows
    the area map with an empty foreground: no `Local Area` row.
- Static follow-up:
  - The stock return sequence after `0x0034153c` calls behavior names
    `scalex1`, `area_list_true`, `floor_list_false`,
    `placeview_visible_false`, and optionally `back_close`.
  - This means the vtable call itself is valid, but triggering `area_list_sp`
    inside the state2 reset cave happens before the stock return event sequence
    finishes.
- Conclusion:
  - Do not keep this as an accepted fix. It preserves descent but does not fix
    return.
  - The only remaining product attempt allowed in this round is to move the
    same proven `area_list_sp` vtable call after the stock return events; if
    that produces no new screenshot/route/logcat/activity observable, stop the
    return patch loop.

## Exploration area return post-event area_list_sp: still empty, stop patch loop

- Frontier: last allowed product attempt for floor-list -> area-list return in
  this round.
- Hypothesis: triggering the same proven `area_list_sp` vtable event after the
  stock return sequence (`scalex1`, `area_list_true`, `floor_list_false`,
  `placeview_visible_false`) should avoid the early-event ordering problem and
  make the rebuilt area PickList visible.
- Changed one variable:
  - Updated `work/build-exploration-area-floor-latch.py` so
    `0x00341538` only clears the latch and calls `createAreaList()`.
  - Added a post-stock hook at `0x00341590` that replays the original
    `+0x55` check and triggers real `area_list_sp` through
    `GetHashCode(0x003e2518)` and `this->vtable+0x54`.
  - Generated and installed
    `work/librooneyj-exploration-area-floor-latch.so`, SHA-256
    `BB451B40A2F27690D42FB13B79A5CAA33A0B6E0D4B3CB2D4E2AB735A85E3C1C8`;
    `patch-lib` verified installed/source SHA-256 equality.
- Static/server checks:
  - `python .\work\build-exploration-area-floor-latch.py` passed after
    verifying stock bytes, `area_list_sp\0`, caves, and branch replay.
  - `node .\server\test-bootstrap-server.js` passed.
- Runtime:
  - Artifacts:
    `work/kssma-runtime-exploration-area-return-postevent-login-*`,
    `work/kssma-runtime-exploration-area-return-postevent-area-*`,
    `work/kssma-runtime-exploration-area-return-postevent-floor-*`,
    `work/kssma-runtime-exploration-area-return-postevent-return-*`.
- Observed:
  - Entry still works: `/connect/app/exploration/area` and non-empty
    `Local Area`.
  - Descent still works: `/connect/app/exploration/floor` with decrypted
    `area_id=0` and floor row `区域 1`.
  - Floor-list return emitted no new request and did not crash, but screenshot
    `work/kssma-runtime-exploration-area-return-postevent-return.png` still
    shows an empty area foreground with no `Local Area` row.
- Conclusion:
  - Two event-based return product patches (`041394...` early vtable event and
    `BB451...` post-stock vtable event) produced no accepted return fix.
  - Stop this product patch loop now. The next valid round must be classifier
    or request-path recovery, not another guessed behavior/state patch.
  - Recommended next frontier: classify the actual `area_list` object's
    visibility/render traversal after return, or implement the explicitly
    allowed fallback of re-requesting `/connect/app/exploration/area` on the
    floor-list return path using a statically recovered native request call.

## Exploration area return re-request: accepted hierarchy fix

- Frontier: floor-list -> area-list return must stop landing on an empty
  foreground.
- Hypothesis: the reliable way back is not another local UI event. The
  floor-list return path should reuse the already-proven "main menu exploration
  button -> `/connect/app/exploration/area` -> `Local Area`" request path.
- Static evidence:
  - Wrote
    `work/exploration-area-entry-rerequest-card-20260627.md`.
  - `_ExplorationModel::area()` at `librooneyj.so+0x001d63c0` constructs an
    empty param map and calls `Model::connect` at `0x001e16e4` with route id
    `0x14`.
  - Native route string anchor `0x003d98b4` is `exploration/area`.
  - The sibling `_ExplorationModel::floor(int)` path uses route id `0x15`,
    matching the observed `/connect/app/exploration/floor` neighborhood.
- Changed one variable:
  - Added `work/build-exploration-area-return-rerequest.py`.
  - It keeps the current safe descent patches and changes only the state-2
    floor-list return path at `0x00341538`.
  - The return cave clears the temporary floor-list latch, loads the current
    `_ExplorationModel*`, calls `_ExplorationModel::area()`, calls
    `LayoutScene::trigger(model)` at `0x001f3eb4`, writes area-wait state `1`,
    then resumes stock code at `0x0034153c`.
  - The builder verifies stock SHA-256
    `CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27`,
    all original patch bytes, the `exploration/area` string bytes, and zero
    caves; it prints a request map, branch map, and `trap map: none`.
  - Generated
    `work/librooneyj-exploration-area-return-rerequest.so`, SHA-256
    `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`.
- Checks:
  - `python .\work\build-exploration-area-return-rerequest.py` passed.
  - `node .\server\test-bootstrap-server.js` passed.
  - `fast-health` passed on ARM19 before install using the healthy legacy
    serial `emulator-5582`; primary `127.0.0.1:5583` remained the known noisy
    offline alias.
  - `patch-lib` installed the native patch and verified installed/source
    SHA-256 equality:
    `8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D`.
  - A later duplicate attempt to save the same hash check into
    `work/kssma-runtime-exploration-area-return-rerequest-hashes.txt` happened
    after acceptance and failed with `adb-transport`; do not treat that as
    product behavior evidence.
- Runtime:
  - Login artifact prefix:
    `work/kssma-runtime-exploration-area-return-rerequest-login-*`.
    The login helper's WebView-dismiss helper hit a UI XML parse error, but the
    screenshot still showed the visible main menu under `RooneyJActivity`.
  - Helper server was restarted before exploration taps.
  - Acceptance artifacts:
    `work/kssma-runtime-exploration-area-return-rerequest-area-*`,
    `work/kssma-runtime-exploration-area-return-rerequest-floor-*`,
    `work/kssma-runtime-exploration-area-return-rerequest-return-*`, and
    `work/kssma-runtime-exploration-area-return-rerequest-refloor-*`.
- Observed:
  - Main menu exploration tap emitted only
    `/connect/app/exploration/area`; screenshot
    `work/kssma-runtime-exploration-area-return-rerequest-area.png` shows
    non-empty `Local Area`.
  - Tapping `Local Area` emitted `/connect/app/exploration/floor` with
    decrypted `area_id=0`; screenshot
    `work/kssma-runtime-exploration-area-return-rerequest-floor.png` shows
    floor row `区域 1`.
  - Tapping the floor-list return button emitted a new
    `/connect/app/exploration/area`; screenshot
    `work/kssma-runtime-exploration-area-return-rerequest-return.png` shows
    non-empty `Local Area`, not the previous empty foreground.
  - Tapping `Local Area` again emitted another
    `/connect/app/exploration/floor` with decrypted `area_id=0`; screenshot
    `work/kssma-runtime-exploration-area-return-rerequest-refloor.png` shows
    floor row `区域 1`.
  - Request order in the final artifact:
    `/exploration/area` -> `/exploration/floor` ->
    `/exploration/area` -> `/exploration/floor`.
  - Activity stayed in `com.test.RooneyJActivity`; the captured logcat has no
    `Fatal signal`, `SIGILL`, `SIGSEGV`, `SIGABRT`, `JResourceLoader`,
    `getSDPackFile`, or `loadTexture` failure.
- Conclusion:
  - Accepted fix. The hierarchy now works as
    main menu -> non-empty area list -> floor list -> return to non-empty area
    list -> floor list again.
  - Do not continue `area_list_sp`, local rebuild, or draw-flag product patches
    for this bug. The next exploration frontiers are separate: `get_floor` /
    `explore` minimum loop and the wrong exploration background value.
