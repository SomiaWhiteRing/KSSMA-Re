# Fairy post-battle and battle-visual path card (2026-08-17)

## Frontier

```text
ordinary fairy challenge
-> /connect/app/exploration/fairybattle
-> scene 4100 -> scene 4301 -> scene 4420
-> ordinary dead fairy must not replay the encounter animation
```

The same battle must render the resource owned by its `master_boss_id`, rather than the generic
soldier fallback. This card changes server response data only. Scene selectors, battle actions,
settlement arithmetic, native code, APK resources, rare-fairy generation, BC, drops, and co-op are
non-goals.

## Accepted entry and wrong result

- `work/kssma-flow-fairy-battle-smoke-fairy-battle-dynamic-acceptance` proves the accepted request
  and scene path: `/exploration/explore -> /exploration/fairybattle(user_id=1,
  serial_id=100001) -> 4100 -> 4301 -> 4420`.
- `screenshots/fairy-battle-4000ms.png` shows the enemy name as 小龙女 but renders a generic silver
  soldier.
- `screenshots/fairy-battle-10000ms.png` and `fairy-battle-18000ms.png` return to the old encounter
  surface. The 18-second screenshot differs from the pre-battle encounter by only `0.02`, while the
  saved fairy is already at zero HP and `battle.fairy.active` is null.

## Post-battle state path

- `_ExplorationModel::init(smart_ptr<_ExploreTagData>)` at `0x001D6700` copies
  `ExploreTagData+0x04` to `ExplorationModel+0x68` and initializes both `_FairyModel` and
  `_RareFairyModel` from the same explore record.
- `_ExplorationMain::preUpdate()` at `0x00347104` calls
  `_ExplorationMain::newEventCheck()` at `0x003454A0` when the result scene settles.
- `newEventCheck()` dispatches `ExplorationModel+0x68 == 1` through the ordinary fairy event path.
- The current fairybattle body contains only `battle_vs_info`, `battle_battle`, and `battle_result`.
  It therefore leaves the previous exploration `event_type=1` and fairy model alive when scene 4420
  reuses `layout_exploration_fairy.xml`.
- `battle_result.event_type` is a different field: `_BattleModel::init(BattleResultTagData)` at
  `0x001CAF28` stores it at `BattleModel+0x88`; changing that value does not clear the exploration
  event consumed by `newEventCheck()`.

The correct response reuse is to append the same shipped `<explore>` model path with the current
floor progress, zero move rewards, `event_type=0`, `encounter=0`, and no fairy/rare-fairy child.
This updates the whole model through its original parser instead of patching a scene flag. A future
awakened-fairy settlement must put a real `rare_fairy` object into this response and select the
statically recovered rare branch; an ordinary kill must not synthesize that animation.

## Battle enemy resource path

- `_BattleBattlePlayerTagParser::parse()` at `0x002F0D68` parses `type` at player data offset
  `+0x0c` and `size` at `+0x10`.
- `_BattleBattleBoss::init()` at `0x0031C524` copies those to its enemy status. At `0x0031C980` it
  reads enemy `type`, calls `rooney::res::getMasterBoss(type)`, calls
  `_MasterBoss::getCardImageId()`, then `rooney::res::getBossImage(imageId)`.
- The shipped `master_boss` row is structurally:

  ```text
  master_boss_id=30024, master_card_id=600, name=小龙女,
  hp=9660, card_image_id=600, boss_version=161
  ```

  and the matching resource is `pack/161/boss/boss600_0.pack`.
- The current server hardcodes both players to `<type>2</type>`. The enemy therefore looks up boss
  row 2 instead of row 30024. The earlier assumption that `visualMasterCardId=600` alone selected
  the battle sprite is falsified by the accepted screenshot.

The closed mapping is: keep player type 2 from the shipped player sample, set enemy type to the
encounter `masterBossId` (30024), and retain size 0. This makes the original boss scene perform the
`30024 -> image 600 -> boss600` lookup itself.

## Minimum observable and stop

- The response log must expose `explorationEventType=0`, `enemyBattleType=30024`, and
  `enemyBossImageId=600`.
- The flow must prove the 18-second frame is no longer the pre-battle encounter surface and the
  foreground Activity remains alive.
- The 4-second battle frame must visibly replace the generic soldier with 小龙女's boss resource.
- If two response-only candidates produce neither a new terminal-frame observable nor a changed
  enemy rendering, stop and record both results before considering a native or resource patch.

## ARM19 acceptance

- Command:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario fairy-battle-smoke -Tag postbattle-visual-masterboss
  ```

- Artifact `work/kssma-flow-fairy-battle-smoke-postbattle-visual-masterboss` passed on
  `emulator-5556` in `172.559s` with the exact
  `/exploration/explore -> /exploration/fairybattle(user_id=1,serial_id=100001)` edge and scenes
  `4100 -> 4301 -> 4420`.
- The response records `explorationEventType=0`, `enemyBattleType=30024`, and
  `enemyBossImageId=600`. The VS frame and the 1s/4s battle frames visibly render 小龙女 instead
  of the generic soldier fallback.
- The 18s frame is the exploration return surface, not the old `HP 6000/6000` encounter. Its
  screenshot diff from the pre-battle encounter is `66.52` (the rejected response differed by
  only `0.02`). The save agrees on fairy HP zero, `active=null`, and one win.
- `RooneyJActivity` remains `RESUMED`, and logcat contains no fatal Java/native process signature.

This accepts the ordinary-fairy post-battle model refresh and battle enemy resource mapping. It
does not make every ordinary kill awaken: actual awakening remains a separate server decision that
must emit a real `rare_fairy` record before the client may play the awakened-fairy branch.
