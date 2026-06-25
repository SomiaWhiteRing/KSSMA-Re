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
