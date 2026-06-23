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

## Practical blocker

Without the runtime `k2`, plain HTTP stubbing is not enough for the main native routes.

So the shortest next step is:

1. hook `com.test.Utils.sendK`
2. print `k1`, `k2`, and `urlTop`
3. proxy one real request
4. reproduce the crypto in a local server

## Android 4.4 ARM runtime

The useful local runtime is now `kssma_arm19` on the classic ARM emulator:

- Android: `4.4.2` / API 19
- ABI: `armeabi-v7a`
- Emulator: `C:\Users\旻\AppData\Local\Android\Sdk-classic-arm\tools\emulator.exe`
- ADB serial: `emulator-5582`
- Console/ADB ports: `5582,5583`
- Data partition: `1024M`
- SD card image: `C:\Users\旻\.android\avd\kssma_arm19.avd\sdcard.img` (`512M`)
- Start/install/run helper: `work/android44-arm19.ps1`

Useful commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 configure
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 install -ApkPath .\work\million-cn-animationguard-signed.apk
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 preload-rest
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 preload-small
powershell -NoProfile -ExecutionPolicy Bypass -File .\work\android44-arm19.ps1 run
```

Notes:

- The APK is ARM-only (`lib/armeabi/librooneyj.so`), so this avoids the BlueStacks x86/Houdini false target.
- Install must use `adb install -r -f` because the manifest has `android:installLocation="preferExternal"` and Android 4.4 external ASEC install is unreliable here.
- `-gpu on` removes the `called unimplemented OpenGL ES API` noise seen with `-gpu off`.
- `-no-jni` made the classic ARM emulator stay offline, so do not use it as the default.

Current ARM runtime blocker:

- The app reaches the local server on the ARM runtime:
  - `POST /check_inspection?cyt=1`
  - `POST /connect/app/notification/post_devicetoken?cyt=1`
  - `POST /connect/app/login?cyt=1`
- Without preloading `save/download/rest`, the first resource miss is `save/download/rest/que_adv`; Java throws in `JResourceLoader.loadFile`, then CheckJNI aborts in `librooneyj.so!jni_loadTexture`.
- `work/android44-arm19.ps1 preload-rest` pushes the 49 MiB `download/rest` sample set and fixes that false blocker.
- `work/android44-arm19.ps1 preload-small` also pushes the small `download/scenario` and `download/pack` dumps before retesting tutorial flow.
- After preloading `rest`, the app gets past `que_adv` and crashes later on real ARM:
  - `Fatal signal 11 (SIGSEGV)`
  - `ResourceManagerEx::exists(String)+25`
  - stack: `ResourceManagerEx::exists -> rooney::res::exists -> _Tutorial::loadScript -> _Tutorial::init`
- This is no longer the BlueStacks `libhoudini.so` crash. Next work should inspect tutorial script/resource names required after `local_forward_tutorial.xml`.
