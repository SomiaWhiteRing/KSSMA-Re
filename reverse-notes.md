# KSSMA-Re Current Reverse Notes

This file is the startup index, not the full experiment log. The full pre-compaction
notes are archived at
`docs/reverse-archive/reverse-notes-full-before-compaction-20260627.md`.

## Current Baseline

- Source APK: `base/com.square_enix.million_cn-1.0.0.100.0712.M330.apk`.
- Unique installable client baseline: `work/client-baseline/KSSMA-Re-client-baseline.apk`.
- Client baseline manifest: `work/client-baseline/client-baseline.json`.
- Current accepted native lib inside the client baseline:
  `work/librooneyj-gacha-business-error-dialog.so`
  (`36A4826BD42BCF203B51D0344AF5A1B479B961BD26DDB4685DD01A8B325B69A2`). It contains the accepted
  exploration hierarchy fixes, gacha result-page card-get touch guard, and generic code-1 business-dialog producer.
- Current baseline APK SHA-256:
  `E8723F5438AFC6D39F4E0913159D2EE7B3BC4F097BD2F5A1E48DE31687C2DCC3`.
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
- Current configurable reward/product data:
  `server/data/server/runtime-config.json` owns the fairy per-slot drop percentage and weighted reward pool;
  `server/data/game/gacha.json` owns four fixed product modes (friendship single, MC single, ticket single, MC 11-draw)
  with editable costs and weighted pools. The admin at `/admin/` edits these values atomically and reloads them for
  new encounters/purchases without a Node restart.

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
- Main menu / home hub is marked complete for the current phase as of 2026-07-01. Accepted coverage now includes
  right-side main buttons, Menu page entries/returns, and bottom deck/friends entries/returns. Human validation
  confirmed the Menu page after the flow fixes.
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
- Main-menu fairy/reward notification server path was restored on 2026-08-19. Static recovery closes
  `_YourDataTagParser::fairy_appearance -> _YourDataTagData+0x38 -> _CPlayer+0x84 ->
  _AnmStatusFairyAppearance`, while `_MainMenuTagParser::rewards` remains the separate reward-box count.
  Login, `/mainmenu/update`, and `/mainmenu` now compute a per-account snapshot from the shared raid registry:
  any enabled account's visible live raid emits `<your_data><fairy_appearance>1`; pending contributor rewards emit
  `<mainmenu><rewards>N`. The HTTP/decrypt self-check seeds a live friend raid, observes
  `fairyAppearance=1/activeRaidCount=1`, then clears it and observes zero. After a controlled server restart,
  the current LAN database produced an actual encrypted/decrypted `/mainmenu/update` HTTP response with
  `fairy_appearance=1`, `activeRaidCount=1`, `rewards=0`; `/menu/fairyselect` then returned scene 29200 and live
  serial 100018. Command: `node .\server\test-bootstrap-server.js` (pass). Full client acceptance is still the visible top-left status plus
  a tap emitting `/connect/app/menu/fairyselect`; do not describe the UI edge as accepted before that observable.
  Path card: `work/mainmenu-fairy-notification-path-card-20260819.md`.
- The user accepted the main-menu fairy notification and list/detail/battle edges on 2026-08-19: the main menu visibly
  showed `妖精出现中`, tapping it opened the live fairy list, and serial 100018 rendered as
  `LonelyZero / 小龙女 Lv.1`. The initial row was history-only because `<put_down>` was zero; native recovery proved
  `_FairySelect::update` calls `fairyFloor` only for `put_down=1`. After that server fix, the user confirmed that the
  fairy detail page and battle both open correctly. The first accepted-detail run nevertheless exposed a distinct
  stack/settlement defect: `/menu/fairyselect -> /exploration/fairy_floor` responded with `next_scene=6200`, and a
  losing `/exploration/fairybattle` incorrectly returned `event_type=18`; the client therefore entered through
  exploration and emitted `/exploration/get_floor(area_id=3,floor_id=4)` after settlement. Static scene recovery
  closes the correct direct path as scene 29200 -> 6202, with loss event 10 retaining the updated live-fairy detail
  and victory event 18 returning to the suspended fairy list. A fresh serial 100019 replay then isolated a second
  direct-entry defect: `/menu/fairyselect -> /exploration/fairy_floor` reached scene 6202 but displayed only
  `adv_avalon_attack` plus battle BGM. Server logs showed a successful response and no later route for 99 seconds;
  A12 kept `RooneyJActivity` resumed and logcat had no native fatal, missing texture, or Java exception. Static native
  recovery proved event 1 is the exploration-only discovery behavior which locally transitions to scene 6202 again,
  whereas event 11 dispatches `fairy_stay`; `layout_exploration_fairy.xml` uses `fairy_stay` to reveal the fairy,
  status, BC/AP, battle, compound, and back controls in the already-active scene. The menu `fairy_floor` response now
  emits `next_scene=6202 + event_type=11`; post-battle loss 10 and victory 18 are unchanged. The HTTP/decrypt self-check
  covers this direct-entry mapping plus loss/remaining-fairy and victory/list settlement. After restart, a real encrypted
  request to the live server for serial 100019 decrypted to HTTP 200, `next_scene=6202`, the requested serial, and
  `event_type=11`; PID 476 was healthy on both 50005 and 10001. Client visual acceptance of event 11 and the two
  settlement return targets remains pending. Path card:
  `work/fairy-shared-raid-account-path-card-20260819.md`.
- Main-menu displayed level now uses the authoritative player progression level. The live save was
  `profile.level=6/profile.townLevel=1`; `renderYourDataXml` previously serialized the stale `townLevel`, causing
  visible `LV1`, although level gain and admin writes consistently update `profile.level`. The original bundled
  battle fixture independently has `town_level=6` and `rank=2`, so `town_level` and `rank` are not aliases. Only
  `town_level` was changed to `profile.level`; rank semantics remain a separate recovery domain. After restart,
  decrypted live `/connect/app/mainmenu` returned `name=LonelyZero,town_level=6,rank=6,next_scene=2100`, and the full
  server self-check passed. Client UI acceptance requires refreshing the main-menu model. Path card:
  `work/mainmenu-player-level-path-card-20260819.md`.

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
- Rejected alternate runtime: the user-provided Android 15 emulator at `127.0.0.1:5555` is reachable
  and healthy as API 35/x86_64, but its 32-bit ABI list contains only `x86`. The unique client APK has
  only `lib/armeabi/librooneyj.so` (`ELFCLASS32`, `EM_ARM`). Normal install failed with
  `INSTALL_FAILED_NO_MATCHING_ABIS`; forced `--abi armeabi-v7a` failed with `ABI armeabi-v7a not
  supported on this device`, and no package was created. This run never reached Activity or network,
  so `10.0.2.2` is not implicated. Evidence: `work/a15-runtime-compatibility-card-20260817.md`.
- Accepted alternate runtime candidate: the user-provided Android 12/MuMu emulator at
  `127.0.0.1:7555` is healthy as API 32/x86_64 and exposes working 32-bit ARM translation. The unique
  client installed as `primaryCpuAbi=armeabi`; MuMu reported `libhoudini.so` and
  `RunningArchitecture=armeabi`. Guest route `10.0.2.0/24` confirmed `10.0.2.2` as the host gateway,
  and device hosts mappings for the two legacy domains reached the existing server on ports 50005/10001.
  The first native abort named the known missing external resource `save/download/rest/treasurebox`;
  reusing the accepted minimal resource set removed it. A cold launch then completed
  `check_inspection -> post_devicetoken -> login`, rendered the main menu, stayed alive through 15 seconds,
  and a Gacha tap emitted `/connect/app/gacha/select/getcontents` and visibly opened scene 9100. About 269
  seconds later, however, that process hit a null `SIGSEGV` at `librooneyj.so` PC `0x003657c6` in the
  `vector<smart_ptr<RewardBoxTagData>>` copy constructor (caller `0x0040b03c`); Android restarted the task,
  repeated login/web, and returned to a visible main menu. No resource-miss accompanied this crash. A12 is
  accepted only as a startup/main-menu/manual investigation candidate, not full gameplay acceptance. Compare
  the same idle-on-gacha-select condition on ARM19 before attributing it to Houdini or changing reward-box state.
  It does not replace ARM19 or weaken its runtime/flow guards.
  Evidence: `work/a12-runtime-compatibility-card-20260817.md` and
  `work/kssma-a12-launch-20260817/summary.json`.
- Accepted MuMu Android 12 installation path: `work/kssma-mumu-a12.ps1` is an isolated alternate-runtime
  installer for `127.0.0.1:7555`; it reuses generic process/ADB helpers but does not change the ARM19 runtime
  configuration or flow gates. `prepare-assets.py -> extract-gacha-pack-resources.py ->
  build-client-baseline.py -> build-mumu-a12-resource-pack.py` produced APK SHA-256
  `D22ED62A8C39210FBC22B91FB224FB33F603AF4CF9927B9014098AAF9398429B`, accepted native SHA-256
  `DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`, and a deterministic static
  resource TAR containing 6,901 files / 517,599,894 payload bytes with SHA-256
  `FF60551898A285A355ECEC0E4C38624BA9999A6A19A6CB668CF8C7C9E66519CF`. Mutable
  `appdata/save_appdata` is excluded and preserved. The installer keeps a stable original-hosts backup,
  idempotently maps both legacy domains to confirmed guest gateway `10.0.2.2`, verifies the installed native
  hash, and runs `sha256sum -c` over the full resource payload. The final single-command replay
  `deploy -StartServer -Launch` passed; after making those final status values mandatory postconditions, the
  unchanged replay passed again in 67.882s: PackageManager selected `armeabi`, all resource hashes and both
  device-side `/healthz` probes passed, PID 6701 remained in `com.test.RooneyJActivity` with no 10-second fatal,
  and `work/kssma-mumu-a12-last-launch.png` showed the main menu. The first replay's final evidence step failed
  only because local `$pid` collided with PowerShell's read-only `$PID`; installation and full resource hashing
  had already passed, and the variable was corrected to `$gamePid`. Do not use `database/master_card` as a
  persistent sentinel because the client can consume it after loading; it is now a separately verified
  stopped-process launch seed for `install-client`, `launch`, and the isolated A12 flow gate. Do not use MuMu's
  unsupported `nc -z`; the accepted persistent probes are `database/master_boss` and device-side `curl /healthz`.
  This accepts installation and repeatable controller-owned card initialization, not the unresolved delayed
  gacha-select crash or full gameplay on A12. Evidence:
  `work/mumu-a12-deployment-card-20260817.md`.
- MuMu A12 now has an isolated automated-flow entry:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-mumu-a12.ps1 flow -Scenario <name> -Tag <tag>`.
  It reuses the accepted login/server/artifact/scenario plumbing through a process-local A12 runtime gate and keeps
  ARM19 unchanged. The current gate is read-only for display: it requires physical `1440x2560` / density 360 with
  no `wm` override, scales only host-side taps/swipes by 2, and retains native 2560x1440 screenshots plus 1280x720
  comparison copies. An earlier `exploration-walk-smoke` passed in 137.536s under a temporary display override with route sequence
  `post_devicetoken -> login -> area -> floor -> get_floor -> explore -> explore -> area -> floor`, two persisted
  moves, and 20% readback; it is historical compatibility evidence, not native-display acceptance. Artifact:
  `work/kssma-flow-exploration-walk-smoke-mumu-a12-qualification-exploration-walk-2`.
- The same qualification rejects promotion of A12 to full gameplay acceptance. An inherited admin fairy rate of
  100% first exposed `adv_chara0` missing in the fairy event path, followed by Android 12 strict-JNI null
  `GetObjectClass` and `SIGABRT`; ordinary exploration/progress flows now explicitly isolate random fairy encounters,
  while `fairy-battle-smoke` remains explicitly enabled. More importantly,
  `gacha-settlement-deck-smoke` reached `/gacha/buy product_id=1 bulk=1 auto_build=1` and atomically saved
  friendship `400 -> 200`, serial 2/master card 9, and `cardsDrawn=1`, but the client then loaded missing
  `thumbnail_chara_0` even though `thumbnail_chara_9` exists and aborted through the same strict-JNI path. Do not
  add guessed zero-name placeholders; recover why the accepted fairy/card data paths resolve to zero. The first
  gacha replay's 11.730s `script-error` was harness-only (`StrictMode Latest` versus optional result properties) and
  was removed without changing client/server behavior; the evidentiary rerun failed as `client-crash` in 88.501s.
  Evidence: `work/mumu-a12-flow-qualification-card-20260818.md`,
  `work/kssma-flow-exploration-walk-smoke-mumu-a12-qualification-exploration-walk`, and
  `work/kssma-flow-gacha-settlement-deck-smoke-mumu-a12-qualification-gacha-settlement-2`.
- Native-display diagnosis on 2026-08-18 falsified display scaling and that run's card-file copy timing as fixes for
  gacha. `gacha-settlement-deck-smoke` at untouched 1440x2560/360 copied the original 260249-byte
  `database/master_card`, received and persisted master card 9, then still requested
  `thumbnail_chara_0` and strict-JNI aborted. `fairy-battle-smoke` reached the exact fairybattle request; the server
  settled `playerWon=true`, `winner=0`, fairy HP 6000 -> 0, player HP 5620 -> 4620, Gold 18 -> 795 and EXP 3 -> 7,
  but the A12 client requested `adv_chara0` and aborted before rendering any battle/result screen. Later timed
  screenshots therefore show MuMu Store after focus fallback and are not gameplay evidence. Artifacts:
  `work/kssma-flow-gacha-settlement-deck-smoke-mumu-a12-native-resolution-master-card` and
  `work/kssma-flow-fairy-battle-smoke-mumu-a12-native-resolution-settlement-diagnosis`. The original bundled
  `local_battle_result.xml` has local `player_enemy=0` losing and `winner=1`; this once suggested that `winner` was
  a player index, but the inference remained conditional on a visible client result and is superseded below. A
  later exact stopped-process/pre-start restore removed the fairy `adv_chara0` blocker, so this earlier result must
  not be generalized into rejection of the serialized cache as a launch input.
- A user-driven native-display A12 battle on 2026-08-18 reached
  `/exploration/fairybattle(user_id=1,serial_id=100007)` and the server atomically settled a local victory
  (`winner=0`, fairy HP `9660 -> 0`, player HP `5620 -> 3220`, Gold `2575 -> 2875`, EXP `42 -> 47`). The client
  then aborted in `GLRenderer.nativeMain` because Android 12 strict JNI rejected a null `GetObjectClass` while
  MediaPlayer was resetting/starting an MP3 decoder. This exact manual window had no `JResourceLoader`, missing-file,
  `adv_chara0`, or `thumbnail_chara_0` line. A read-only device audit matched all 507 sound/voice files to the package
  checksum list and all static files except the known client-consumed `database/master_card`; media volume was
  speaker 100/100 and unmuted. The actual packaging gap was `appdata/save_appdata`: the A12 copy was 2,849 all-zero
  bytes (`E2C2D56F...AA6ADAD`), while the original ZIP/dump contains initialized data. The A12 builder now emits a
  patched `mainbg_70_sp -> mainbg_an` seed and the installer applies it only when the player file is missing or all
  zero, preserving a backup and any nonzero player data. The live one-variable seed changed the device hash to
  `FCA2045D...C973D59`; audio/battle replay is pending the user's manual click.
  Server self-check remains green. Its gacha layout subprocess now resolves the existing project Conda interpreter
  at `miniconda3/envs/KSSMA-Re/python.exe` (or `KSSMA_RE_PYTHON`) before falling back to `python`; this removes the
  Windows Store execution-alias exit 9009 without changing any response XML.
- The clean user replay after that seed proved the two symptoms were separate: music now plays, while fairy battle
  still aborts. `/exploration/fairybattle(user_id=1,serial_id=100008)` settled a local victory (`winner=0`, fairy HP
  `9660 -> 0`, player HP `5620 -> 3220`, Gold `2910 -> 3210`, EXP `53 -> 58`), then the client explicitly threw
  `JResourceLoader` "file cannot be opened" for `save/download/image/adv/adv_chara0` before strict-JNI
  `GetObjectClass(null)` and `SIGABRT`. `save_appdata` retained the repaired nonzero hash, so audio is accepted and
  is no longer the battle frontier. The fairybattle response contains valid `master_card_id=600`, enemy
  `type=30024`, and the package has `adv_chara600`; gacha independently maps valid master card 9 to
  `thumbnail_chara_0` on A12. The common frontier is therefore card-master initialization, not a missing zero-name
  asset. Historical startup evidence proves the original client can issue `/masterdata/card/update`; the next
  bounded classifier will advertise only a newer `card_rev` and leave every other revision and response unchanged.
- The A12 card-master refresh transport classifier made the client send the original `/masterdata/card/update`
  with local `revision=231`; the server returned the complete 260,249-byte recovered binary cache, and main menu
  remained alive. The next user-driven fairy battle still
  requested `adv_chara0` and strict-JNI aborted, while the server correctly settled serial `100009` as a local
  victory with `master_card_id=600`, enemy type 30024, and image id 600. The diagnostic override was removed and
  the server again advertises revision zero. Native inspection then proved the response contract is wrong:
  `ResourceDownloader::parseMasterCardTagData` at `0x003923BD` treats the body as XML through `_TXmlParser` and
  `_MasterDataTagParser`, creates card objects, and only then calls `updateMasterCardList`; it does not consume the
  serialized `database/master_card` cache. The unchanged device `save_version` corroborates that the update was
  not accepted. Do not retry revision values or add a zero-name placeholder; recover the parser-backed card-update
  XML and rerun the same trigger with only the payload representation changed. Evidence:
  `work/mumu-a12-master-card-refresh-card-20260818.md` and
  `work/mumu-a12-master-card-refresh-rejected-20260818`.
- The parser-backed card update is now implemented as the one-variable follow-up. The server pins the recovered
  `database/master_card` hash, consumes all 480 serialized records to their exact boundaries, and renders the full
  `_CardTagParser` field set under `<master_data><master_card_data><update_type>1`; it no longer sends the binary
  cache as wire plaintext. Static checks confirm master 9 -> image `9/5009`, master 22 -> `22/5022`, and master
  600 -> `600/5600`; the encrypted live endpoint is 862,160 bytes and logs `recordCount=480/updateType=1`.
  `node .\server\test-bootstrap-server.js` passes, including an HTTP/decrypt round trip. MuMu still has revision
  231, no external `master_card`, and the server is currently running with only `card_rev=232`; live client
  acceptance and the next user-driven battle are pending. Evidence/schema:
  `work/master-card-update-schema-card-20260818.md` and
  `work/mumu-a12-master-card-xml-live-20260818`.
- The full 480-card XML live run did not initialize the card manager. Login requested card revision 231 and the
  server returned the complete 862,160-byte encrypted XML, but `save_version` retained SHA-256 `EFEA36BB...925C5`
  and no external `database/master_card` appeared. The next user-driven edge created fairy `100010`; tapping battle
  again attempted `adv_chara0`, strict-JNI aborted at `GetObjectClass(null)`, and only then did the already queued
  `/exploration/fairybattle` reach the server and settle a victory. Thus neither HTTP completion nor the later
  settlement proves the battle scene was entered. Stop changing card field names: the schema/root/tag path is
  statically closed and the generated XML parses as 480 records. The next experiment must be a callback classifier,
  not another field scan; use the statically recovered `imagedl_list -> requestDlMCardImage` branch or a bounded
  payload-size/card-count differential to prove whether the callback parsed any card before altering battle data.
  Artifact: `work/mumu-a12-master-card-xml-live-20260818` (`server.stdout.log`, `logcat.txt`,
  `activity-after-battle.txt`, `device-master-state.txt`).

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
- Ordinary fairy encounter entry is accepted on ARM19. `event_type=1` plus the native-parsed `<fairy>` object reuses
  the original `fairy_floor -> scene 6202` path. Artifact
  `work/kssma-flow-exploration-forward-visual-smoke-20260816-223933` records
  `/exploration/explore -> /exploration/fairybattle user_id=1 serial_id=100001`; screenshot
  `screenshots/after-forward-0200ms.png` visibly shows 小龙女 Lv.18 and HP `20000/20000`.
  Battle candidate 1 removed the 501 but rejected non-constructible `next_scene=4103` at
  `_SceneControl::create(int)+105`. Static factory evidence and the APK sample corrected the selector to generic
  VS scene 4100. Artifact `work/kssma-flow-fairy-battle-smoke-scene4100-candidate2-valid` then passed with exact
  `/exploration/fairybattle(user_id=1,serial_id=100001)`, visible original VS, animated battle, and fairy-result
  layout across scenes `4100 -> 4301 -> 4420`; RooneyJ stayed alive. Dynamic artifact
  `work/kssma-flow-fairy-battle-smoke-fairy-battle-dynamic-acceptance` now also accepts player/fairy-owned battle
  records and atomic settlement: visible 小龙女 `6000 -> 0`, Arthur `5620 -> 4620`, two rounds, gold
  `18 -> 795`, EXP `3 -> 7`, `wins=1`, cleared active fairy, and matching history, with a resumed Activity and
  no native crash. The follow-up `work/kssma-flow-fairy-battle-smoke-postbattle-visual-masterboss` artifact accepts
  the post-result refresh and enemy visual mapping: the response refreshes ExplorationModel with
  `event_type=0/encounter=0`, the 18s frame differs from the old encounter by `66.52`, and battle type `30024`
  visibly resolves boss image 600 (小龙女) instead of the generic soldier. Reward presentation and next-click
  behavior remain separate. Static settlement recovery now proves that the blank frame was the ordinary
  `event_type=0` branch; original scene 4420 dispatches `event_type=18` through `area_fairy_dead` and then
  `reward_check_com`, whose `btl_exp` node binds the existing BattleModel Gold/EXP/level fields. The server and
  flow self-checks pass with the post-battle response changed only to `event_type=18/encounter=0`; path card:
  `work/fairy-postbattle-settlement-path-card-20260817.md`. Its first ARM19 replay stopped before login at
  `repair-adb / restart-boot-timeout` with an empty route sequence, artifact
  `work/kssma-flow-fairy-battle-smoke-fairy-settlement-event18-candidate1`; a permitted repair and later
  `fast-health` still reported `emulator-5556 offline`. This is runtime-only evidence, not a failed product
  candidate. Keep the event-18 response candidate and replay it unchanged only after ARM19 health returns.
  Prior accepted evidence:
  `work/fairy-encounter-path-card-20260816.md`, `work/fairy-battle-path-card-20260816.md`, and
  `work/fairy-battle-settlement-schema-card-20260816.md`, plus
  `work/fairy-postbattle-visual-path-card-20260817.md`.

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
- Gacha card-get result-page touch guard accepted:
  - builder: `work/build-gacha-cardget-inner-touch-nullguard.py`
  - source baseline: `work/librooneyj-exploration-area-return-rerequest.so`
  - output/source of the current client-baseline lib: `work/librooneyj-gacha-cardget-inner-touch-nullguard.so`
  - SHA-256: `DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`
  - branch map: `_AnmCmnCardGetWindow::getSelected` entry `0x00258b68 -> 0x003e7f60`
  - scope: only the card-get/bonus-card window touch child is null-guarded; the broader
    `_AnmTouchScreen::getSelected` global guard is not accepted into the baseline.
- Gacha generic business-error dialog producer accepted:
  - builder: `work/build-gacha-business-error-dialog.py`
  - source baseline: `work/librooneyj-gacha-cardget-inner-touch-nullguard.so`
  - output/current client-baseline lib: `work/librooneyj-gacha-business-error-dialog.so`
  - SHA-256: `36A4826BD42BCF203B51D0344AF5A1B479B961BD26DDB4685DD01A8B325B69A2`
  - branch map: `_Main::connect` `0x001c3ba8 -> 0x003e7fa0 -> 0x001c3bae`; only error code `1`
    acquires `_Main`'s scene control and pushes stock `dialog_scene=90100`.
  - accepted A12 screenshots: `work/gacha-business-error-dialog-visible-a12-20260819.png` and
    `work/gacha-business-error-dialog-dismissed-a12-20260819.png`.

Accepted server handlers:

- `/connect/app/exploration/area`
- `/connect/app/exploration/floor`
- `/connect/app/exploration/get_floor`
- `/connect/app/exploration/explore`
- `/connect/app/exploration/fairybattle` (funded success path; insufficient-BC client presentation remains open)
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
  ARM19 remains the only complete acceptance runtime. MuMu A12's isolated flow can pass ordinary exploration, and
  controller-owned cold starts now fix the fairy `adv_chara0` edge; gacha result under the new seed boundary and
  the older delayed reward-box crash remain promotion blockers. See
  `work/mumu-a12-flow-qualification-card-20260818.md`.
- Gacha, weighted fairy rewards, and deck builder are active/in-progress product lines. The server-side single-live-raid,
  loss mounting, attacker contribution, probabilistic weighted card rewards, idempotent claim, manual multi-account baseline, and main-menu
  `fairy_appearance/rewards` publication now pass deterministic two-account and HTTP/decrypt self-checks. The visible
  `mainmenu live-fairy status -> menu/fairyselect -> fairy list` edge is user-accepted. A fresh direct-entry replay
  exposed and statically closed the blank 6202 scene as `event_type 1 -> 11`; the immediate client edge is visual
  acceptance of that `fairy_stay` detail, then proving `loss -> fairy detail` and `victory -> fairy list`, followed by
  friend attack and visible reward-box claim. Per-client account identity is now closed at the server/transport layer:
  login issues a signed `kssma_session` Cookie and the stock Java `DefaultHttpClient/CookieStore` automatically
  replays it. Two-account concurrent HTTP/read-write isolation passes; two-real-client visible co-op remains pending.
  Do not reopen accepted main-menu black-screen, face,
  background, BGM, voice, tapped subtitle, main-button, Menu-page, bottom deck, or bottom friends work without
  new resource-miss, crash, route regression, or screenshot regression evidence.
- Shared prerequisite for both new systems: player owned-card data, card master data, deck slots, card resources,
  and currency/ticket save fields must stay coherent. Frontier cards:
  `work/gacha-system-frontier-card-20260701.md` and `work/deck-builder-system-frontier-card-20260701.md`.
- Gacha first edge is accepted: `flow -Scenario gacha-draw-smoke -Tag gacha-buy-owner-card-1` reached
  `/connect/app/gacha/buy` with `product_id=1`, `bulk=1`, `auto_build=1`, returned a minimal `gacha_buy`
  body, and kept the client alive on the draw scene. Artifact:
  `work/kssma-flow-gacha-draw-smoke-gacha-buy-owner-card-1`; schema card:
  `work/gacha-buy-schema-card-20260701.md`.
- Gacha result edge is accepted: `flow -Scenario gacha-result-smoke -Tag gacha-result-baseline-accepted-1`
  passed using the unique client baseline, without `-ExperimentLibPath`. It proves login -> gacha select ->
  `/connect/app/gacha/buy product_id=1 bulk=1 auto_build=1` -> draw scene -> tap TOUCH SCREEN -> result page
  local transition, with screenshot `screenshots/gacha-result-after-touch.png` and no fatal/resource-miss logcat.
- Gacha rejected result-edge directions:
  - `gacha-result-touch-4` exposed the original crash at `_AnmTouchScreen::getSelected(bool)` through
    `_AnmCmnCardGetWindow::getSelected` (`pc 0x0022c64e`, caller `0x00258b79`).
  - `gacha-result-isnew0-1` and `gacha-result-no-complete-list-2` produced the same crash, so more
    `/gacha/buy` XML field guessing is not the next move.
  - `work/build-gacha-cardget-touch-nullguard.py` guarded only the outer smart pointer and did not fix the crash.
  - `work/build-gacha-touchscreen-nullthis-guard.py` passed once, but it is a broad global guard and is not
    accepted into the baseline.
- Gacha result-page back, paid retry, card persistence, and friendship-point/MC spending are accepted. The 2026-08-19
  server/admin baseline adds independently weighted pools for friendship single, MC single, ticket single, and MC
  11-draw products. Settlement preflights currency and capacity, then writes all result cards atomically; invalid
  products and insufficient balances fail closed without a partial save. Ticket/11-draw visible entry and repeated
  result rendering still require client flow acceptance. The client-visible G1 balance-error dialog is now accepted;
  comp-sheet rewards, holographic rate, and album completion remain open. Path cards:
  `work/fairy-gacha-pool-path-card-20260819.md` and
  `work/gacha-buy-original-balance-dialog-path-card-20260819.md`.
- Gacha-triggered server exit is fixed at the transport boundary. A truncated
  `POST /connect/app/gacha/select/getcontents` reproduced Node 24's uncaught `Error: aborted / ECONNRESET` because
  the async HTTP handler Promise was not observed. `createServer` now catches every request Promise, logs
  `request_error` for disconnects, and keeps both ports alive. The self-check replays the disconnect, requires a
  subsequent `/healthz` 200, then continues through both gacha settlements. Manual post-fix replay kept the same
  PID and returned the next normal gacha-select request. ARM19 reacceptance later passed twice after the slow boot
  recovered: `gacha-result-back-smoke / gacha-server-disconnect-fix-arm19-retest-2` proved the visible select,
  RARE draw, result, and return edge; `gacha-settlement-deck-smoke / gacha-funded-settlement-arm19-retest` proved
  friendship `400 -> 200`, persisted card `serialId=2/masterCardId=9`, history/counter update, and round-table
  readback. Both runs had empty server stderr and no client fatal. The first resumed attempt had exposed a missing
  generated `gacha_cp_button`; the accepted `extract-gacha-pack-resources.py` path restored the original pack assets,
  and `environment.yml` now declares its required `pycryptodome`. The zero-balance result/back smoke still awarded
  a card while holding friendship at zero, so insufficient-balance semantics remain explicitly unaccepted.
  Evidence and exact commands: `work/gacha-server-disconnect-crash-card-20260817.md`.
- Gacha result-page back is accepted: `flow -Scenario gacha-result-back-smoke -Tag gacha-result-back-4` passed on
  ARM19. Route sequence proved `/connect/app/gacha/select/getcontents -> /connect/app/gacha/buy product_id=1
  bulk=1 auto_build=1 -> /connect/app/gacha/select/getcontents` after tapping the visible result-page back button.
  `screenshots/gacha-result-after-back.png` matches the gacha select page and visual diff from the result page was
  `59.76`. Friendship-point results keep retry hidden; paid `gachaType=2` exposes it and is covered by the paid-retry
  acceptance below.
- Flow screenshot reliability fix: `Capture-FlowScreenshot` now retries zero-byte screenshot pulls up to three
  attempts and records `screenshot-attempt` events. This fixes the false `visual-state-mismatch` seen in
  `gacha-result-back-2`, where the draw-scene screenshot was zero bytes but the result-page screenshot was valid.
- Deck-builder D1 entry, D2 leader mode, D4 one-card in-memory edit, and D5 save-request capture edges are accepted.
  D3's native path is
  statically closed in
  `work/deck-builder-edit-native-path-card-20260809.md`: normal DeckScene -> card-select tab `(127,360)` -> sole
  candidate `(226,247)` -> reverse tab `(1144,360)` -> normal DeckScene. The path remains in scene `83200`, sends no
  request, and inserts the selected card into the first empty slot. Artifact
  `work/kssma-flow-deck-builder-edit-smoke-deck-builder-edit-2` proves the runtime edge and unchanged save. D5 artifact
  `work/kssma-flow-deck-builder-save-smoke-deck-builder-save-1` captures the exact `C/lr` request and proves the
  current placeholder response does not write. D5.5 then falsified the candidate explicit
  `<save_deck_card><result>0</result>...` response: artifact
  `work/kssma-flow-deck-builder-save-smoke-deck-builder-save-result0-1` received that exact parser-visible body but
  remained on the populated DeckScene (`diff=0.05`). Static postmortem found the missing gate: header
  `next_scene=83200` is consumed by `_Main::connect` and pushes a new DeckScene whose `initModel` ignores
  `save_deck_card`, so the old model's result branch is never reached. The `next_scene == 0` current-model path is
  now statically closed and supported by the accepted exploration 50% -> 55% same-scene differential. The only D5.6
  runtime invocation stopped at `repair-adb / restart-boot-timeout` before login with an empty route sequence, so it
  did not test that product hypothesis. Its experimental response/strict-flow code was removed, restoring D5
  capture-only. C2-A retired the bad listener/shell probes, and the single C2-B warm restart measured
  `tBoot=102.733s` with stable identity/boot samples, a successful restart helper, one process group, and both
  ports owned by its `emulator-arm.exe`. Keep the existing 120-second restart wait. The next bounded product round
  is D5.6 current-model response acceptance; D6 persistence remains blocked until that runtime edge passes.
- Exploration ordinary walking remains accepted. The user has explicitly reopened the fairy branch: ordinary fairy
  encounter and the original `4100 -> 4301 -> 4420` battle presentation are now accepted. The active edge is
  `accepted post-battle refresh -> reward presentation/return click -> prove next route`.
  Dynamic damage, original battle playback, and atomic gold/EXP/counter/history persistence are accepted by
  `work/kssma-flow-fairy-battle-smoke-fairy-battle-dynamic-acceptance`; see the settlement card for exact values.
  `work/kssma-flow-fairy-battle-smoke-postbattle-visual-masterboss` further accepts the original-model response fix:
  a no-event `<explore>` refresh prevents replay of the defeated `HP 6000/6000` encounter, and enemy battle type
  `30024` visibly selects boss image 600 (小龙女) rather than the generic soldier. The terminal frame exposes the
  exploration return button, but its click/next route and a dedicated reward summary remain unaccepted.
  A browser-skill pass for the three added admin values was also stopped before navigation: its Node kernel could
  not `lstat` `%USERPROFILE%\AppData` in the managed sandbox. The temporary server closed without creating its QA
  save. Do not treat this as a UI failure; API validation/reload self-checks pass and the accepted M1 responsive grid
  is unchanged, but the new fields still need one browser regression when host access is restored.
  Cross-region completion, guardians, rare fairies, and expired/dead fairy handling remain separate frontiers.
- Advanced-fairy static survey is recorded in `work/fairy-advanced-protocol-survey-card-20260817.md`.
  Hypothesis: BC gating was client-side. Static result: falsified for the accepted APK—
  `_ExplorationMain::isBcFull()` at `0x00343274` always returns true, both `BcCheck` handlers always select their
  `*_max_bc` behaviors, and `battleFairy` sends only `user_id,serial_id`. Therefore BC validation/debit must be
  server-authoritative and returned through header `your_data/bc`; the original shortage body and exact debit amount
  remain open. The same survey closes the immediate factor schema (`get_item_parts_event -> event_id -> parts_one ->
  lake_id/parts/master_card_id/parts_num/parts_have[/user_card]`), reward-box list/claim routes and fields, the
  sibling `rare_fairy` parser shape, and the shared-fairy selection/floor/history/lose plus attacker-history routes.
  It also proves reward-box type 1 is card and type 2 is item; types 3..6 are not yet semantically closed. No product
  response or runtime data was changed by this static round.
- Shared-fairy/account server baseline is implemented; path and evidence are indexed by
  `work/fairy-shared-raid-account-path-card-20260819.md`. One active raid is authoritative per discoverer; a losing
  attack records contribution and keeps the raid mounted, which suppresses later exploration encounters. Any enabled
  local account can sequentially select and attack the raid; defeat creates pending type-1 card rewards only for
  recorded attackers, baseline `master_card_id=600 x1`, with finisher `+1`. Claims are idempotent through the player
  save's claimed-id ledger. The admin is the only account-creation path, creates independent saves and scrypt password
  records, exposes account selection plus reward card/count controls, and does not return credentials/hashes.
  `node .\server\test-bootstrap-server.js` passes the two-account loss/assist/claim/replay sequence. MuMu A12 artifact
  `work/kssma-flow-fairy-battle-smoke-mumu-a12-shared-raid-single-account-regression-r2` passes the accepted real-client
  edge `explore -> fairybattle -> get_floor`; its isolated shared ledger records raid 100001 defeated, contributor 1 as
  finisher, and pending card 600 x2. This only accepts regression of the existing single-account edge: the client-visible
  earlier `menu/fairyselect -> exploration/fairy_floor -> fairy detail -> battle` edge was user-accepted through the
  exploration-style stack. The corrected direct 6202 stack initially blanked because menu `fairy_floor` incorrectly
  reused discovery event 1; static recovery changed it to `fairy_stay` event 11. Visual acceptance of that direct detail,
  corrected loss/detail and victory/list return targets, and reward-box claim remain pending. Captures prove gameplay
  request bodies after login have no session/account field and MuMu NAT presents every connection as 127.0.0.1;
  identity must not be inferred from either. Static DEX recovery then found the missing accepted carrier outside the
  encrypted body: `AsyncTaskRunner.connectPost -> com/test/b.run -> HttpUtil.connectPost` reuses one static
  `DefaultHttpClient` per process, sends through `DefaultHttpClient.execute`, and explicitly enumerates its
  `CookieStore` after requests. The server now signs an account/time/nonce token from the account password hash and
  local protocol key, returns it as HttpOnly `kssma_session` on login, and resolves every later request to a local
  account/save path; malformed, expired, disabled-account, and bad-signature cookies fail closed. No-cookie direct
  protocol fixtures retain a documented last-login compatibility fallback. `node .\server\test-bootstrap-server.js`
  passes two distinct login cookies, concurrent mainmenu identity (`局域网亚瑟` vs `协力亚瑟`), concurrent explore
  writes (AP `9->8` and `14->13`, one independent move each), and bad-signature 401 with byte-identical saves. After
  final live restart was fingerprint-clean and healthy on both ports; a real encrypted account-1 login returned the Cookie and the
  Cookie-authenticated `/mainmenu` returned HTTP 200/name `Yukie`, with a redacted session log identifying user 1.
  This retires the planned per-route native body patch; two physical client processes and visible friend attack remain
  the final acceptance edge. Path card: `work/multi-client-session-path-card-20260819.md`.
- 2026-08-17 regression: `work/kssma-runtime-flow.ps1 -SelfTest` and `git diff --check` passed. The first bare
  `node server/test-bootstrap-server.js` invocation stopped at its child `python` with Windows status `9009` because
  this PowerShell session had no Python on `PATH`; rerunning the identical test with
  `C:\Users\jsyzd\miniconda3\envs\KSSMA-Re` prepended to `PATH` passed all bootstrap-server checks. This was an
  invocation-environment failure, not a product assertion or ARM19 permission failure.
- Current accepted exploration regression artifact after the gacha native baseline promotion:
  `work/kssma-flow-exploration-smoke-gacha-baseline-regression-exploration-1`.
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
- The former blanket fairy freeze is superseded by the user's 2026-08-16 reopening and the current fairy cards above.
  Cross-region completion, guardians, rare fairies, expired/dead fairy handling, and reward-box/card/factor drops stay
  frozen; do not use this older baseline note to freeze the accepted ordinary-fairy branch again.
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
- Menu-page route skeletons are in progress, not fully accepted. The old artifact
  `work/kssma-flow-menu-buttons-route-smoke-menu-full-after-haveparts` showed item and parts-list screenshots, but
  manual testing exposed that the old flow allowed weak local-page proof and manual `start-server` could keep stale
  bootstrap code alive. The helper server now tracks a code/data fingerprint, and menu flow local/routed page tests now
  use screenshot-diff gates: opening item/parts must visibly leave Menu, and back must visibly return. The focused
  regression is `flow -Scenario menu-item-parts-smoke`; full Menu-page acceptance still needs entry-specific flows,
  especially WebView-backed update/help pages. The former parts-list blocker was an empty scene skeleton showing the
  native no-data overlay; `work/menu-haveparts-schema-card-20260630.md` records the parser evidence and the current
  minimal `<have_parts><lake><parts_list>` payload.
- Menu item/parts focused runtime accepted: `work/kssma-flow-menu-item-parts-smoke-menu-item-parts-visual-gate` passed
  on ARM19. It proves item is a client-local page that visibly opens (`open-menu-item-visual-open` diff `91.73`) and
  returns to Menu (`return-from-open-menu-item-visual-return` diff `0`); parts list emits
  `/connect/app/menu/haveparts`, visibly opens (`open-menu-parts-list-visual-open` diff `53.09`), then returns through
  `/connect/app/menu/menulist` with visual diff `0`. `ensure-client-baseline` was already matched, and logcat had no
  fatal/SIGSEGV/resource-miss evidence. Screenshot logging now records file byte length so empty screenshot files are
  not marked successful evidence.
- Main-menu bottom deck/friends runtime accepted: `work/kssma-flow-mainmenu-bottom-buttons-smoke-deck-friends-bottom-scene17100`
  passed on ARM19. Under the historical response, bottom deck emitted `/connect/app/roundtable/edit` with `move=1`,
  opened scene `10100` as a round-table viewer (not the deck editor), and returned
  to main menu after two back taps. Bottom friends emits `/connect/app/menu/friendlist` with `move=0`; the accepted
  response uses `nextScene=17100` plus a minimal `friend_list/user_list/user` body, opens visibly (`diff 91.08`),
  and returns through `/connect/app/mainmenu`. Do not change this entry back to `22100`: artifact
  `work/kssma-flow-mainmenu-bottom-buttons-smoke-deck-friends-bottom-final-2` proved `22100` still crashes in
  `_SceneControl::create(int)` even after the friend-list body exists.
- Gacha dynamic frontier accepted: `work/kssma-flow-gacha-draw-smoke-gacha-buy-owner-card-1` passed on ARM19.
  It proves safe select entry -> `/connect/app/gacha/buy` with decrypted `product_id=1`, `bulk=1`, `auto_build=1`
  -> minimal `gacha_buy` response -> client still alive on draw scene. Rejected intermediate:
  `work/kssma-flow-gacha-draw-smoke-gacha-buy-minxml-1` added `final_result/ex_user_card` only and still crashed
  in `_AnmGachaLakeBall::setPropertyValues`, with stack evidence through `_CPlayer::getUserCard(...)`; conclusion:
  the drawn card serial must also be present in response `your_data.owner_card_list`.
- Gacha result-page acceptance: built `work/librooneyj-gacha-cardget-inner-touch-nullguard.so` from the accepted
  exploration lib and promoted it into the unique client baseline. `flow -Scenario gacha-result-smoke -Tag
  gacha-result-baseline-accepted-1` passed without experiment parameters; `summary.json` reports pass, route sequence
  reaches `/connect/app/gacha/select/getcontents -> /connect/app/gacha/buy`, and `screenshots/gacha-result-after-touch.png`
  proves the local result-page transition after tapping the draw-card touch screen. The earlier broad
  `work/librooneyj-gacha-touchscreen-nullthis-guard.so` is not accepted despite passing because it guards every
  `_AnmTouchScreen::getSelected` call.
- Gacha result-page back acceptance: `work/kssma-flow-gacha-result-back-smoke-gacha-result-back-4` passed. It reuses
  the accepted draw/result path, taps the visible back button on `layout_gacha_drawresult`, receives
  `/connect/app/gacha/select/getcontents`, and screenshots the select page after return. Prior failed runs were
  runtime/tooling noise, not gameplay evidence: `gacha-result-back-1` stopped at `restart-boot-timeout`, and
  `gacha-result-back-2` stopped because `gacha-draw-after-route.png` was zero bytes before screenshot retry was added.
- Gacha baseline exploration regression: after rebuilding `work/client-baseline/KSSMA-Re-client-baseline.apk` with
  native lib SHA `DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`, `flow -Scenario
  exploration-smoke -Tag gacha-baseline-regression-exploration-1` passed. It proves the new client baseline did not
  regress accepted exploration hierarchy: `/exploration/area -> /exploration/floor area_id=0 ->
  /exploration/get_floor area_id=0 floor_id=2 -> /exploration/area -> /exploration/floor area_id=0 ->
  /exploration/get_floor area_id=0 floor_id=2`, with no fatal/resource-miss logcat.
- Gacha real settlement and deck readback accepted: `flow -Scenario gacha-settlement-deck-smoke -Tag
  gacha-settlement-deck-1` passed on ARM19. The artifact-local save starts with 400 friendship points, then
  `/connect/app/gacha/buy product_id=1 bulk=1 auto_build=1` logs `source="gacha buy settlement"`,
  spends 200 friendship points, persists card `serialId=2/masterCardId=9`, increments `stats.cardsDrawn` to 1,
  and appends one `gacha.history` entry. The same run returns to main menu and enters
  `/connect/app/roundtable/edit move=1`; response metadata reports `ownerCardSerialIds=[1,2]` and
  `ownerCardMasterCardIds=[22,9]`, proving the deck/roundtable entry reads the settled player card data.
  Artifact: `work/kssma-flow-gacha-settlement-deck-smoke-gacha-settlement-deck-1`.
- Gacha select real-pack ratio page accepted as the current direction: the previous generated `gac_*` alias resources
  and inpainted blank-banner attempt were rejected after visual review because they were self-made and did not respect
  the page regions. `server/data/game/gacha.json` now follows bundled `local_gachaselect.xml` y anchors and uses only
  original resources decoded from `work/million_cn/apktool/assets/pack/161/gacha/gacha0_1.pack`:
  `gacha_event_button`, `gacha_compsheet`, `gacha_free_0`, and `gacha_cp_button`. `work/extract-gacha-pack-resources.py`
  only decrypts/re-encrypts original PNG chunks; it does not draw or repaint assets. The `gacha_free_0_1204` /
  `gacha_cp_2` page version was functionally runnable but visually rejected because it made the entry page look
  crowded and poster-like. Evidence card: `work/gacha-select-resource-ratio-card-20260702.md`.
- Gacha button-ratio runtime accepted: `flow -Scenario gacha-paid-settlement-deck-smoke -Tag
  gacha-button-ratio-fix-5` passed on ARM19. Artifact:
  `work/kssma-flow-gacha-paid-settlement-deck-smoke-gacha-button-ratio-fix-5`. The run pushed
  `gacha_event_button`, `gacha_compsheet`, `gacha_free_0`, and `gacha_cp_button`, opened the same-page select,
  scrolled to the paid slot, reached `/connect/app/gacha/buy product_id=2
  bulk=0 auto_build=0`, spent 300 MC, persisted card `serialId=2/masterCardId=9`, returned to main menu, and
  `/roundtable/edit move=1` read owner cards `[1,2]` / master cards `[22,9]`.
- Gacha select layout HTML check accepted: `work/render-gacha-select-layout-html.py --check` translates the
  current `server/data/game/gacha.json` and bundled `local_gachaselect.xml` into
  `work/gacha-layout-html-check/gacha-select-layout.html`, copies the real PNG assets into that artifact, and
  fails on missing images, overflow, or image overlap. It found the previous raw-anchor mapping was objectively
  broken: `gacha_compsheet @ y=128` overlapped `gacha_free_0 @ y=168` by `504x48`, and `gacha_free_0 @ y=168`
  overlapped `gacha_cp_button @ y=288` by `624x40`. Current mapping keeps the same original pack images but moves
  `gacha_free_0` to `y=220` and `gacha_cp_button` to `y=396`; static/browser check reports `current_overlaps=0`.
  Browser screenshot: `work/gacha-layout-html-check/browser-layout-fixed-assets.png`. Server self-check now runs
  this layout check. Runtime artifact `work/kssma-flow-gacha-paid-settlement-deck-smoke-gacha-layout-html-fix-2`
  reached the core paid route, result/back, mainmenu return, and `/roundtable/edit move=1` readback, but the outer
  command timed out during final deck screenshot capture, so it is route evidence rather than a clean pass summary.
- Gacha select manual layout editor added after human visual rejection of the automatic layout direction:
  `python .\work\render-gacha-select-layout-html.py --editor` writes
  `work/gacha-layout-html-check/gacha-select-layout-editor.html`. Correction: `layout_gacha_select.xml` is the outer
  select-box/page layout, not the per-entry image content; it supplies the `xml_viewer frame_w=400` client logical
  viewport. Slots and coordinates are locked to `local_gachaselect.xml`, and the decoded 2x PNG candidates are previewed
  at inferred display scale `0.500`. The editor supports fixed-slot image replacement and export only; no coordinate
  dragging/nudging and no product data mutation until a human-approved export is applied. Browser verification loaded 4
  slots at 400px logical width, 6 placements, 25 candidates, and the export kept XML coordinates such as ticket
  `x=8,y=8`, ticket text `x=30,y=12`, paid image `x=8,y=288`, and paid text `x=140,y=292`. The strict XML preview
  currently exposes a 4px overlap between selected `gacha_compsheet` and `gacha_free_0` candidates, so the remaining
  work is manual candidate choice rather than moving slots. Screenshot:
  `work/gacha-layout-html-check/gacha-select-layout-editor-scaled.png`.
- Gacha rest decryption supersedes the manual-fit direction as the next evidence frontier:
  `python .\work\decrypt-gacha-rest-evidence.py` now decrypts and classifies the first-party rest files. `ae_gacha`
  and `ae_gacha02` decrypt with `k1` to PNGs; `rja_ae_gacha.load` lists `ae_gacha.png`, `cmn_bg_01.png`,
  `ae_gacha02.png`; `rja_ae_gacha` parses as `.AE` with 29 records and 27 atlas sprites. `rja_ae_gacha_slot`
  parses as a small `1000_common_button_.png` slot animation and is not the select-list layout. `rule_resource.xml`
  plus `layout_gacha_select.xml` show the select page has scene-owned `ae_gacha` chrome and a server-driven
  `xml_viewer y=50 frame_w=400`; the scrolling product list still needs server XML evidence. Evidence card:
  `work/gacha-rest-layout-evidence-card-20260706.md`; preview sheet:
  `work/gacha-rest-decrypt/rja_ae_gacha_sprites_sheet.png`.
- Gacha rest-select trial accepted as the current runnable page shape: `server/data/game/gacha.json` now keeps the
  select XML to two original-resource entries, `gacha_free_0` for friendship and `gacha_cp_button` for paid MC, and
  `work/kssma-runtime-flow.ps1` syncs the scene-owned rest resources `ae_gacha`, `ae_gacha02`, `rja_ae_gacha`, and
  `rja_ae_gacha.load` before gacha flows. `node .\server\test-bootstrap-server.js`,
  `flow -Scenario gacha-draw-smoke -Tag gacha-rest-select-trial-2`, and
  `flow -Scenario gacha-paid-settlement-deck-smoke -Tag gacha-rest-select-paid-2` passed. Key artifact:
  `work/kssma-flow-gacha-paid-settlement-deck-smoke-gacha-rest-select-paid-2`; screenshots
  `open-gacha-select.png` and `gacha-paid-confirm.png` show the restored `ae_gacha` chrome, real friendship banner,
  MC button, and Chinese confirmation dialog. The first paid trial failed only because the flow tap landed above the
  visible button; moving the paid tap to the button center fixed it. This does not prove separate friendship/paid pages;
  no client page-switch route has been recovered yet.
- Paid gacha retry accepted: `flow -Scenario gacha-paid-retry-smoke -Tag paid-retry-2` passed on ARM19 with artifact
  `work/kssma-flow-gacha-paid-retry-smoke-paid-retry-2`. The artifact-local save starts at 600 MC. Route order is
  `/gacha/select/getcontents -> /gacha/buy product_id=2 bulk=0 auto_build=0 -> /gacha/buy product_id=2 bulk=0
  auto_build=0`; the retry confirmation visual diff is `86.3`. The second response reports `mcBefore=300`,
  `mcAfter=0`, `drawnSerialId=3`, `ownerCardCount=3`, and `cardsDrawn=2`. The draw-to-result edge emitted no route,
  `gacha-paid-retry-result.png` visibly shows the second result page (`diff 65.62`), the client stayed alive, and the
  final save is `MC=0`, card serials `[1,2,3]`, two product-2 history entries, and `cardsDrawn=2`. The first attempt,
  artifact `work/kssma-flow-gacha-paid-retry-smoke-paid-retry-1`, stopped before gameplay with
  `wrong-runtime-only`; `start-runtime` restored the absent ARM19 AVD and `fast-health` reconfirmed
  `armeabi-v7a / 4.4.2 / boot=1`. It is runtime evidence only, not a failed retry hypothesis.
- Deck-builder entry path statically recovered in `work/roundtable-edit-native-schema-card-20260809.md`.
  `_TownModel::card -> _CircleTableModel::edit -> connect(72)` emits `/roundtable/edit move=1`; the response parent
  is `roundtable_edit`, not `round_table`. Its direct fields are `ex_gauge:int`, `leader_card:<single owned serial>`,
  and `deck_cards:<12 comma-separated owned serial/empty slots>`. `_DeckScene::initModel` consumes this body; scene
  `10100` only opens
  `_RoundTableScene`, whose update handles back and card detail but no edit action. Existing save state is the only
  value source: `cards.activeDeckId`, matching `cardInstanceIds`, and `profile.leaderSerialId`, padding to 12 with
  `empty`. Save is a later edge: connect id 74 maps to `/cardselect/savedeckcard` with request keys `C` and `lr`.
- Deck-builder D1 runtime accepted: hypothesis was that the statically recovered `<roundtable_edit>` contract would
  drive the original editor without a native or resource change. Command: `powershell -NoProfile
  -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario deck-builder-entry-smoke -Tag
  deck-builder-entry-1`. Artifact
  `work/kssma-flow-deck-builder-entry-smoke-deck-builder-entry-1` passed on `emulator-5556`: request params are exactly
  `move=1`, response metadata is `command=round_table / nextScene=83200`, screenshot diff from main menu is `68.86`,
  and `deck-builder-entry.png` visibly shows the 12-slot deck rail plus `decide/leader/create_deck/back` controls.
  The RooneyJ activity stayed alive with no fatal or resource-miss evidence. The flow now also requires a fixed
  1280x720 DeckScene color signature; the accepted screenshot passes it and the main-menu screenshot is rejected.
  Conclusion: D1 is closed and the `scene 10100` editor assumption is deprecated. Next frontier is D2's local leader
  mode transition only; no save request or persistence was attempted.
- Deck-builder D2 first invocation stopped before gameplay: `flow -Scenario deck-builder-leader-mode-smoke -Tag
  deck-builder-leader-mode-1` produced artifact
  `work/kssma-flow-deck-builder-leader-mode-smoke-deck-builder-leader-mode-1` with
  `failureClass=runtime-not-ready`, `failureStep=repair-adb`, and `restart-boot-timeout`. The event log contains no
  login or gameplay route and no leader tap; it shows a detached ARM19 classification followed by the permitted warm
  restart. A failure screenshot became available after the timeout, so ADB was returning while cleanup ran. This is
  runtime-only evidence, not a failed D2 leader-mode hypothesis; check `fast-health` once before any gameplay retry.
- Deck-builder D2 runtime accepted after that one health recovery: `fast-health` confirmed `emulator-5556` as
  `armeabi-v7a / 4.4.2 / boot=1`, then `flow -Scenario deck-builder-leader-mode-smoke -Tag
  deck-builder-leader-mode-2` passed. Artifact
  `work/kssma-flow-deck-builder-leader-mode-smoke-deck-builder-leader-mode-2` contains only the login chain and
  `/roundtable/edit move=1`; the cursor-scoped three-second window after tapping `(1090,270)` contains no
  `connect_app_probe`. `deck-builder-leader-before.png -> deck-builder-leader-after.png` has diff `37.89`; the after
  image visibly keeps the left card rail active while dimming the status panel and all four right controls, exactly
  matching layout behavior `change_mode_leader_select` plus disabled `grp_button`. The client stayed alive. A fixed
  1280x720 leader-mode signature accepts this after image and rejects both the normal DeckScene and main menu.
  Conclusion: D2 is closed without selecting a card or touching save; D3 is static-only path recovery.
- Deck-builder D3 static path accepted: raw Thumb mode table bytes at `0x002b5950` are `52 29 02 91`, mapping mode 0
  to the clip-37 entry button and mode 1 to the card-list/reverse-button path. Clip 37 returns code 5; DeckScene maps
  it to `slider_right` and `change_mode_card_sel`. With owned `[1,2]` and active deck `[1]`,
  `_DeckCardList::checkDeck` removes serial 1, leaving serial 2 as the sole index-0 candidate. Its exact device-center
  tap is `(226,247)`. `_DeckStage::setCardAtBlankOnDeck` writes it into the first empty slot and stays in card mode.
  Decrypted clip-38 geometry yields reverse tap `(1144,360)`; it returns code 6, which DeckScene maps to `slider_left`
  and normal deck mode. Generic slider action/task tracing proves no persistent 230/480 offset. Clicking an empty slot
  as entry, automatic return after selection, and scene `83100` are explicitly rejected. No runtime or save mutation
  was performed in D3. Next frontier: D4 one-card in-memory edit flow.
- Deck-builder D4 first invocation stopped before gameplay: `flow -Scenario deck-builder-edit-smoke -Tag
  deck-builder-edit-1` produced artifact
  `work/kssma-flow-deck-builder-edit-smoke-deck-builder-edit-1` with `failureClass=runtime-not-ready`,
  `failureStep=repair-adb`, and `restart-boot-timeout`. `fast-health` first reported `adb-transport`; the permitted
  detached-ARM19 warm restart then missed its boot window. The route sequence is empty and no deck tap or screenshot
  was produced, so this is runtime-only evidence rather than a failed D4 edit hypothesis. Run `fast-health` once and
  replay the same scenario only if `emulator-5556` has reached the accepted ARM19 baseline.
- Deck-builder D4 runtime accepted after short-link ADB recovery: `repair-adb` restored the same AVD by reconnect and
  confirmed `emulator-5556 / armeabi-v7a / 4.4.2 / boot=1`; no second restart was needed. `flow -Scenario
  deck-builder-edit-smoke -Tag deck-builder-edit-2` then passed with artifact
  `work/kssma-flow-deck-builder-edit-smoke-deck-builder-edit-2`. The route sequence contains only login and
  `/roundtable/edit move=1`; each of `(127,360)`, `(226,247)`, and `(1144,360)` had a cursor-scoped three-second
  window with no `connect_app_probe`. Screenshots prove serial 2 appears as the sole candidate, disappears after
  selection while mode 1 remains visible, and then occupies normal DeckScene slot 1 after the explicit reverse tap.
  Relational scores were `candidateEnter=102.42`, `candidateLeave=80.52`, `returnTab=0`, `slot0=0`, and
  `slot1=91.5`. The final artifact save SHA-256 remained
  `8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`, with persisted deck `[1]`, leader `1`,
  owner serials `[1,2]`, and empty gacha history. D4 is closed; D5 may capture the decide request but must not persist
  or guess a success response before the native/request value domains are closed.
- Deck-builder D5 capture accepted: `flow -Scenario deck-builder-save-smoke -Tag deck-builder-save-1` passed with
  artifact `work/kssma-flow-deck-builder-save-smoke-deck-builder-save-1`. After the complete accepted D4 edit, decide
  `(1090,95)` emitted exactly one `/connect/app/cardselect/savedeckcard` request with case-sensitive parameter set
  `{C,lr}`: `C=1,2,empty,empty,empty,empty,empty,empty,empty,empty,empty,empty` and `lr=1`. No duplicate or follow-up
  request appeared. The server returned only the existing generic `save_deck / nextScene=83200` empty-body
  placeholder. Twenty-eight seconds after that response the client was alive on the same populated DeckScene;
  decide-before/response screenshot diff was only `0.05`, so the static default-zero `back()` possibility did not
  become a visible return in this run. The artifact save remained byte-identical at SHA-256
  `8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`, still persisted deck `[1]` / leader `1`.
  Native recovery proves explicit `result=0` is the only return branch and any nonzero result stays/unlocks, but no
  repository sample supplies an original `<save_deck_card>` success body, a nonzero code/message pairing, or a
  reachable app-level error dialog. D5 closes request capture only; D6 must not invent those semantics.
- Deck-builder D5.5 explicit-success candidate rejected: `flow -Scenario deck-builder-save-smoke -Tag
  deck-builder-save-result0-1` produced artifact
  `work/kssma-flow-deck-builder-save-smoke-deck-builder-save-result0-1`. The exact D4 path passed first, then decide
  emitted one `/connect/app/cardselect/savedeckcard` with the accepted `C/lr` values. The server returned a formed
  `<save_deck_card>` parent with explicit `<result>0</result>`, echoed leader/deck, and log marker
  `source="deck save response-only" / saved=false`; no duplicate or follow-up route appeared and the RooneyJ activity
  stayed alive. Nevertheless `deck-builder-save-before.png` and `deck-builder-save-response.png` are visibly the same
  populated DeckScene and score only `0.05`, so the candidate did not exercise the predicted local `back()` edge.
  The artifact save stayed SHA-256
  `8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`, persisted deck `[1]`, leader `1`, and
  owner serials `[1,2]`. This is a product-hypothesis failure, not a threshold or runtime failure. The experimental
  response was removed from the baseline. Static postmortem corrected the missing dispatch condition:
  `_Main::connect` parses header `next_scene` at `0x001c35c4..0x001c35d0`, takes the nonzero branch at
  `0x001c3710`, and calls `_SceneControl::push(nextScene, parser)` at `0x001c3888`. The resulting new
  `_DeckScene::initModel` at `0x0033c6c8` recognizes only `roundtable_edit`, not `save_deck_card`, so this response
  never reaches `_CircleTableModel::update`; only a response retained by the current scene can reach the proven
  state-3/result-zero `back()` tail.
- Deck-builder D5.6 static gate closed before the response experiment: `_HeaderTagParser::parse` initializes
  `HeaderTagData+8` to zero and only overwrites it for an explicit `next_scene`; `_Main::connect`'s zero branch skips
  scene push and returns the response body through `_Main::update` to the pre-connect current `LayoutScene`.
  `_DeckScene::ConnectSave::exec` has already installed the save-state `_CircleTableModel` as that scene's pending
  model; `LayoutScene::task` dispatches the body to `_CircleTableModel::update`, after which DeckScene state 3 reads
  result zero and calls `LayoutScene::back()`. Accepted artifact
  `work/kssma-flow-exploration-forward-visual-smoke-no-next-scene-visual` independently exercises the same generic
  no-`next_scene` current-model path: the existing exploration scene visibly changed from 50% to 55% and rendered
  its reward overlay. The old "zero-scene delivery is unclosed" frontier is retired. The only authorized D5.6
  product variable is to replay the unchanged explicit `save_deck_card/result=0` body and echo while omitting
  `next_scene`; the server must remain response-only and the artifact save byte-identical. This is a local client
  compatibility probe, not evidence of the original server's success/error contract and not authorization for D6.
- Deck-builder D5.6 first and only runtime invocation stopped before gameplay: `flow -Scenario
  deck-builder-save-smoke -Tag deck-builder-save-current-model-1` produced artifact
  `work/kssma-flow-deck-builder-save-smoke-deck-builder-save-current-model-1` with
  `failureClass=runtime-not-ready`, `failureStep=repair-adb`, and `restart-boot-timeout`. Initial fast-health failed
  as `adb-transport`; the permitted detached-ARM19 warm restart did not reach the boot deadline. The route sequence
  is empty, the activity service was unavailable, and the only screenshot is a black cleanup-time failure frame.
  No login, D4 action, save request, response marker, or current-model UI observable occurred. The seeded artifact
  save remained SHA-256 `8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`.
  This run neither accepts nor rejects the no-`next_scene` hypothesis. In accordance with the one-run stop rule,
  the D5.6 response-only server/test and strict flow/docs experiment was removed, restoring the D5 capture-only
  product baseline. The next round is runtime health recovery only; do not vary XML or implement persistence.
- ARM19 calibration C1 accepted: the single `fast-health` invocation wrote
  `work/kssma-runtime-calibration-health-1/summary.json` and returned `ok=true`, `command=fast-health`,
  `serial=emulator-5556`, `abi=armeabi-v7a`, `release=4.4.2`, and `bootCompleted=1`; all three `getprop` stages
  succeeded. No connect, repair, restart, server, flow, login, baseline, APK, or product action ran. This accepts the
  current live runtime only. C2 is the next bounded round; D5.6 and D6 remain frozen.
- ARM19 calibration C2 stopped on an invalid sampler: the one authorized `restart-runtime -Force -Reason
  "calibrate ARM19 warm boot readiness after 120s timeout"` invocation created the new process group
  `emulator.exe 10620 -> emulator-arm.exe 24456`, but artifact
  `work/kssma-runtime-calibration-warm-boot-1` ended with `decisionClass=calibration-error`,
  `measurementOk=false`, and `caughtError="Bounded netstat listener query failed or timed out."`. Only the first
  sample completed (`0.953s..4.789s`); the second bounded listener query exceeded its two-second cap, so the observer
  stopped and terminated only its helper PowerShell process. It did not run a second restart or repair and did not
  start server, flow, login, baseline, APK, or product work. `oldDeadlineCrossed=false`; no `tIdentity`, `tBoot`, or
  stable confirmation was measured, so this artifact cannot classify the boot as within/after 120 seconds and cannot
  justify any timeout change. The recorded `tShell=4.789` is also invalid: ADB returned exit code zero with empty
  stdout and `device 'emulator-5556' not found` on stderr. Retire both bad probes before any future C2 measurement:
  listener acquisition needs a bounded method that tolerates host boot load, and shell success must reject ADB error
  stderr/empty values. The next round is static calibration-tooling correction only; D5.6 and D6 remain frozen.
- ARM19 calibration C2-A/C2-B accepted and supersedes the invalid warm-boot-1 measurement. The corrected one-shot
  sampler in `work/kssma-runtime-calibration-warm-boot-2/run-calibration.ps1` uses an eight-second bounded listener
  query and accepts ADB/getprop output only when the child did not time out, exited zero, emitted nonempty exact
  stdout, and emitted no ADB-error stderr. Its `-SelfCheck` passed 13 cases without starting or querying an emulator.
  The single authorized C2-B command then produced ignored artifact
  `work/kssma-runtime-calibration-warm-boot-2`: `decisionClass=healthy-within-120`, `measurementOk=true`,
  `tShell=tIdentity=43.013s`, first complete boot sample `tBoot=102.733s`, and stable confirmation at `122.529s`.
  The helper itself returned `ok=true` after `104.449s`; the new process group was uniquely
  `emulator.exe 44176 -> emulator-arm.exe 55020`, both ports `5556/5557` were bound to PID 55020, and no restart,
  repair, flow, server, login, baseline, APK, or product action followed. Conclusion: retain the existing 120-second
  restart wait and unfreeze exactly one D5.6 current-model response run; warm-boot-1 remains rejected evidence.
- Deck-builder D6-S native/data gate is closed in
  `work/deck-builder-save-capture-native-path-card-20260809.md`. `_DeckStage::sortDeck` moves only wholly empty
  three-slot groups to the suffix and preserves holes inside partial groups. `DeckUtil::checkDeck` requires a
  non-empty owned leader in `C`, rejects repeated character ids, and requires total card cost `<= CPlayer::getMaxBc`.
  The accepted `master_card` SHA-256 `7B121D...B3A56BDF` parses exactly as 480 records; every
  `characterId == masterCardId`, character ids are unique, and costs are positive `[2,99]` (master 22 cost 10;
  master 9 cost 3). `work/generate-card-master-data.js --check` pins that schema/hash and verifies the clean
  `server/data/game/card-master.json` byte-for-byte. The max-BC native chain ends at the same
  `<your_data><bc><max>` value emitted from `playerSave.resources.bc.max`. D6 must resolve every owned serial through
  this table, reject unknown/repeated-character/over-cost input with zero mutation, and persist accepted slot positions
  exactly; no bootstrap loader or persistence behavior was added in D6-S.
- Deck-builder D5.6 second and only product invocation for the corrected runtime round failed its explicit
  route-quiet contract. `flow -Scenario deck-builder-save-smoke -Tag deck-builder-save-current-model-2` produced
  artifact `work/kssma-flow-deck-builder-save-smoke-deck-builder-save-current-model-2`. The accepted D4 replay
  completed first with unchanged save; decide then emitted exactly the captured
  `C=1,2,empty,empty,empty,empty,empty,empty,empty,empty,empty,empty / lr=1` request. The server returned the exact
  no-`next_scene` `save_deck_card/result=0` probe at event 25 with `saved=false`, but 165ms later the client emitted
  `/connect/app/mainmenu` at event 26. The flow stopped at `deck-builder-save-response-route-quiet` with
  `failureClass=unexpected-route` before accepting any screenshot claim. The artifact save remained byte-identical
  at SHA-256 `8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`. This is a real current-model
  observable, but the bounded hypothesis required zero follow-up routes, so it is rejected rather than
  reinterpreted. The response-only server/strict-flow experiment is removed again, D5 capture-only remains the
  product baseline, and D6 persistence is frozen. Do not relax the gate or try another XML in this round.
- Historical Gacha G1 stop (superseded by the accepted 2026-08-19 producer-edge restoration); details are in
  `work/gacha-buy-failure-schema-card-20260810.md`. Parser-minimum header error data and `code=1` reaching the generic
  `_Main::connect` type-2 DialogModel branch are closed, as are the dialog scene's eventual tap/pop semantics once
  such a scene exists. The missing production edge is the call from that generic error branch to
  `LayoutScene::showDialog` or `_SceneControl::push(90100)`. Without it, no evidence proves a visible rejection
  dialog, return to `GachaDrawResult`, or route quiet. The candidate XML is not implemented; G2 product, mode, and
  balance rejection remain frozen rather than guessing a wire error contract.
- Local admin M1 is accepted as a server-only tool. `/admin/` exposes a KSSMA-styled status/player page; its API
  writes only validated profile/resource/currency/ticket/capacity scalars through the existing atomic save path,
  keeps exploration/cards/decks read-only, and requires loopback or `KSSMA_ADMIN_TOKEN`. The full server self-check
  and a real-browser 639px no-overflow render passed without changing gameplay XML, native code, or the real save.
  Evidence: `work/admin-console-m1-card-20260816.md`; roadmap: `docs/local-revival-roadmap.md`.
- A12 card-master bounded classifier absence inference is rejected by the subsequent exact-path capture. The
  revision-232 response selected exact recovered ids 9/22/600, contained three records, and was 5,568 encrypted
  bytes, but neither `save_version` nor an external card table changed. A temporary DEX path logger on the next
  login/reproduction proved fairy serial 100012 still entered
  `JResourceLoader.loadFile -> loadBitmap -> TextureLoader.loadTexture` with exact path
  `save/download/image/adv/adv_chara0`, then aborted at `GetObjectClass(null)`. The earlier run's lack of printed
  `adv_chara0` was incomplete log evidence, not in-memory card-manager acceptance; the adjacent MediaPlayer
  transition is not the root cause. The XML responses did not prevent the downstream null card, but external
  `database/master_card` absence is no longer treated as rejection evidence: the earlier accepted A12 deployment
  already records that the client removes this preload after reading it. Native recovery closes the callback as
  `clearMasterCardList -> updateMasterCardList -> serializeMasterCardList` and closes direct XML children
  `update_type`, repeated `card`, and `imagedl_list`; `_CardTagParser` directly recognizes
  `master_card_id`, `country_id`, and the remaining emitted native field names. The next bounded classifier restores
  the accepted serialized cache (device/source SHA-256 `7B121D...B3A56BDF`) before process start and removes the
  diagnostic revision override. A missing `adv_chara0` will move the fix to repeatable A12 launch-time master-table
  restoration; the same exact path will end this branch and move to battle user-card binding. Do not create a fake
  image zero or continue resource/audio/XML-field work. Evidence:
  `work/master-card-update-schema-card-20260818.md` and
  `work/mumu-a12-texture-null-path-live-20260818/`.
- A12 texture-null classifier is complete. Static JNI recovery showed the accepted native library's only direct
  `GetObjectClass` calls are in
  `jni_loadTexture` (`0x001b0fd0`) and `jni_loadTextureWithRect` (`0x001b1192`), immediately after Java
  `TextureLoader` returns. Device hashes for flow-relevant `adv_chara9/22/600/5009/5022/5600` and
  `boss_full600/5600` exactly match the recovered package; all decrypt into valid PNGs, so bulk resource reinstall
  is rejected. The builder's opt-in `KSSMA_TEXTURE_PATH_DIAGNOSTIC=1` mode verifies the stock DEX hash, redirects
  only the two silent same-signature path logs to `Debug.err`, recomputes both DEX header checks, and records the
  diagnostic in the unique baseline manifest. Parsed patched DEX self-check passed and A12 install preserved the
  accepted native SHA-256. The one authorized reproduction identified ordinary `loadTexture(String,float)` and
  exact `adv_chara0`; restore the normal baseline before a product fix. Evidence:
  `work/a12-texture-null-path-card-20260818.md`.
- The first A12 battle to survive into the result screen rejects the old winner-index inference. Fairy serial
  `100013` was a real local victory: server and persisted save agree on fairy HP `9660 -> 0`, player HP
  `5620 -> 3220`, `playerWon=true`, Gold `4620 -> 4920`, EXP `34 -> 39`, and `wins +1`; nevertheless the response's
  `<winner>0</winner>` visibly rendered `YOU LOSE`. Therefore the result scene treats `winner` as a local-result
  flag: `1=local victory`, `0=local defeat`. The server mapping, API assertions, flow fixture/gate, and settlement
  schema are updated together; gameplay rewards and persisted win/loss calculation remain driven by `playerWon`.
  The user then confirmed the corrected replay as “战斗正常、结算正常”.
- Fairy battle BC debit is accepted on the funded success path. Contemporary deck guides and the recovered
  480-card master table close the local rule as the sum of the active deck's card COST values. The server now checks
  before mutation and commits BC, battle, reward, fairy state, counters, and history through the same atomic save;
  the default card `22` costs `10`. MuMu A12 `fairy-battle-smoke / mumu-a12-bc-deduction-acceptance` passed in
  `139006 ms`: response, header, saved BC, and history all agree on `25 -> 15`, active fairy became null, the client
  showed `YOU WIN`, returned to exploration with a visible `15/25` BC gauge, continued to
  `/exploration/get_floor`, and server stderr/fatal scan were clean. Server self-check also proves
  `9/10` returns fail-closed HTTP 409 without changing BC, active fairy HP, wins, or history. This 409 is only a
  trust-boundary guard: the client resource contains the correct `*_no_bc` behaviors, but accepted native
  `BcCheck/BcCheck2` always select `*_max_bc` and `isBcFull()` returns true. The visible shortage path remains the
  next native frontier; do not invent error XML. Evidence: `work/fairy-battle-bc-card-20260819.md`.
- The exact pre-start cache that let serial 100013 cross `adv_chara0` is now a repeatable MuMu A12 controller
  contract. Resource manifest schema 2 pins 260,249 bytes and SHA-256
  `7B121DE5626DD3B9820022C698A1FF754F87CAC4B64E563B70138F68B3A56BDF`; `install-client`, `launch`, and the A12
  flow gate stop the process, restore only a missing/different target, verify it, and only then permit startup.
  A real missing-file fault injection made normal `launch -StartServer` report `restored=true`, then PID 3012
  remained in `RooneyJActivity`, the normal main menu screenshot rendered, and logcat had no zero-card texture or
  fatal signal. The test backup was removed after equal-hash verification. `status` still ignores the consumable
  file and uses persistent sentinels. Direct MuMu icon launches remain outside controller protection; use
  `repair-master-card` first when manual icon startup is required. Evidence:
  `work/mumu-a12-master-card-launch-seed-card-20260819.md`.

## Fresh-clone startup asset closure

- Frontier: a Git clone could not start because accepted native bytes, XML overlays, layout fixtures, game files, and ARM19 machine state were implicit local dependencies.
- Hypothesis: keep only 4.37 MiB of accepted project artifacts in Git; rebuild ignored runtime assets from the two archive.org files and create the AVD skeleton from a separately supplied classic ARM SDK.
- Changed one variable: documented the first-run path, added stdlib-only asset preparation, made debug-keystore and AVD skeleton creation automatic, and removed layout-check dependence on a pre-existing apktool tree.
- Server check: `prepare-assets.py` passed, layout check reported `current_overlaps=0`, and `node server/test-bootstrap-server.js` printed `bootstrap-server self-check passed`.
- ARM19 check: transport self-check passed 6/6 and existing-AVD `configure` passed; full preload stopped at the existing `wrong-runtime-only` guard because unrelated Android devices were online.
- Observed: baseline rebuilt with accepted lib SHA-256 `DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`.
- Conclusion: Git needs 4.37 MiB of previously ignored project artifacts; external distribution still needs the two game files plus an approximately 1.55 GiB self-contained `Sdk-classic-arm` package, not the 9.6 GiB machine-state AVD. The local SDK used junctions, so naive recursive copying is invalid.
- Next: validate the documented first-run sequence on a clean Windows device with no other emulator online.

## Fresh-device baseline install branch

- Frontier: fresh ARM19 with the package removed could not complete `ensure-client-baseline`.
- Hypothesis: the helper called installed-lib verification before its existing package-missing install branch could run.
- Changed one variable: check package presence first and reuse `Invoke-InstallClientBaselineApk` directly when absent.
- Observable: `ensure-client-baseline` on the same fresh emulator must install the generated APK and verify installed `librooneyj.so` SHA-256.
- Intermediate result: after `preload-full`, the 1.5 GiB data partition had only 490.9 MiB free versus 546.5 MiB required for first install; README order was corrected to install before preload.
- Result: after removing the rebuildable stash, fresh install completed in 229.991s with installed/source lib SHA-256 `DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`; re-preload pushed 6895 files / 517055607 bytes and final baseline passed.
- Startup observable: fresh-clone server listened on `50005,10001`, client package launched on fresh ARM19, and `work/kssma-runtime-fresh-clone-startup.png` showed the original visible mode-select screen.
- Conclusion: the documented fresh-clone sequence is accepted through visible client startup; first install must precede full resource preload.

## Official Android 4.4 ARM setup automation

- Frontier: fresh developers still needed a manually distributed `Sdk-classic-arm` directory.
- Hypothesis: the accepted runtime can be reconstructed from immutable Google Android repository archives rather than a project-owned environment package.
- Changed one variable: added `work/setup-android44-arm.ps1`; README now requires explicit SDK-license acceptance and runs this installer.
- Sources: `tools_r25.2.5-windows.zip` (306785944 bytes, official SHA-1 `A7F7EBEAE1C8D8F62D3A8466E9C81BAEE7CC31CA`, SHA-256 `DA1A0BD9BB358CB52A8FC0A553A060428EFE11151E69B9EA7A5CBACB27CF1C7C`) and `sys-img/android/armeabi-v7a-19_r05.zip` (159871567 bytes, official SHA-1 `D1A5FD4F2E1C013C3D3D9BFE7E9DB908C3ED56FA`, SHA-256 `CA7440CADE53D829A8CACE857CFAD9AFAA174C286D1B7A5D139E73CFCFDE45D7`).
- Checks: setup self-check passed; missing license acceptance was rejected; isolated install verified four accepted file SHA-256 values; repeated install was idempotent; a second clean profile installed the runtime and `configure` created `kssma_arm19` plus the 4 GiB SD card.
- Conclusion: maintainers no longer need to redistribute a 1.55 GiB Android environment package. Google downloads total about 445 MiB and expand into the existing `%LOCALAPPDATA%/Android/Sdk-classic-arm` contract.

## Isolated README cold-start validation

- Frontier: prove the documented setup works from a new clone and isolated Windows profile without reusing the existing project's assets, SDK, AVD, cache, or keystore.
- Hypothesis: the only remaining host-state conflict was `ensure-runtime` refusing to start `kssma_arm19` when unrelated Android devices were online even though ports `5556/5557` were free.
- Changed one variable: allow a new classic runtime only for `adb-transport` or `wrong-runtime-only`, with no target process and both dedicated ports free; other devices are never stopped or controlled.
- Check: transport self-check passed 10/10, including other-device/free-port acceptance and occupied-target-port rejection.
- Cold evidence: a fresh clone under `KSSMA-Re-readme-validation-20260814` used an isolated `USERPROFILE`/`LOCALAPPDATA`; both archive.org game files and both official Google runtime archives were downloaded again, hashes passed, and the isolated runtime installed without an external SDK package or existing AVD.
- Rejected run: although the emulator executable came from the isolated SDK, process/file timestamps proved classic emulator had resolved `kssma_arm19` from the pre-existing global AVD home. Its installed client predated this run, so the otherwise healthy login/main-menu observable was contaminated and is not accepted as cold-start evidence.
- Correction: classic emulator r25 ignores the newer `ANDROID_AVD_HOME`; `Start-ClassicEmulator` now temporarily supplies its documented `ANDROID_SDK_HOME` and `ANDROID_EMULATOR_HOME`, then restores the caller environment. The next run created `userdata-qemu.img` and `cache.img` under the isolated profile, proving it no longer reused the global AVD.
- Isolated cold result: failed. The truly fresh instance reached the Android kernel and initialized `/data`, but `/cache` failed to mount, ADB remained `emulator-5556 offline`, and `ensure-runtime` hit its 240-second `boot-timeout`; another 90-second observation produced no state change. No client install, preload, baseline, or login claim from this run is accepted.
- Cache finding: the isolated and accepted global `cache.img` files are byte-identical (SHA-256 `C39628D11159632D1D5B20A1BDE5A0C96CC105EA2B4701DD80985FA6BC34D343`) and both pass `e2fsck -fn`; the kernel's `/cache` mount warning also remains in a successful cold boot. It is not the startup blocker.
- Accepted runtime fix: `configure` now copies the official initial userdata, expands it to 1536 MiB with the bundled `resize2fs.exe`, repairs the resize inode with bundled `e2fsck.exe -fy`, and requires a clean `e2fsck -fn` before first boot. This removes first-boot filesystem expansion from the emulator. Fresh `configure` created a clean 1610612736-byte image, and the same new isolated AVD passed `armeabi-v7a / 4.4.2 / boot_completed=1` on its first start. The cold-start wait is 360 seconds because this host completed near the old 240-second boundary.
- Deployment result: with no package initially installed, `ensure-client-baseline` completed the package-missing install and matched installed/source native SHA-256 `DEC36585...CD40F`; `preload-full` pushed 6895 files / 517055607 bytes; hosts, mounts, 1280x720/240 dpi, audio, and package baseline passed. A screenshot from this clean AVD shows the expected Mode Select page, proving no saved account/AVD state was inherited.
- Separate non-runtime frontier: `exploration-smoke` reached Mode Select, World Select, and LoginActivity but its ADB text driver timed out with only `1` in the phone field and no password. Two bounded runs produced no login route, so the attempted batching change was removed. Do not reinterpret this login-automation failure as an ARM19 cold-start failure.
- Conclusion: the off-book AVD/cache runtime blocker is resolved. The README deployment reaches a healthy, fully provisioned, visible fresh client from isolated downloaded inputs; automatic first-login driving remains a separate flow-helper issue.

## 2026-08-19 Fairy Drop And Gacha Pool Round

- Hypothesis: the accepted fairy reward-box and gacha result parsers can retain their XML/client paths while server
  settlement changes from one fixed card to snapshotted weighted pools.
- Changed one product variable: reward selection/settlement data. Fairy reward slots now roll an admin-controlled
  `0..100` drop percentage and then a snapshotted weighted card pool; gacha products 1/2/3/4 use fixed
  friendship-single/MC-single/ticket-single/MC-11-draw metadata with admin-controlled price and per-product pool.
- Observable/checks: `node .\server\test-bootstrap-server.js` passed deterministic weight-boundary, no-drop,
  contributor/finisher, four-currency/product, 11-serial, capacity/insufficient rollback, admin atomic-write, formal
  data, generated inline-script, encrypted HTTP, and gacha layout checks. `flow -Scenario self-check -Tag
  gacha-pool-selfcheck` passed and now asserts random results against the configured pool instead of master card 9.
  A live `/admin/` browser load rendered four product panels, the 70% fairy drop control, normalized pool text, and
  no console errors. The restarted manual server listens on both 50005 and 10001.
- Conclusion: server/admin behavior is accepted for this round; historical rates are not claimed. Existing live
  raids retain their old snapshot. New ticket and 11-draw client entry/result edges, and the visible insufficient
  balance dialog, remain client/native frontiers. Evidence: `work/fairy-gacha-pool-path-card-20260819.md`; flow
  artifact: `work/kssma-flow-self-check-gacha-pool-selfcheck/summary.json`.
- Final self-check exposed one account-session text-malleability edge: changing the final Base64URL character can
  sometimes decode to the same HMAC bytes because unused trailing bits are ignored. Session verification now rejects
  non-canonical Base64URL before timing-safe HMAC comparison; the full self-check then passed with the tampered Cookie
  returning 401 and neither account save changing.

## 2026-08-19 Gacha Insufficient-Balance Network-Dialog Round

- Hypothesis: the reported network dialog is not a transport outage; the live friendship draw reached
  `/connect/app/gacha/buy(product_id=1)` with `friendshipPoint=0`, settlement raised
  `GACHA_INSUFFICIENT_BALANCE` for the configured 200-point cost, and the common exception handler returned
  undecryptable plain-text HTTP 500.
- Observed result: live logs closed that exact chain while exploration and fairy routes continued normally. The
  settlement guard ran before any write, so no currency/card/save mutation occurred.
- Changed one response variable: only `GACHA_INSUFFICIENT_BALANCE` reuses the complete accepted encrypted
  `gacha_select / next_scene=9100` response and logs `gacha_buy_rejected`, required/available balance, and
  `saved=false`. It does not grant currency/card or claim the original insufficient-balance dialog contract.
- Check: `node .\server\test-bootstrap-server.js` passed HTTP 200/decryption, complete select model, absence of a
  buy result, byte-identical save, success-settlement regression, and full server regression. Client-visible return
  is still pending one user retry; stop after that observable rather than trying a second XML candidate. The
  replacement live server PID 38104 is fingerprint-clean and healthy on 50005/10001; a real encrypted product-1
  request against the live save returned HTTP 200, 11888 ciphertext bytes, `next_scene=9100 + gacha_select`, no
  `gacha_buy`, and an unchanged save SHA-256. Its log records `requiredCost=200`, `availableBalance=0`,
  `saved=false`.
- Evidence: `work/gacha-buy-insufficient-fallback-path-card-20260819.md`.
- Client acceptance: the user retried the deployed live client and confirmed the flow was normal. The compatibility
  fallback is accepted for eliminating the false network error; an original-style insufficient-balance dialog remains
  a distinct G1 frontier.

## 2026-08-19 Gacha Original Balance-Dialog Candidate Round

- Hypothesis: the parser and dialog consumer are already complete; the only missing edge is the generic code-1
  branch in `_Main::connect` failing to push stock `dialog_scene=90100` after
  `_DialogModel::initDialog(type=2)`.
- Static differential: the stock network-error path in the same function executes
  `_Main::getSceneControl -> _SceneControl::push(90100)`; gacha select and draw-result confirmation paths use the
  equivalent `initDialog -> LayoutScene::showDialog`. A server `next_scene=90100` is rejected because generic
  nonzero errors never execute the next-scene branch, and all three gacha scenes inherit an empty `preUpdate`.
- Changed one complete path: `build-gacha-business-error-dialog.py` gates error code `1`, restores the stock scene
  push, releases its temporary scene-control smart pointer, and returns to `0x001c3bae`. Source hash, original
  bytes, zero cave `0x003e7fa0..0x003e8050`, entry/return disassembly, and path map passed. Candidate SHA-256 is
  `36A4826BD42BCF203B51D0344AF5A1B479B961BD26DDB4685DD01A8B325B69A2`.
- Server candidate: with `KSSMA_GACHA_BUSINESS_ERROR_DIALOG=1`, insufficient friendship/MC/ticket purchases returned
  encrypted HTTP 200 with code `1`, respectively `友情点不足 / MC不足 / 扭蛋券不足`, empty body, and no save write.
  During candidate testing, the user-accepted `gacha_select/9100` compatibility response remained the default until
  native promotion. `node server/test-bootstrap-server.js` passed, including the encrypted candidate response and
  byte-identical rejected save; log: `work/gacha-business-error-dialog-server-test-20260819.log`.
- Runtime stop: ARM19 was absent with no classic-emulator process; the prescribed `repair-adb` made no destructive
  change. MuMu A12 `127.0.0.1:7555` also refused connection. No candidate was installed, so visible dialog,
  dismissal route quietness, and baseline promotion remain the single next observable. Do not try a second XML or
  UI patch.
- Resumed deployment: after the user started MuMu A12, its full gate passed without display mutation. Installed
  native changed from accepted `DEC36585...CD40F` to candidate `36A4826B...25B69A2` with source/device hash equality,
  identical `755 / 1000:1000 / apk_data_file` metadata, and the process stopped during replacement. Server PID 8404
  is fingerprint-clean on both ports with the experiment flag. A real encrypted live-save probe returned
  `code=1/message=友情点不足`, empty body, no next scene/select/buy model, `saved=false`, and unchanged save SHA-256.
  A12 PID 2902 then survived the controller launch gate in resumed `RooneyJActivity` without fatal.
- Visible acceptance: the user triggered product 1 from the original gacha page. The stock framed modal displayed
  `友情点不足` over the dimmed page; after dismissal the same gacha page was restored. PID 2902 remained resumed,
  logcat contained no fatal, request counts were unchanged during dismissal, and live save SHA-256/mtime remained
  byte-identical. Screenshots: `work/gacha-business-error-dialog-visible-a12-20260819.png` and
  `work/gacha-business-error-dialog-dismissed-a12-20260819.png`.
- Promotion: the experiment gate and `gacha_select/9100` compatibility fallback were removed. Code `1` is now the
  default insufficient-balance response. Native SHA-256
  `36A4826BD42BCF203B51D0344AF5A1B479B961BD26DDB4685DD01A8B325B69A2` and rebuilt unique client baseline APK
  SHA-256 `E8723F5438AFC6D39F4E0913159D2EE7B3BC4F097BD2F5A1E48DE31687C2DCC3` are accepted. Server PID 29168 was
  restarted without the experiment flag; both ports were healthy, an encrypted product-1 probe returned the expected
  business error without a save write, and the installed native hash matched the promoted source.
- Evidence: `work/gacha-buy-original-balance-dialog-path-card-20260819.md`.

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

