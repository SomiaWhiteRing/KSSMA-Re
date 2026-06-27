# KSSMA-Re Reverse Notes

Source artifacts:

- APK: `base/com.square_enix.million_cn-1.0.0.100.0712.M330.apk`
- Resource dump: `base/com.square_enix.million_cn-140330.zip`
- Decompiled output: `work/million_cn/`

## What was extracted

- `work/million_cn/apktool/`: manifest, smali, assets, `lib/armeabi/librooneyj.so`
- `work/million_cn/jadx/`: Java decompile and unpacked assets
- `work/million_cn/sdcard_dump/`: downloaded runtime resources from the original client

## Immediate conclusion

The Java layer is mostly bootstrap, login/world selection, billing glue, WebView glue, and persistence.
The actual game flow and most API routes live in `lib/armeabi/librooneyj.so`.

That means server reconstruction should not start from the Android activities. It should start from:

1. world selection bootstrap APIs
2. runtime key negotiation
3. native `/connect/app/` routes embedded in `librooneyj.so`

## Java-side bootstrap

Manifest:

- package: `com.square_enix.million_cn`
- launcher activity: `com.test.enter.LogoActivity`
- native entry activity: `com.test.RooneyJActivity`

Relevant files:

- `work/million_cn/jadx/sources/com/test/enter/EnterDef.java`
- `work/million_cn/jadx/sources/com/test/enter/WorldSelectActivity.java`
- `work/million_cn/jadx/sources/com/test/HttpUtil.java`
- `work/million_cn/jadx/sources/com/test/Helper.java`
- `work/million_cn/jadx/sources/com/square_enix/million/util/Crypt.java`

Bootstrap endpoints found in Java:

- `http://dlc.game-CBT.ma.sdo.com:50005/add_user.php`
- `http://dlc.game-CBT.ma.sdo.com:50005/world_list.php`

`world_list.php` response fields used by the client:

- `name`
- `member_count`
- `world_status`
- `url_root`
- `url_top`
- `world_id`
- `url_pr`
- `billing_flag`

`add_user.php` request payload:

- form field: `data_str`
- JSON body inside `data_str`:
  - `world_id`
  - `device_id`
  - `game_id` = `"1"`
  - `user_id`
  - `password`

`add_user.php` password handling:

- AES/ECB/PKCS5Padding
- static key: `B1dACcrvur2YULyl`
- then Base64

## Runtime request crypto

Normal app API requests are not plain form posts.

From `HttpUtil.java` and `Crypt.java`:

- request URL gets `cyt=1`
- every POST field value is AES/ECB/PKCS5Padding encrypted
- encrypted field value is then Base64 encoded
- response bytes are decrypted with AES/ECB/PKCS5Padding unless the route is `gp_verify_receipt?`
- Basic Auth is set on the HTTP client:
  - username: `iW7B5MWJ`
  - password: `8KdtjVfX`

Runtime keys are injected later through:

- `com.test.Utils.sendK(String k1, String k2, String urlTop)`

Observed behavior:

- `k1` -> `Helper.setKey(k1)` -> used to encrypt/decrypt local `dtool.txt`
- `k2` -> `Crypt.setKey(k2)` -> used for API request/response crypto

Local persistence:

- `dtool.txt` stores login/cache state
- encrypted with `k1`
- fields include:
  - login id
  - password
  - random UUID
  - `url_root`
  - `url_top`
  - `world_id`
  - `url_pr`
  - `billing_flag`

## Native layer findings

Main game base URL strings found in `librooneyj.so`:

- `http://game.ma.mobimon.com.tw:10001/connect/app/`
- `http://game.ma.mobimon.com.tw/contents/`
- `http://dns7.m-craft.com/rooney/`
- `http://dns7.m-craft.com/rooney/fix/`

Strings also found in `librooneyj.so`:

- helper keys:
  - `A1dPUcrvur2CRQyl`
  - `rBwj1MIAivVN222b`
- build tag:
  - `build: Jul 12 2013`

App routes extracted from `librooneyj.so`:

- `masterdata/card/update`
- `masterdata/card_category/update`
- `masterdata/boss/update`
- `masterdata/item/update`
- `masterdata/scol/update`
- `masterdata/combo/update`
- `mainmenu/update`
- `menu/menulist`
- `menu/noticelist`
- `menu/menu_friend_notification`
- `menu/fairyrewards`
- `menu/battlehistory`
- `menu/player_search`
- `menu/playerinfo`
- `menu/fairyselect`
- `menu/friendlist`
- `menu/friend_notice`
- `menu/friend_appstate`
- `menu/rewardbox`
- `menu/get_rewards`
- `menu/invite_friend`
- `menu/towneventlist`
- `menu/cardcollection`
- `menu/gettownevent`
- `menu/haveparts`
- `menu/other_list`
- `menu/recycle/recycle`
- `menu/recycle/recycle_buy`
- `menu/recycle/recycle_select`
- `menu/productlist`
- `menu/buyproduct`
- `menu/chksnd`
- `exploration/area`
- `exploration/floor`
- `exploration/get_floor`
- `exploration/explore`
- `exploration/battle`
- `exploration/fairyhistory`
- `exploration/fairy_floor`
- `exploration/boss_floor`
- `exploration/fairy_lose`
- `exploration/fairybattle`
- `battle/area`
- `battle/playerlist`
- `battle/competition_item`
- `battle/competition_parts`
- `battle/battle_userlist`
- `battle/competition_floor`
- `battle/competition_userlist`
- `battle/shooting_userlist`
- `battle/battle`
- `battle/battle_userlist_first`
- `battle/battle_userlist_second`
- `story/getoutline`
- `story/battle`
- `scenario/start_scenario`
- `scenario/next_scenario`
- `scenario/start_eventsc`
- `scenario/next_eventsc`
- `tutorial/savename`
- `tutorial/savecountry`
- `tutorial/save_character`
- `tutorial/next`
- `roundtable/edit`
- `roundtable/preview`
- `cardselect/savedeckcard`
- `card/exchange`
- `compound/buildup/getinfo`
- `compound/buildup/compound`
- `compound/evolution/getinfo`
- `compound/evolution/compound`
- `shop/shop`
- `shop/buy`
- `shop/use`
- `item/havelist`
- `item/use`
- `item/use_fakecard`
- `friend/add_friend`
- `friend/approve_friend`
- `friend/refuse_friend`
- `friend/remove_friend`
- `friend/cancel_apply`
- `friend/like_user`
- `ranking/ranking`
- `ranking/ranking_next`
- `ranking/ranking_previous`
- `comment/update`
- `comment/send`
- `payment/verify_receipt`
- `push_info/push_setting`

## Runtime storage layout

The client expects these folders under app storage:

- `save/appdata/`
- `save/database/`
- `save/download/rest/`
- `save/download/image/`
- `save/download/image/card/`
- `save/download/image/boss/`
- `save/download/image/gacha/`
- `save/download/image/face/`
- `save/download/image/map/`
- `save/download/image/item/`
- `save/download/image/mainbg/`
- `save/download/image/cmpsheet/`
- `save/download/image/privilege/`
- `save/download/image/adv/`
- `save/download/image/cache/`
- `save/download/scenario/`
- `save/download/sound/`
- `save/download/voice/`
- `save/download/pack/`

The dumped ZIP already contains real samples for `save/download/rest/`.

## Recommended reconstruction order

1. Re-implement `world_list.php` and `add_user.php` first.
2. Instrument or patch the client to capture `k1` and `k2` from `Utils.sendK(...)`.
3. Rebuild a minimal `/connect/app/` server that can answer:
   - `tutorial/savename`
   - `tutorial/savecountry`
   - `tutorial/save_character`
   - `tutorial/next`
   - `mainmenu/update`
   - `menu/menulist`
4. Use the ZIP dump and `save/download/rest/` naming to map resource IDs to responses.
5. Only then move to exploration, battle, card, gacha, and billing.

## Practical blocker status

The runtime keys are no longer the active blocker. The client logs now expose:

- `k1`: `A1dPUcrvur2CRQyl`
- `k2`: `rBwj1MIAivVN222b`

The bootstrap server uses `k2` for `/connect/app/` AES responses. The active work is now filling the smallest useful `/connect/app/` and `/connect/web/` behavior after login.

Human server helper:

- `work/kssma-server.ps1 start` launches `server/bootstrap-server.js` in the background with `CHECK_INSPECTION_KEY=rBwj1MIAivVN222b`, `CONNECT_APP_KEY=rBwj1MIAivVN222b`, `LOGIN_RESPONSE=sample`, and `PORTS=50005,10001`.
- `work/kssma-server.ps1 status` checks the saved process, both ports, and `http://127.0.0.1:50005/healthz`.
- `work/kssma-server.ps1 log` tails `work/kssma-server.out.log` and `work/kssma-server.err.log`.
- If the game says it cannot connect to the server, first verify this helper reports both `Port50005` and `Port10001` as true before changing client or protocol code.
- `work/kssma-preflight.ps1` is a read-only environment check for human/manual tests. It verifies server ports/health, ARM19 ADB target, hosts, display, audio, key resource files, and whether the full-resource stash exists under `/data/local/tmp/kssma-save`.
- `work/android44-arm19.ps1 mount` restores the existing full-resource bind mount without repushing the 500MB dump. Cold boot drops bind mounts and can restore `/system/etc/hosts` to the base image, so `launch` and `run` now restore hosts and mount the existing full-resource stash before starting the game.

## Android 4.4 ARM runtime

The useful local runtime is now `kssma_arm19` on the classic ARM emulator:

- Android: `4.4.2` / API 19
- ABI: `armeabi-v7a`
- Emulator: `C:\Users\旻\AppData\Local\Android\Sdk-classic-arm\tools\emulator.exe`
- ADB serial: `emulator-5582`
- Console/ADB ports: `5582,5583`
- ADB fallback: classic ARM can leave a stale `emulator-5582 offline` entry even while the same emulator is reachable as `127.0.0.1:5583`; verify the fallback with `ro.product.cpu.abi=armeabi-v7a` and `ro.build.version.release=4.4.2` before using it.
- Data partition: `1536M`
- SD card image: `C:\Users\旻\.android\avd\kssma_arm19.avd\sdcard.img` (`4096M`)
- Start/install/run helper: `work/android44-arm19.ps1`
- Display: current stable AVD config is landscape `1280x720` / `240dpi` on `Nexus 7`-style hardware. The helper now preserves this with `wm size 1280x720` / `wm density 240` instead of the older portrait `640x960` override. Do not restore the old portrait override unless a new runtime check proves this baseline broke.
- Audio: enabled by default. Do not launch ARM19 with `-no-audio` when validating BGM, SE, or voice; the helper keeps `hw.audioInput=yes` and `hw.audioOutput=yes`.
- RAM/heap: AVD config uses `hw.ramSize=2048` and `vm.heapSize=256M`, while the running Android 4.4 guest still reports `dalvik.vm.heapsize=128m`; treat the guest value as the effective Java heap when debugging memory behavior.
- Full `com.square_enix.million_cn-140330.zip` runtime resources should be imported as save data, not APK resources. Current AVD config uses a 4G sdcard and 1536M data image; `work/android44-arm19.ps1 preload-full` still restores the original ZIP save dump to `/data/local/tmp/kssma-save`, patches the missing `mainbg_70_sp` appdata reference to `mainbg_an`, and bind-mounts it over both `/mnt/media_rw/sdcard/.../files/save` and `/storage/sdcard/.../files/save`. Binding only the FUSE path can leave a `(deleted)` mount after the game recreates the directory, causing false missing-resource crashes such as `save/download/rest/treasurebox`. The 4G sdcard baseline was configured while `emulator-5582` was offline; revalidate ADB online state before treating this as a proven runtime improvement.

Useful commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 configure
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 install -ApkPath .\work\million-cn-animationguard-signed.apk
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 hosts
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 preload-rest
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 preload-small
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 run
```

Notes:

- The APK is ARM-only (`lib/armeabi/librooneyj.so`), so this avoids the BlueStacks x86/Houdini false target.
- Install must use `adb install -r -f` because the manifest has `android:installLocation="preferExternal"` and Android 4.4 external ASEC install is unreliable here.
- `-gpu on` removes the `called unimplemented OpenGL ES API` noise seen with `-gpu off`.
- `-no-audio` was removed from the default ARM19 launch arguments; leaving it enabled makes BGM/voice verification impossible even when Android `STREAM_MUSIC` volume and resources are correct.
- `-no-jni` made the classic ARM emulator stay offline, so do not use it as the default.
- Rebuilt APKs now come from the clean `base/com.square_enix.million_cn-1.0.0.100.0712.M330.apk` plus the current native/dex patches, with no XML/asset replacement from `work/million_cn/apktool`. Do not rebuild from the latest signed APK or the dirty apktool resource tree by default; that carried old resource experiments forward and made main-menu/resource debugging look like a black-screen regression.

Current ARM runtime blocker:

- The app reaches the local server on the ARM runtime:
  - `POST /check_inspection?cyt=1`
  - `POST /connect/app/notification/post_devicetoken?cyt=1`
  - `POST /connect/app/login?cyt=1`
- Without preloading `save/download/rest`, the first resource miss is `save/download/rest/que_adv`; Java throws in `JResourceLoader.loadFile`, then CheckJNI aborts in `librooneyj.so!jni_loadTexture`.
- `work/android44-arm19.ps1 preload-rest` pushes the 49 MiB `download/rest` sample set and fixes that false blocker.
- `work/android44-arm19.ps1 preload-small` also pushes:
  - `save/appdata/save_version`
  - `save/database/master_card`
  - `save/database/master_item`
  - `save/database/master_cardcategory`
  - `save/database/master_boss`
  - `save/database/master_scol`
  - `save/database/master_combo`
  - `save/download/image/adv/adv_chara111`
  - `save/download/sound/bgm_common1.ogg`
  - the small `download/scenario` and `download/pack` dumps
- It skips already-present files/directories, so reruns are fast.
- With `LOGIN_RESPONSE=tutorial`, the app gets past `que_adv` and crashes later on real ARM:
  - `Fatal signal 11 (SIGSEGV)`
  - `ResourceManagerEx::exists(String)+25`
  - stack: `ResourceManagerEx::exists -> rooney::res::exists -> _Tutorial::loadScript -> _Tutorial::init`
- With `LOGIN_RESPONSE=sample`, the app avoids the tutorial native crash and reaches:
  - `masterdata/card/update`
  - `masterdata/boss/update`
  - `masterdata/card_category/update`
  - `masterdata/item/update`
  - `GET /contents/161/res/res0_0.pack`
- `res0_0.pack` is an intentional 18-byte empty asset pack from the APK, not a bad local server response.
- Preloading `save_version` plus the `master_*` samples makes the client skip first-run masterdata/resource updater churn and enter mainmenu scene `2100`.
- Missing `save/download/image/adv/adv_chara111` previously caused a CheckJNI abort through `jni_loadTexture`; preloading that fixed the false blocker.
- Missing `save/download/sound/bgm_common1.ogg` was the next warning; preloading it removes the BGM warning.
- The ARM `_Layout::event(...)` `0x00000098` crash is fixed in the rebuilt APK:
  - `work/build-animation-nullguard.py` changes the stale layout callback path at `0x0038D478` / `0x0038D47C`.
  - The root cause was an earlier null-guard branch that still reached a `blx r3` with `r3 = 0x98`; real ARM jumped to `0x98`.
  - The patched path skips missing layout event nodes and no-ops the bogus callback while keeping the existing non-null success result.
- The app now stays alive as the top activity after login and reaches a WebView for `http://game.ma.mobimon.com.tw:10001/connect/web/?S=...`.
- `work/android44-arm19.ps1 hosts` maps `game.ma.mobimon.com.tw` to `10.0.2.2`; `run` applies it automatically.
- The bootstrap server should be launched with `PORTS=50005,10001` so both native `/connect/app/` rewrites and WebView `/connect/web/` hit the same local process.
- `/connect/web/` currently returns a minimal local HTML stub that auto-navigates to `sceneto://2100`.
- ARM19 retest confirms the Java WebView client handles that URL, logs `sceneto : [sceneto://2100]`, closes the WebView, and returns to the visible main menu without a native crash.
- Latest clean-base retest installed `work/million-cn-animationguard-signed.apk`, confirmed `assets/bundle/rule_resource_route.xml`, `layout_mainmenu.xml`, `layout_exploration_area.xml`, `1000_main_menu_badge.anm`, and `local_battle_player.xml` all match the base APK by SHA-256, and captured `work/kssma-clean-resources-mainmenu.png`. The main UI/menu renders and is not the previous full black-screen resource regression. The central main-menu background is still black even though `save/download/pack/mainbg/*` exists on device; treat that as a separate mainbg/rendering issue, not as dirty APK resource inheritance.
- Current resource fix retest: `work/kssma-final-resource-fix.png` reaches `com.test.RooneyJActivity` with no `getSDPackFile`, `treasurebox`, or native missing-file crash. `server/bootstrap-server.js` suppresses login master/resource revisions when using `LOGIN_RESPONSE=sample`, because full resources are already preloaded and advertising newer revisions wakes a broken CDN pack updater.
- This is no longer the BlueStacks `libhoudini.so` crash and no longer a missing `rest`, `adv_chara111`, `bgm_common1`, `_Layout::event` `0x98`, or blocked original WebView issue. Next work should interact with main menu entries and implement the next missing `/connect/app/` route.

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
  - `_ExplorationArea::preUpdate()` only rebuilds the visible floor list via `createFloorList()` after a UI/model completion flag path reaches the `floor_list_active2` branch; current data reaches the server but does not trigger that visible branch.
  - Next debugging should inspect the model/connection completion callback or `_ExplorationArea` flag updates around object offsets `0x55` and `0x56`, not the Android runtime.

## Check inspection retry experiment

- Frontier: after `POST /check_inspection?cyt=1`, the client shows the network retry dialog and the local server does not receive `/connect/app/notification/post_devicetoken` or `/connect/app/login`.
- Hypothesis: the minimal `/check_inspection` success XML is missing a native header field needed to advance the connection flow.
- Static evidence:
  - `librooneyj.so` exports `_HeaderTagParser::parse` and `_ErrorTagParser::parse`.
  - The header parser string cluster includes `error`, `revision`, `your_data`, `session_id`, and `next_scene`.
  - Bundled `assets/bundle/local_forward.xml` is the smallest observed forward response shape: `error/code` plus `next_scene`.
- Changed one variable: temporarily added only `<next_scene>2100</next_scene>` to `CHECK_INSPECTION_OK_XML`.
- Server check: `node .\server\test-bootstrap-server.js` passed; encrypted `check_inspection`-shaped responses grew from 112 to 160 bytes.
- ARM19 check:
  - Runtime: Android 4.4.2/API19 ARM `emulator-5582`.
  - Server log: `C:\Users\旻\AppData\Local\Temp\kssma-check-nextscene-20260624-193432.out.log`.
  - Logcat artifact: `work/kssma-check-nextscene-logcat-20260624-193634.txt`.
  - Command: clear logcat, launch with `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 launch`, wait 45s, inspect server log.
  - Observed requests: `tcp_connect`, `POST /check_inspection?cyt=1`, and `check_inspection_response` only. No `/connect/app/notification/post_devicetoken` and no `/connect/app/login`.
- Conclusion: adding only `next_scene` to `/check_inspection` does not advance the client. The temporary server change was reverted. Do not keep adding main hall resources for this blocker; next useful check should inspect the Java/native `check_inspection` completion path or try a different minimal header field only if static evidence points to it.

## Manual original login flow reaches login request

- Frontier: standard runtime check produced no server requests because the package was missing at first, then after installing it stopped on the original `ModeSelectActivity` screen without user input.
- Hypothesis: driving the original Java UI flow without skipping login will advance the startup request chain past `/check_inspection`.
- Changed one variable: installed `work/million-cn-animationguard-signed.apk`, then used the original UI path only: continue game, select `Local Dev World`, enter `13800138000` / `testpass1`, confirm the built-in login/download popup.
- Server check: no server code changed; `node .\server\test-bootstrap-server.js` was not required for this runtime-only check.
- ARM19 check: Android 4.4.2/API19 ARM via `127.0.0.1:5583`, server log `work/kssma-runtime-manual-ui-20260624-225300-server.out.log`, screenshots under `work/kssma-runtime-manual-ui-20260624-225300-*.png`.
- Observed: server received `POST /world_list.php`, then `POST /check_inspection?cyt=1`, `POST /connect/app/notification/post_devicetoken?cyt=1`, and `POST /connect/app/login?cyt=1`. Decrypted login params were `login_id=13800138000` and `password=testpass1`.
- Conclusion: the clean startup protocol is not blocked at `/check_inspection` when the original login flow is driven. This satisfies the current request-chain success criterion.
- Next: the next frontier is after `/connect/app/login`; the client crashed before a masterdata request in this run, but this round intentionally does not chase crash, resource, black-screen, or main hall issues.

## Login response stops on treasurebox rest miss

- Frontier: `/connect/app/login` returns, but no stable next client behavior has been proven.
- Hypothesis: the current `LOGIN_RESPONSE=sample` path either emits the next `/connect/app/` request, or logcat/native evidence will show why it cannot.
- Changed one variable: none; reran the standard runtime check with the original login driver.
- Server check: no server code changed; `node .\server\test-bootstrap-server.js` was not required.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -WaitSeconds 45`
- Observed: artifact prefix `work/kssma-runtime-20260624-230553`; server stdout reached `POST /connect/app/login?cyt=1` and responded with `assets/bundle/local_battle_player.xml + mainmenu bg`, but no later `/connect/app/` request appeared. Logcat shows `java.lang.RuntimeException: ファイルが開けません:/storage/sdcard/Android/data/com.square_enix.million_cn/files/save/download/rest/treasurebox`, followed by `JResourceLoader.loadFile -> TextureLoader.loadTexture -> librooneyj.so jni_loadTexture -> ResourceManagerEx::loadSceneResource -> _SceneControl::loadResource -> _SceneControl::update`, then CheckJNI abort / `Fatal signal 6 (SIGABRT)`. Activity dump still showed `RooneyJActivity` during collection, but the native abort explains why no next route was logged.
- Conclusion: this run satisfies the current success criterion by proving the post-login stop reason. The next `/connect/app/` route is blocked by a concrete native resource load miss for `save/download/rest/treasurebox`, not by `/check_inspection` or the original login UI.
- Next: verify why the expected small preload does not provide `download/rest/treasurebox` before changing protocol responses; do not switch emulator, skip login, or work on face/mainbg/hall rendering.

## Preload-rest does not repair treasurebox miss

- Frontier: `/connect/app/login` returns and native scene loading aborts on missing `save/download/rest/treasurebox`.
- Hypothesis: running `work/android44-arm19.ps1 preload-rest` before the standard driven login check will make `treasurebox` available through the runtime save path, removing the CheckJNI abort and allowing the next `/connect/app/` request.
- Changed one variable: ran only `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 preload-rest`, then `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -WaitSeconds 45`.
- Server check: no server code changed; `node .\server\test-bootstrap-server.js` was not required.
- ARM19 check: Android 4.4.2/API19 ARM via `127.0.0.1:5583`; artifact prefix `work/kssma-runtime-20260624-234146`.
- Observed: `preload-rest` returned `download/rest already-present` because `que_adv` exists, but direct device checks showed `/storage/sdcard/.../save/download/rest/treasurebox` and `/data/local/tmp/kssma-save/download/rest/treasurebox` were both missing, and no `kssma-save` bind mount was present. Server stdout reached `/connect/app/notification/post_devicetoken` and `/connect/app/login`, but no later `/connect/app/` route. A post-run logcat capture in `work/kssma-runtime-20260624-234146-logcat-after.txt` again shows `java.lang.RuntimeException: ファイルが開けません:/storage/sdcard/Android/data/com.square_enix.million_cn/files/save/download/rest/treasurebox`, followed by `JResourceLoader.loadFile -> TextureLoader.loadTexture -> jni_loadTexture -> ResourceManagerEx::loadSceneResource`, then `Fatal signal 6 (SIGABRT)`.
- Conclusion: `preload-rest` as currently written did not fix the `treasurebox` miss because the sentinel `que_adv` can make the script skip an incomplete `download/rest` directory. This round does not prove any new protocol blocker after login.
- Next: fix the runtime preload/mount path so `download/rest/treasurebox` is actually present before rerunning the same driven login check; do not change login response, emulator target, APK, or face/mainbg/hall resources for this frontier.

## Preload-full repairs treasurebox miss

- Frontier: `/connect/app/login` returns and native scene loading previously aborted on missing `save/download/rest/treasurebox`.
- Hypothesis: restoring the full 140330 runtime save dump and bind-mounting it to the app save path will make `download/rest/treasurebox` readable by the client, removing the CheckJNI abort.
- Changed one variable: ran `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 preload-full` against Android 4.4.2/API19 ARM via `127.0.0.1:5583`; `emulator-5582` was offline and the fallback was revalidated as `ro.product.cpu.abi=armeabi-v7a`, `ro.build.version.release=4.4.2`.
- Server check: no server code changed; `node .\server\test-bootstrap-server.js` was not required.
- ARM19 check:
  - `preload-full` pushed 6895 files / 517055607 bytes and reported `/storage/sdcard/Android/data/com.square_enix.million_cn/files/save` on `/data` with 667.7M free.
  - Direct required verification passed:
    - `adb -s 127.0.0.1:5583 shell ls -l /storage/sdcard/Android/data/com.square_enix.million_cn/files/save/download/rest/treasurebox` -> `-rwxr-xr-x root root 21968 ... treasurebox`
    - `adb -s 127.0.0.1:5583 shell ls -l /data/local/tmp/kssma-save/download/rest/treasurebox` -> `-rwxr-xr-x root root 21968 ... treasurebox`
  - Standard driven check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -WaitSeconds 45`, artifact prefix `work/kssma-runtime-20260625-000834`.
  - Longer post-login observation: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -WaitSeconds 90 -Tag postfull-90s`, artifact prefix `work/kssma-runtime-postfull-90s`.
- Observed: the required `treasurebox` file remained present after launch, logcat contains no `treasurebox`, `JResourceLoader`, `getSDPackFile`, `ファイルが開けません`, `jni_loadTexture`, `Fatal signal`, `SIGABRT`, or `SIGSEGV` entries for the post-full-preload runs. Server stdout reached `/connect/app/notification/post_devicetoken`, `/connect/app/login`, then `GET /connect/web/?S=1bcdrlialn5bvkdogc2pt5mst2`. Activity stayed focused/resumed in `com.test.RooneyJActivity`. Screenshot `work/kssma-runtime-postfull-90s.png` shows the client at `CONNECTING...`. Logcat after `/connect/web/` shows APN permission noise from `CheckNetWork` and repeated `AwContents nativeOnDraw failed; clearing to background color`, but no native resource abort.
- Conclusion: full runtime save preload fixes the concrete `save/download/rest/treasurebox` miss. The next frontier is no longer missing `rest/treasurebox`; after login the client enters the local `/connect/web/` WebView path and does not emit a later `/connect/app/` request during the 90s observation.
- Next: inspect the WebView close/sceneto path or why the existing `/connect/web/` redirect is not returning this run to the native main menu; do not change protocol, APK, or black-screen resources based on the old `treasurebox` failure.

## Runtime notice WebView guard

- Frontier: after `/connect/app/login`, the client may request `/connect/web/?S=...`; this can be the daily first-login notice WebView, but `/connect/web/` alone is not a failure and not proof that input is needed.
- Hypothesis: the runtime driver should only dismiss an active notice when the current UI/screenshot proves a notice is still blocking the game; if the client is already at main menu, it should record `/connect/web/` and avoid Back/taps.
- Changed one variable: updated `C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1` with `-DismissNoticeWebView`, `-WaitMainMenuAfterWebView`, and a guarded `-ForceDismissNoticeWebView` escape hatch. Also updated the skill instructions.
- Server check: `node .\server\test-bootstrap-server.js` passed.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 45 -Tag notice-dismiss-mainmenu-guard`.
- Observed: artifact prefix `work/kssma-runtime-notice-dismiss-mainmenu-guard`; server stdout still reached `GET /connect/web/?S=1bcdrlialn5bvkdogc2pt5mst2`, so `connect_web_seen=True`. The pre-action screenshot `work/kssma-runtime-notice-dismiss-mainmenu-guard-notice-webview-before.png` was already the visible main menu; `*-notice-webview.txt` logged `looks_main_menu=True` and `skipped input: no active notice proven`. No `pressed Android Back` or `fallback tap` line was emitted.
- Conclusion: `/connect/web/` and stale/embedded WebView evidence must not be treated as a failure or as permission to close anything. The runtime check now preserves the observation and avoids input when the screenshot is already main menu.
- Next: use normal `-DismissNoticeWebView` for login checks. Use `-ForceDismissNoticeWebView` only after a saved screenshot proves an actual notice page is blocking the game but Android UI dump does not expose a reliable close control.

## Audio/BGM/voice scope closure

- Frontier: keep the current main-menu investigation focused on visual differences only.
- Hypothesis: stale task wording that mentions BGM/voice can make agents reopen an already-closed emulator/runtime baseline while the active issue is black mainbg/face rendering.
- Changed one variable: updated agent instructions and interrupted the active subagents to exclude BGM, voice, and audio from the main-menu task unless new evidence directly connects audio state to visual rendering.
- Observed: the runtime baseline already documents enabled ARM19 audio and preflight checks; the current main-menu observable is still visual-only: black central background and black pixie/face.
- Conclusion: BGM/voice/audio is not an active bug in the main-menu visual frontier. It belongs only to environment preflight.
- Next: investigate only the visual resource chain: mainmenu/town_model parser fields, `TextureLoader`/`JResourceLoader`, `MainMenuTagParser`, `MainbgTagParser`, and the town model binding path.

## Main menu wrapper experiment

- Frontier: after a valid login flow reaches `RooneyJActivity`, the visible main menu still has a black central background and black character face while the relevant resource files exist.
- Hypothesis: `_MainMenuTagParser` and `_MainbgTagParser` expect the existing `bgAnmType`, `current_bgfile`, `previous_bgfile`, `currentBgfile`, `previousBgfile`, `fairy_pose`, and `fairy_face` fields under a `<main_menu>` parent instead of directly under `<body>`.
- Changed one variable: wrapped the existing main menu fields in `<main_menu>` for both `LOGIN_RESPONSE=sample` seeding and `/connect/app/mainmenu/update`; field names and values were unchanged.
- Server check: `node .\server\test-bootstrap-server.js` passed.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 60 -Tag mainmenu-main-menu-wrapper-rerun`.
- Observed: artifact prefix `work/kssma-runtime-mainmenu-main-menu-wrapper-rerun`; `server.err.log` was empty, requests reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, and `/connect/web/`. The login response size was `2080`, proving the wrapper payload was exercised. Screenshots `work/kssma-runtime-mainmenu-main-menu-wrapper-rerun.png` and `work/kssma-runtime-mainmenu-main-menu-wrapper-rerun-mainmenu-after-webview.png` still show black main-menu background and black character face. Resource checks still show `face_1`, `face_111`, `adv_chara111`, and `mainbg_an_0_0` present; logcat has no useful `JResourceLoader`, `getSDPackFile`, `loadTexture`, `mainbg`, `face`, or `Fatal signal` evidence for the visual-resource chain.
- Conclusion: the `<main_menu>` wrapper alone does not fix the main menu visual differences. Do not repeat this exact XML-shape experiment unless new parser evidence changes the hypothesis.
- Next: inspect the actual town/main-menu model consumption path or compare decrypted known-good main-menu payloads before adding more XML fields.

## Mainmenu node fixes main menu visuals

- Frontier: after login reaches scene `2100`, the central main-menu background and pixie/face were black even though `mainbg_an_0_0`, `face_1`, `face_111`, and `adv_chara111` were present on device.
- Hypothesis: the native `MainMenuTagParser` consumes confirmed snake_case fields from a `<mainmenu>` node, not from direct `<body>` fields and not from `<main_menu>`.
- Changed one variable: changed login-seeded and `/connect/app/mainmenu/update` body shape to:
  `<body><mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile></mainmenu></body>`.
  Removed the earlier camelCase/direct body fields from this experiment.
- Server check: `node .\server\test-bootstrap-server.js` passed; `/connect/app/login` response size became `1904`, proving the `<mainmenu>` payload was served.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 60 -Tag mainmenu-mainmenu-node-rerun`.
- Observed: artifact prefix `work/kssma-runtime-mainmenu-mainmenu-node-rerun`; requests reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, and `/connect/web/`; resources still showed `face_1`, `face_111`, `adv_chara111`, and `mainbg_an_0_0` present. Screenshot `work/kssma-runtime-mainmenu-mainmenu-node-rerun.png` showed the mainbg image instead of a black background, but the WebView dismiss helper pressed Back and opened the exit confirmation dialog. After tapping `No`, screenshot `work/kssma-after-mainmenu-node-no.png` showed the main menu with background, pixie, buttons, AP/BC/card/friend counters visible.
- Conclusion: `<mainmenu>` with `current_bgfile` and `previous_bgfile` is a valid fix candidate for the black main-menu background/pixie startup state. The earlier `<main_menu>` wrapper and direct `<body>` fields are the wrong shapes for this parser path.
- Next: keep this minimal response shape. If face expression still needs refinement, investigate which `fairy_pose`/`fairy_face` values the pixie model expects, but do not reopen resource mount, audio, or broad XML-field guessing.

## Mainmenu fairy_pose schema check

- Frontier: validate one formed schema hypothesis for mainmenu pixie fields, not discover schema by runtime guessing.
- Schema card source: `work/mainmenu-fairy-schema-card.md`; static anchors are `work/million_cn/jadx/resources/assets/bundle/layout_mainmenu.xml:21`-`23` and `work/mainmenu-parser-annotated.txt` `_AnmPixie::setPropertyValues` at `0x2898ac`, which looks up `fairy_pose`/`fairy_face` and calls `updateFairyImage`.
- Hypothesis: adding only `<fairy_pose>1</fairy_pose>` under the already-proven `<body><mainmenu>` node changes the visible pixie pose/face state or produces a new face/fairy resource/log observable.
- Changed one variable: temporarily added only `<fairy_pose>1</fairy_pose>` to `MAINMENU_FIELDS`; no `fairy_face`, APK, emulator, resource, contents/loginBonus/badge/dialogue, or audio change.
- Expected observable: login response size increases by one field, request chain still reaches scene `2100`, and clean screenshot or logcat shows a pixie/face change versus `work/kssma-runtime-mainmenu-fairy-baseline-clean.png`.
- Server check: `node .\server\test-bootstrap-server.js` passed; `mainmenu/update` encrypted response grew from `336` to `368` bytes during the experiment.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 60 -Tag mainmenu-fairy-pose-1`.
- Artifact prefix: `work/kssma-runtime-mainmenu-fairy-pose-1`; baseline prefix `work/kssma-runtime-mainmenu-fairy-baseline`.
- Observed: login response size was `1936` versus baseline `1904`, proving the single field was served. Requests reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, and `/connect/web/`. Logcat had no new `JResourceLoader`, `getSDPackFile`, `loadTexture`, `face`, `fairy`, or fatal signal evidence. Clean screenshot `work/kssma-runtime-mainmenu-fairy-pose-1-clean.png` matched baseline visually; pixel diff was `0.0594%` full screen and `0%` in the marked face area, with changed pixels only around `x=358..474,y=632..636`.
- Conclusion: `fairy_pose=1` alone did not produce a useful mainmenu face/character observable.
- Next: validate `fairy_face` as the second and final candidate from the same schema card; stop if it also produces no new observable.

## Mainmenu fairy_face schema check

- Frontier: validate the second formed schema hypothesis for mainmenu pixie fields.
- Schema card source: `work/mainmenu-fairy-schema-card.md`; same `layout_mainmenu.xml` pixie binding and `_AnmPixie::setPropertyValues -> updateFairyImage` static path.
- Hypothesis: adding only `<fairy_face>1</fairy_face>` under `<body><mainmenu>` changes the visible pixie face state or produces a new face/fairy resource/log observable.
- Changed one variable: removed the temporary `fairy_pose` field and temporarily added only `<fairy_face>1</fairy_face>` to `MAINMENU_FIELDS`; no other response shape, APK, emulator, resource, contents/loginBonus/badge/dialogue, or audio change.
- Expected observable: login response size increases by one field, request chain still reaches scene `2100`, and clean screenshot or logcat shows a face-specific change versus baseline.
- Server check: `node .\server\test-bootstrap-server.js` passed; `mainmenu/update` encrypted response was `368` bytes during the experiment.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 60 -Tag mainmenu-fairy-face-1`.
- Artifact prefix: `work/kssma-runtime-mainmenu-fairy-face-1`.
- Observed: login response size was `1936`, proving the single field was served. Requests reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, and `/connect/web/`. Logcat had no new `JResourceLoader`, `getSDPackFile`, `loadTexture`, `face`, `fairy`, or fatal signal evidence. Clean screenshot `work/kssma-runtime-mainmenu-fairy-face-1-clean.png` still did not reveal a face change; pixel diff versus baseline was `0.3424%` full screen and `0%` in the marked face area, with changed pixels localized around the lower AP/BC bar region `x=332..496,y=611..647`.
- Conclusion: `fairy_face=1` alone did not produce a useful mainmenu face observable. Together with the `fairy_pose=1` negative result, this satisfies the hard stop: two candidate field checks produced no new face/character observable.
- Next: stop runtime field trials. The server was restored to the minimal `<mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile></mainmenu>` shape; future work should recover the value domain or missing model data statically before another runtime check.

## Master/resource static mapping proof

- Frontier: static proof for face/character dialog resource mapping without changing server, APK, runtime, or audio.
- Hypothesis: an existing sample `leader_serial_id` or `master_card_id` can be linked to `master_card`, then to concrete `face_*` / `adv_chara*` files in the 140330 save dump.
- Command: `node .\work\master-resource-map-proof.js`; report written to `work/master-resource-map-20260625.md`.
- Observed:
  - `local_battle_player.xml` only exposes `leader_serial_id=2367`; it has no `master_card_id`, `owner_card_list`, `user_card`, or `leader_card` body.
  - Parsed `save/database/master_card` as a big-endian offset table with 480 records. `2367` is not a master id and no parsed record contains u32 value `2367`.
  - Other bundle samples prove the direct chain when `master_card_id` is present:
    - `local_battle_result.xml`: `serial_id=13822704 -> master_card_id=9 -> face_9/adv_chara9 and face_5009/adv_chara5009` exist; `card9_0.pack` contains the aliases.
    - `local_battle_result.xml`: `serial_id=7 -> master_card_id=101 -> face_101/adv_chara101 and face_5101/adv_chara5101` exist; `card101_0.pack` contains the aliases.
    - `local_users_event_list.xml` and `local_battle_area.xml` similarly close for `master_card_id` 22, 179, and 30.
- Conclusion: `master_card_id -> master_card -> card pack alias -> face/adv resource` is a viable static chain, but `local_battle_player.xml leader_serial_id=2367 -> master_card_id` remains unproven. Do not infer `face_2367` or `adv_chara2367` from the leader serial.
- Next: find or capture one owner-card payload containing `serial_id=2367` beside `master_card_id`; then add exactly one proven `2367 -> N -> face_N/adv_charaN` row.

## Owner-card evidence static search

- Frontier: resolve `leader_serial_id=2367` to a sibling owned-card `master_card_id` without runtime, server, APK, or audio changes.
- Hypothesis: an existing bundle sample, 140330 save dump file, server sample, or `work/` runtime/log/decrypted artifact contains an owner-card structure with `serial_id=2367` and `master_card_id` in the same block.
- Command: `node .\work\owner-card-evidence-proof.js`; report written to `work/owner-card-evidence-20260625.md`.
- Observed: scanned jadx bundle, apktool bundle, non-audio sdcard dump files, the 140330 ZIP database/appdata/text candidates, `server/`, and top-level `work/` artifacts. The only valid payload hit remains `local_battle_player.xml` with `your_data/leader_serial_id=2367`; no searched source contains `serial_id=2367 -> master_card_id=N`. Binary/log hits for `2367` were PNG bytes, Android process ids, or existing proof notes.
- Conclusion: the chain still cannot close. `2367` remains an owned-card serial id only and must not be used as `master_card_id`, `face_2367`, or `adv_chara2367`.
- Next: the minimum proof is one captured/static owner-card or deck payload, likely from `roundtable/edit`, `roundtable/preview`, `menu/playerinfo`, `menu/cardcollection`, `cardselect/savedeckcard`, or `card/exchange`, containing `<serial_id>2367</serial_id>` beside `<master_card_id>N</master_card_id>`.

## Mainmenu infomation 2/1 runtime attempt

- Frontier: mainmenu infomation candidate might repair or change the pixie face or character-click dialogue.
- Hypothesis: one `<mainmenu><infomation>` entry with `fairy_pose=2`, `fairy_face=1`, and a `Welcome back.` message will be consumed by `TownModel` / `NavigatorModel` and produce a pixie or dialogue observable.
- Changed one variable: temporarily added one `<infomation>` child under the already-proven `<body><mainmenu>` fields in `MAINMENU_FIELDS`, so it covered both `LOGIN_RESPONSE=sample` login seeding and `/connect/app/mainmenu/update`. No `imagefile`, `focus`, `link`, `banner`, `rewards`, `event_type`, APK, emulator, resource, or audio change.
- Server check: `node .\server\test-bootstrap-server.js` passed with the candidate; encrypted `/connect/app/mainmenu/update` grew from the mainbg-only 336 bytes to 576 bytes. After the failed runtime attempt produced no client observable, server/test were restored to the mainbg-only state and the same self-check passed again with `mainmenu/update` back at 336 bytes.
- ARM19 check: ran exactly once: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 60 -Tag mainmenu-infomation-2-1`. The outer shell timed out after about 604 seconds before the helper wrote its summary/logcat/screenshot artifacts.
- Observed: artifact prefix `work/kssma-runtime-mainmenu-infomation-2-1`; only `*-server.out.log`, `*-server.err.log`, and `*-login-driver.txt` were produced. `*-server.out.log` contains only bootstrap server startup on `50005` and `10001`; `*-login-driver.txt` only reached `drive_login start login_id=13800138000`. There were no `world_list`, `check_inspection`, `/connect/app/login`, `/connect/app/mainmenu/update`, or `/connect/web/` requests. No summary, logcat key line, screenshot, RooneyJActivity/mainmenu proof, pixie change, dialogue proof, resource miss, or native crash artifact was produced. The one-shot `node .\server\bootstrap-server.js` process and the timed-out `kssma_runtime_check.ps1` PowerShell process left by the timeout were stopped after confirming their command lines.
- Conclusion: this run produced no valid runtime observable for the `infomation` candidate, so the candidate XML was not kept. It does not prove the values fail; it only proves this one-shot run did not reach the client flow.
- Next: keep the server at the mainbg-only `<mainmenu>` baseline. Before any future rerun of this exact candidate, first diagnose why the runtime helper hung before login/request capture; do not change schema, APK, resources, emulator target, or audio to explain this attempt.

## Runtime harness observability restored

- Frontier: the one-shot runtime helper timed out before producing request, logcat, activity, or screenshot artifacts for the prior `infomation` trial.
- Hypothesis: the helper was losing observability before the login driver because ARM19 was not actually online on the expected serial during cold start; it was not a protocol/XML failure.
- Changed one variable: no server XML, APK, resource, or emulator-target change. Ran read-only preflight/status checks first, then retried the baseline helper after standard ARM19 was online and `hosts`/`launch` had been verified individually.
- Server check: baseline server remained the mainbg-only `<mainmenu>` shape before candidate retest.
- ARM19 check:
  - Read-only preflight: `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-preflight.ps1`.
  - Cold helper attempt: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 60 -Tag harness-baseline-mainbg-only` timed out externally after 900s.
  - Online helper retry: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 60 -Tag harness-baseline-online-mainbg-only`.
- Observed: preflight initially showed `ServerPort50005=False`, `ServerPort10001=False`, and no ARM19 serial; the visible ADB devices were Android 12/x86_64. The cold helper left only `work/kssma-runtime-harness-baseline-mainbg-only-server.out.log` and `server.err.log`; manual captures showed ARM19 later online as `emulator-5582` (`armeabi-v7a`, Android `4.4.2`) but still at Launcher, with no server requests. After verifying `android44-arm19.ps1 hosts` and `launch` separately, the online retry produced full artifacts under `work/kssma-runtime-harness-baseline-online-mainbg-only*`: requests reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, and `/connect/web/`; activity/logcat/resources/screenshot were captured.
- Conclusion: runtime observability is restored when ARM19 is already online on `emulator-5582`; the prior 604s candidate run and the repeated cold helper timeout were harness/ADB startup observability failures, not evidence against the XML candidate.
- Next: rerun only the fixed `infomation 2/1 + message` candidate now that baseline request, activity, logcat, and screenshot artifacts are available.

## Mainmenu infomation 2/1 result

- Frontier: validate the fixed `infomation` candidate, not discover new schema.
- Hypothesis: one `<mainmenu><infomation>` entry with `fairy_pose=2`, `fairy_face=1`, and a `Welcome back.` message will be consumed by `TownModel` / `NavigatorModel` and produce a pixie or dialogue observable.
- Changed one variable: kept the proven `<mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile>` baseline and added only:
  `<infomation><fairy_pose>2</fairy_pose><fairy_face>1</fairy_face><message><text>Welcome back.</text><color>0xFFFFFF</color><size>20</size></message></infomation>`.
  The shared `MAINMENU_FIELDS` covers both `LOGIN_RESPONSE=sample` login seeding and `/connect/app/mainmenu/update`; no `imagefile`, `focus`, `link`, `banner`, `rewards`, `event_type`, APK, emulator, resource, or audio change.
- Server check: `node .\server\test-bootstrap-server.js` passed. `/connect/app/mainmenu/update` encrypted response grew from the mainbg-only 336 bytes to 576 bytes, and the test asserts the candidate fields are present while the excluded fields are absent.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\旻\.codex\skills\kssma-re-runtime\scripts\kssma_runtime_check.ps1 -Repo C:\Users\旻\Documents\GitHub\KSSMA-Re -DriveLogin -DismissNoticeWebView -WaitMainMenuAfterWebView 20 -WaitSeconds 60 -Tag mainmenu-infomation-2-1-result`.
- Observed: artifact prefix `work/kssma-runtime-mainmenu-infomation-2-1-result`; requests reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, and `/connect/web/`. Login response size was `2144` bytes versus baseline `1904`, proving the candidate was served through `LOGIN_RESPONSE=sample`. No runtime `/connect/app/mainmenu/update` request was emitted during this flow, but the same shared body is covered by the server self-check. Screenshot `work/kssma-runtime-mainmenu-infomation-2-1-result.png` shows the main menu information box rendering `Welcome back.`. A minimal tap at `300,360`, chosen from the 1280x720 screenshot's visible character region, was saved as `work/kssma-runtime-mainmenu-infomation-2-1-result-before-tap.png` and `work/kssma-runtime-mainmenu-infomation-2-1-result-after-tap.png`; after the tap, the pixie changes from the back/side state to a visible front face expression. Logcat after the run/tap showed no new `JResourceLoader`, `getSDPackFile`, `loadTexture`, `Fatal signal`, `SIGABRT`, or `SIGSEGV` evidence.
- Conclusion: the fixed `infomation 2/1 + message` candidate is valid enough to keep. It gives a concrete main-menu dialogue/message observable and a character-tap pixie/face observable without new resource or native-crash failures.
- Next: keep the minimal server/test change. Future work can refine real message rotation or pixie value domains from captured server data, but should not add `imagefile`, `banner`, rewards, or event fields without new evidence.

## Mainmenu infomation 2/5 result

- Frontier: fix the initial unclicked main-menu pixie face, not the clicked/selected face path.
- Hypothesis: `fairy_pose=2` is the supported pose for `adv_chara111`, and changing only `fairy_face` from `1` to `5` will select the front-facing initial expression indicated by the static `adv_chara111_2_5` resource/native string evidence.
- Changed one variable: kept the proven `<mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile><infomation>...<message>Welcome back.</message></infomation></mainmenu>` shape and changed only `<fairy_face>1</fairy_face>` to `<fairy_face>5</fairy_face>` in the shared `MAINMENU_FIELDS`. No APK, emulator, resource, `imagefile`, `focus`, `link`, `banner`, rewards, event, or audio change.
- Server check: `node .\server\test-bootstrap-server.js` passed. `/connect/app/mainmenu/update` encrypted response stayed `576` bytes, and the test now asserts `<fairy_face>5</fairy_face>` is present in both `MAINMENU_UPDATE_XML` and the `LOGIN_RESPONSE=sample` login-seeded payload.
- ARM19 check: the standard runtime helper first failed before launch at `stage=start-arm19` because `android44-arm19.ps1 start` reported `Display=unavailable` while `emulator-5582` was already `device`; that produced no server requests and is not evidence against `face5`. A manual equivalent run then started `bootstrap-server.js` with `CHECK_INSPECTION_KEY=rBwj1MIAivVN222b`, `CONNECT_APP_KEY=rBwj1MIAivVN222b`, `LOGIN_RESPONSE=sample`, and `PORTS=50005,10001`; verified hosts/resources; force-stopped and started `com.square_enix.million_cn/com.test.enter.LogoActivity`; waited 90 seconds; and collected artifacts under `work/kssma-runtime-mainmenu-infomation-2-5-manual*`.
- Observed: server requests reached `/check_inspection`, `/connect/app/notification/post_devicetoken`, `/connect/app/login`, and `/connect/web/`. Login response size was `2144` bytes, proving the `face5` payload was served through the same login-seeded path as `face1`. Top activity stayed `com.test.RooneyJActivity`. Screenshot `work/kssma-runtime-mainmenu-infomation-2-5-manual.png` shows the unclicked initial main menu with the pixie facing forward and smiling. Logcat had no new `JResourceLoader`, `getSDPackFile`, `loadTexture`, `Fatal signal`, `SIGABRT`, or `SIGSEGV` evidence.
- Conclusion: `fairy_pose=2` + `fairy_face=5` fixes the initial unclicked face state for the current local main menu. The earlier `fairy_face=1` run only proved the `infomation/message` node was consumed; its clicked screenshot was the separate selected/touch path and must not be counted as an initial-state fix.
- Next: keep `face5` as the current baseline for `adv_chara111`. If future work changes the navigator character, recover that character's valid `pose/face` value domain statically before runtime trials.

## Main menu visual restoration closure

- Frontier: close the main-menu visual restoration loop before returning to gameplay/protocol reconstruction.
- New evidence: the user recovered pre-shutdown gameplay footage and confirmed that tapping the main-menu character originally showed synchronized subtitle text without a bottom/backing dialogue box.
- Observed current baseline: `fairy_pose=2` + `fairy_face=5` fixes the initial unclicked face for `adv_chara111`; `<mainmenu><current_bgfile>mainbg_an</current_bgfile><previous_bgfile>mainbg_an</previous_bgfile>` fixes the main background; `<mainmenu><infomation><message>...` drives the main-menu information box; BGM/voice runtime baseline is enabled; tapping the character changes expression and shows synchronized text.
- Correction: the earlier "missing tap dialogue/backing box" reports were based on a false memory of the original UI. They must not be used as evidence for another XML, resource, layout, emulator, or APK fix.
- Conclusion: main-menu restoration is stage-complete for the current local baseline.
- Next: resume the post-main-menu frontier, currently gameplay/protocol progression after the visible main menu, such as exploration request/state-machine work. Reopen main-menu visuals only if a new run produces a resource-miss log, texture/native crash, or screenshot regression against this baseline.

## Main menu button connectivity triage

- Frontier: user reports every main-menu button loads and then says it cannot connect to the server.
- Hypothesis: this is not a stopped-server problem; at least some buttons are reaching the local server and then failing because the route is missing or because the implemented route does not advance the client state.
- Changed one variable: no code, APK, resource, or emulator change. Started/checked the human server helper and inspected the existing server log.
- Server check: `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-server.ps1 status` showed `Running=True`, `Port50005=True`, `Port10001=True`, and `Health50005=True`.
- Observed: `work/kssma-server.out.log` recorded `POST /connect/app/exploration/area?cyt=1` and an encrypted 200 response (`minimal exploration area`, 928 bytes). It also recorded `POST /connect/app/shop/shop?cyt=1`; `server/bootstrap-server.js` has no handler for that route, so it falls through to the generic `501 connect/app not implemented yet` plain-text response. The client can present that as a generic server connection failure.
- ADB note: `adb devices -l` shows `emulator-5582 device`, but direct `adb -s emulator-5582 shell getprop`, `dumpsys`, and `screencap` hung until their client processes were killed. `127.0.0.1:5583` is currently offline. Do not run automated button clicking until ADB shell control is restored.
- Static button map: `layout_mainmenu.xml` exposes main commands `exploration`, `menu`, `battle`, `compound`, `shop`, `scroll_story`, `gacha`, plus status/menu buttons. Galileo's static pass ranked `exploration` first because `/connect/app/exploration/area` and `/connect/app/exploration/floor` are implemented; `shop` maps to `/connect/app/shop/shop` and is currently unimplemented.
- Conclusion: the phrase "cannot connect to server" is ambiguous. Current evidence proves the server is reachable. For shop, the immediate blocker is a missing `/connect/app/shop/shop` encrypted route. For exploration, the known blocker remains the post-`exploration/floor` client state-machine transition, not server reachability.
- Next: use exactly one frontier at a time. First restore ADB control if automated runtime clicks are required. For protocol progress without ADB, either continue the existing exploration state-machine investigation or statically recover and implement the smallest `/connect/app/shop/shop` response before one runtime check.

## Main menu button matrix and runtime baseline repair

- Frontier: user says many main-menu buttons load and then report "cannot connect to server".
- Hypothesis: some buttons are reaching the local server but the server lacks a route, while exploration is already connected and only blocked by later state/mount issues.
- Changed one variable: restored ARM19 ADB/hosts/mount observability without touching button XML or protocol code.
- Server check: `work/kssma-server.ps1 status` stayed healthy with `Port50005=True` and `Port10001=True`.
- ARM19 check:
  - `emulator-5582` became stale/offline after restart, so the working serial is `127.0.0.1:5583`.
  - `/system/etc/hosts` had dropped back to only `localhost`; manual restore to `10.0.2.2 game.ma.mobimon.com.tw` and `10.0.2.2 dlc.game-CBT.ma.sdo.com` fixed the startup chain.
  - `android44-arm19.ps1 hosts` and `mount` were failing while the emulator was running because they tried to rewrite `config.ini`; the script was patched so `Start-Runtime` stops a live classic ARM process before touching AVD config.
- Observed:
  - Main-menu buttons hit concrete routes: `exploration/area`, `shop/shop`, `battle/area`, `card/exchange`, `menu/menulist`.
  - `exploration/area` is implemented and returns 200.
  - `shop/shop`, `battle/area`, `card/exchange`, and `menu/menulist` are currently missing handlers in `server/bootstrap-server.js`, so they fall through to the generic `501 connect/app not implemented yet`.
  - The client shows the generic "无法连接服务器" dialog for those missing routes.
- Conclusion: the connectivity complaint is a mixture of a runtime baseline issue (hosts/mount after ARM19 restart) and real protocol gaps for several menu routes. Exploration itself is not the blocker at the server-reachability layer.
- Next: continue from exploration only after restoring mount/hosts on the active serial. The most promising next protocol fix remains the first missing concrete route that the user actually needs, but exploration is already past the HTTP reachability stage.

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

## ARM19 ADB repair helper

- Frontier: runtime checks spend too much wall time recovering from stale ARM19 ADB transports instead of testing the game.
- Hypothesis: the repeated slow path comes from classic ARM exposing `emulator-5582` and `127.0.0.1:5583` inconsistently: one can be stale/offline while the other is usable, and simple `adb shell` probes can hang long enough to waste most of a turn.
- Changed one variable: added `work/android44-arm19.ps1 repair-adb`, which disconnects stale `127.0.0.1:5583`, reconnects offline transports, optionally restarts the ADB server, and then resolves the preferred usable Android `4.4.2` / `armeabi-v7a` serial. Also shortened non-critical status/display probes so `AllowFailure` timeouts return quickly instead of throwing.
- Skill update: updated personal skill `kssma-re-runtime` to require `repair-adb` before manual runtime click loops, and updated its one-shot `kssma_runtime_check.ps1` to run `repair-arm19-adb` after `start-arm19` and before `apply-hosts`.
- Server check: `node .\server\test-bootstrap-server.js` still passed; no protocol behavior was changed.
- ARM19 check: `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 repair-adb` and `status` both resolved `emulator-5582 device` with `TargetRows=emulator-5582 device`; measured runtime was about 7-9 seconds in the current environment.
- Observed: the helper now reports the selected serial and target rows directly, so agents no longer need to spend a manual loop on `adb kill-server`, `disconnect`, `connect`, and serial guessing when `127.0.0.1:5583` is stale.
- Conclusion: the emulator connection is still inherently flaky, but the recovery path is now a named, reusable operation rather than an ad hoc investigation.
- Next: before any manual runtime test, run `kssma-server.ps1 status`, then `android44-arm19.ps1 repair-adb`, then `hosts` and `mount`. If `repair-adb` cannot produce a usable ARM19 serial, stop and report ADB state instead of trying random emulator targets.

## ARM19 install/runtime efficiency baseline

- Frontier: runtime work was spending most wall time on emulator/ADB/APK installation instead of code or game observables.
- Hypothesis: repeated full `adb install` is the wrong default for native-only experiments, and missing install diagnostics cause agents to retry the slowest operation blindly.
- Evidence:
  - The signed APK is about 304MB, while the native patch target `lib/armeabi/librooneyj.so` is only a few MB.
  - Android 4.4 internal install can consume extra `/data` headroom through `/data/local/tmp`, `/data/app`, `/data/app-lib`, and dexopt staging; stale `vmdl-*` and temp APKs make later attempts worse.
  - A prior host-side `adb install` timed out after several minutes, but device-side installation had already completed: the installed `/data/app-lib/com.square_enix.million_cn-*/librooneyj.so` bytes matched the diagnostic APK.
  - Frida probing on ARM19 made the ADB transport fall offline in this environment, so it should not be the default observability path.
- Changed one variable: upgraded `work/android44-arm19.ps1` rather than changing APK/protocol behavior:
  - `patch-lib` extracts `librooneyj.so` from an APK or accepts a `.so`, force-stops the app, pushes only that library into `/data/app-lib/...`, fixes permissions, and verifies SHA-256.
  - `clean-install` clears known Android install scratch files and reports `/data` state.
  - `install` now clears scratch, checks `/data` headroom, uses a longer timeout, and after failure/timeout checks whether installed `librooneyj.so` already matches before asking for another full install.
  - `status` now reports `/data` `df`; `stop` only targets this AVD's classic ARM emulator processes.
- Check:
  - `node .\server\test-bootstrap-server.js` passed.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 status` returned in seconds and reported the usable serial as `127.0.0.1:5583`, with `emulator-5582` still offline and `/data` free around 618MB.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 patch-lib -ApkPath .\work\million-cn-animationguard-signed.apk` completed in about 31 seconds and verified `/data/app-lib/com.square_enix.million_cn-2/librooneyj.so`.
- Conclusion: for native-only exploration diagnostics, the baseline command is now `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 patch-lib -ApkPath .\work\million-cn-animationguard-signed.apk`. Full `install` is reserved for Java/resources/manifest/signature/package changes or first install.
- Next: if a future runtime task spends more than a few minutes before reaching a concrete game observable, first check whether it violated this baseline: wrong serial, Frida left running, full install used for native-only change, or ignored `/data`/install diagnosis.

## ARM19 runtime control plane

- Frontier: emulator/ADB setup was still consuming most runtime-task wall time, especially around stale `emulator-5582 offline`, repeated hosts/mount/display checks, and accidental full APK install/restart loops.
- Hypothesis: making `127.0.0.1:5583` the fixed primary serial and splitting runtime work into fast health, ADB repair, baseline, launch, observe, patch, install, and explicit restart commands will prevent agents from rediscovering the same emulator state.
- Changed one variable: added `work/kssma-runtime-lib.ps1` and `work/kssma-runtime.ps1` as the runtime control plane; changed `work/android44-arm19.ps1` into a compatibility shim; updated `kssma-re-runtime` skill and `kssma_runtime_check.ps1` to use the new control plane.
- Runtime rules:
  - primary serial is `127.0.0.1:5583`; `emulator-5582` is diagnostic/legacy only.
  - `fast-health` only runs `adb connect 127.0.0.1:5583` plus ABI/release/boot `getprop`.
  - `restart-runtime` is destructive and must include `-Force -Reason`.
  - `launch` starts the game only; `run` performs one `ensure-baseline`.
  - `observe` collects requested artifacts only.
- Checks:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 fast-health` returned `ok=true`, serial `127.0.0.1:5583`, Android `4.4.2`, ABI `armeabi-v7a`, boot `1`, elapsed about `881ms`.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 connect` returned `ok=true`, warned that other devices exist and `emulator-5582` is offline, and still selected only `127.0.0.1:5583`.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 ensure-baseline` restored missing hosts and bind mounts, then hot-cache rerun returned in about `965ms`.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 restart-runtime` without `-Force -Reason` failed as expected with `failureClass=restart-requires-force-reason`.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 start` still works through the shim and maps to `ensure-runtime`.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 patch-lib -ApkPath .\work\million-cn-animationguard-signed.apk` patched only `librooneyj.so` and verified the installed hash in about `14.3s`; no full APK install or emulator restart was used.
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 run -WaitSeconds 1 -Observe Activity -Tag runtime-smoke-control-plane` performed one cached baseline, launched `LogoActivity`, and wrote `work/kssma-runtime-runtime-smoke-control-plane-activity.txt`.
  - `node .\server\test-bootstrap-server.js` passed.
- Conclusion: runtime control now has a fast, evidence-bearing entry path. A stale `emulator-5582 offline` with `127.0.0.1:5583 device` must not trigger restart or emulator switching. Future agents should report the JSON `failureClass`/`recommendedCommand` instead of looping on raw ADB commands.
- Next: for gameplay/protocol tests, use `fast-health` first, `ensure-baseline` only once per run, `launch`, and then `observe` with explicit artifact classes. Use `diagnose` only when lightweight commands fail or a full artifact bundle is required.

## Runtime harness hardening during exploration validation

- Frontier: start real-device validation of the exploration floor blocker without losing time to helper false negatives.
- Hypothesis: the one-shot login helper and runtime control plane were failing the wrapper, not the game: successful `ensure-baseline` JSON was being treated as a failed phase, failed runtime commands could print no JSON, and a fresh runtime-state cache could hide missing hosts after a reboot.
- Changed one variable: tightened helper behavior only, without changing APK protocol semantics. `kssma_runtime_check.ps1` now refreshes `Start-Process` before reading `ExitCode` and treats a null post-wait exit code as 0; `work/kssma-runtime-lib.ps1` now uses `ConvertTo-Json -InputObject` and only accepts baseline cache when `hostsOk`, `mountOk`, `displayOk`, `audioOk`, and `packageOk` are all true.
- Server check: `node .\server\test-bootstrap-server.js` passed.
- ARM19 check: `restart-runtime` without `-Force -Reason` now reliably prints JSON with `failureClass=restart-requires-force-reason`; `ensure-baseline` after reboot rechecked hosts/mount/display/audio/package and restored missing hosts/mount instead of trusting stale state; `kssma_runtime_check.ps1 -DriveLogin -DismissNoticeWebView -Tag explore-floor-id1-login3` reached `com.test.RooneyJActivity` and recorded login plus `/connect/web/`.
- Observed: before the helper fix, the one-shot script failed at `ensure-runtime-baseline` even though the embedded runtime JSON had `ok=true`; after the fix, the script reached the real login/main-menu state. After reboot, the old cache marked `hostsOk=True` even though `/system/etc/hosts` had been reset; the stricter cache rule forced a real hosts check and repair.
- Conclusion: these were runtime-control bugs, not exploration protocol evidence. Keep the fixes; otherwise future real-device validation can stop before the game observable and send agents back into ADB/server noise.
- Next: if a runtime command exits nonzero or produces no JSON, treat that as a helper regression to fix immediately before interpreting any game behavior.

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

## Project constraint update: gameplay flow edges and known-good path reuse

- Frontier: the old project rules still reflected the startup-chain era and
  could push gameplay work back toward "next request", XML guessing, or one
  local UI flag at a time.
- Hypothesis: the two accepted exploration fixes show a better rule:
  gameplay work should validate an entire flow edge and should prefer reusing a
  proven correct path over locally reconstructing UI state.
- Changed one variable:
  - Updated `AGENTS.md`, `clean-start.md`, and `readme.md` only. No server XML,
    APK, native library, resource, or runtime state was changed.
- New rule substance:
  - Startup can still proceed by next route.
  - Gameplay proceeds by flow edge:
    `user action -> request/response -> client state switch -> visible UI -> next click target/route`.
  - HTTP 200 is not a gameplay success criterion.
  - If an already-accepted correct path can produce the target UI/state/route,
    write a path card and statically recover that complete path before product
    patching.
  - Repeatedly emitting the previous-layer route after a supposed layer switch
    is strong evidence that foreground/click ownership did not change; do not
    keep guessing XML fields in that case.
  - After two failed local UI/state/behavior patches, the next round must use
    known-good path diff/reuse or a read-only classifier, not another local
    behavior/flag patch.
  - Exploration-specific text now explicitly rejects continuing `area_list_sp`,
    `+0x84`, XML-only, and `floor_info` sweeps without new native evidence.
- Conclusion:
  - These rules preserve the useful safety gates while removing the wording that
    made agents overfit to tiny local state fixes. Future exploration work
    should start from the layer/flow-edge question before touching XML, draw
    flags, or behavior names.
