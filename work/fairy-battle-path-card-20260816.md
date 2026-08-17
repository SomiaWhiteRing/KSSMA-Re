# Fairy battle path card (2026-08-16)

## Frontier

Restore the original-client edge without inventing a battle screen:

```text
scene 6202 exploration_fairy
-> challenge button
-> /connect/app/exploration/fairybattle(user_id, serial_id)
-> scene 4100 battle_vs (with fairy battle state 6)
-> scene 4301 battle_battle_faily
-> battle_result.result_scene
```

Player-owned battle data, production damage calculation, reward persistence, repeat attacks, defeat,
other attackers, rare fairies, and the post-result return edge are outside the first response-path
experiment in this card.

## Accepted entry and target observable

- Accepted entry: `work/kssma-flow-exploration-forward-visual-smoke-20260816-223933` reaches the
  original 小龙女 fairy surface. Pressing its original challenge target emits
  `/connect/app/exploration/fairybattle` with `user_id=1` and `serial_id=100001`.
- Current wrong-path result: the server returns 501 and the foreground becomes the client's network
  retry dialog.
- Target result: a 200 response initializes the shipped battle models, shows the original VS/battle
  presentation, and advances without another server request to scene 4301.
- Minimum observable: request order contains `/exploration/explore -> /exploration/fairybattle`, a
  screenshot shows the original battle/VS UI, or a scene/activity observable proves the migration.
  HTTP 200 by itself is not acceptance.

## Native request, parser, and scene path

- `layout_exploration_fairy.xml` command `battle` reaches
  `_ExplorationMain::Battle::exec(int)` at `0x003438E0`.
- `_BattleModel::battleFairy(int,String)` at `0x001CCDC8` submits route id `0x27` with exactly
  `user_id` and `serial_id`, then stores battle state `6` at `_BattleModel+0x2c`.
- `_BattleModel::init(TiXmlElement*)` at `0x001CB184` recognizes and initializes these response body
  children:
  - `battle_vs_info` through `_BattleVSInfoTagParser::parse`;
  - `battle_battle` through `_BattleBattleTagParser::parse`;
  - `battle_result` through `_BattleResultTagParser::parse`.
- The APK's bundled `local_battle_result.xml` is an original complete response containing all three
  model sections. It is the known complete response path used by the first experiment; only its
  scene selectors are changed, not its internal battle records.
- The bundled original battle response uses generic `next_scene=4100` (`battle_vs`). The battle model's
  stored fairy state selects the fairy-specific continuation; `4103` exists in `rule_scene.xml` as a named
  alias/cause but is not a constructible `_SceneFactory` case in this CN native.
- `_BattleVS::update(...)` at `0x0032B694` calls
  `_BattleModel::battleBattleExploration()` when its VS animation completes.
- `_BattleModel::battleBattleExploration()` at `0x001CA200` maps stored state `6` to literal
  `0x10CD` (decimal 4301). `rule_scene.xml` maps 4301 to the original
  `battle_battle_faily` scene. No second HTTP response is involved.
- `BattleResultTagData.result_scene` is the data-owned exit from the battle engine. Scene 4420 maps
  to `exploration_fairy_result` and reuses `layout_exploration_fairy.xml` for the fairy result UI.

## Wrong-path connection and reuse rationale

The missing endpoint currently prevents the client from initializing any of its three battle
models. Reusing the complete bundled response path preserves the original VS animation, battle
engine, action sequence, result transition, and battle-state dispatch. Building a replacement HTML
or native-looking result page would not exercise those contracts and could not prove that the
client can run its own battle flow.

The first candidate deliberately keeps the bundled battle records intact. If that candidate does
not produce a new scene, the result is a response-path/schema finding. If it does, the next bounded
round may replace the sample records with one dynamically built player/fairy battle while keeping
the now-accepted path unchanged.

## Candidate 1 runtime result: rejected at scene creation

- Command: `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow
  -Scenario fairy-battle-smoke`.
- Artifact: `work/kssma-flow-fairy-battle-smoke-20260816-230217`.
- The accepted encounter page emitted exactly
  `/connect/app/exploration/fairybattle(user_id=1, serial_id=100001)`. The server returned the
  complete bundled three-section response with `next_scene=4103`, battle state 6/scene 4301, and
  `result_scene=4420`.
- This did not reach a visible VS frame. The client immediately raised `SIGSEGV` at address `0x4`;
  the native backtrace starts at `_SceneControl::create(int)+105`, then
  `_SceneControl::update(AudioMan*, bool)+526`. Every post-response screenshot is the Android crash
  dialog, and no later route exists.
- Conclusion: the `/fairybattle` request and body delivery path are proven, but the assumption that
  rule-scene id 4103 is constructible by this CN native is rejected. This is a scene-factory
  failure, not evidence that the battle body schema or animation executed. Candidate 2 must first
  statically identify a constructible battle/VS scene or prove the exact factory branch; changing
  battle values/rewards before that is not authorized.

## Candidate 2 static correction

- `_SceneFactory::create(int)` at `0x001FA9B0` has exact constructible cases for generic battle VS
  scene 4100 and player battle scene 4200. It has no exact/range case for 4102, 4103, or 4104.
- The same factory accepts the inclusive 4300..4302 battle-scene range through the shared branch at
  `0x001FBF54`, so the fairy continuation 4301 is constructible.
- The APK-bundled `local_battle_result.xml` itself uses `next_scene=4100`, not 4103. Therefore the
  second and final response candidate restores the bundled generic VS selector unchanged while
  retaining fairy state 6 and `result_scene=4420`.
- Minimum runtime observable remains a visible original VS/battle frame and a live Activity. If
  candidate 2 also produces no new scene observable, stop this response-candidate round and do not
  vary battle/reward fields.

### Invalid candidate-2 invocation (no product edge)

`work/kssma-flow-fairy-battle-smoke-scene4100-candidate2` never reached exploration. While the flow
was preparing a native title-screen tap, automatic login completed; the delayed tap then landed on
the main-menu deck button and emitted `/roundtable/edit`. The captured `mainmenu.png` is DeckScene,
and there is no `/exploration/area`, `/exploration/explore`, or `/fairybattle` request. This run is a
flow-driver race, not a candidate-2 result. The title tap is changed to the existing bounded direct
ADB tap pattern so it cannot spend several seconds in UI-dialog inspection after deciding the title
screen is active.

## Candidate 2 runtime result: battle path accepted

- Command: `powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow
  -Scenario fairy-battle-smoke -Tag scene4100-candidate2-valid`.
- Artifact: `work/kssma-flow-fairy-battle-smoke-scene4100-candidate2-valid` passed in 161.078s.
- Request order is `/exploration/explore -> /exploration/fairybattle`; the latter carries exactly
  `user_id=1, serial_id=100001`. The server response records scene path `4100 -> 4301 -> 4420`.
- Screenshots prove the original client executed the path: `fairy-battle-0200ms.png` is the original
  VS presentation, `fairy-battle-4000ms.png` is the animated battle engine, and
  `fairy-battle-10000ms.png` has returned to the fairy result layout. Diff scores from the encounter
  page are 76.71, 67.39, and 28.41. RooneyJ remained alive and logcat contains no native crash.
- Accepted scope: generic battle-VS scene 4100, fairy-state continuation 4301, and result-layout
  transition 4420 are constructible and the complete three-section response schema is accepted.
- Explicit limitation: the bundled sample still displays its Japanese sample users/cards/actions;
  the server reports `saved=false`, so real fairy HP, damage, win/loss, and rewards are not accepted
  by this artifact. The next bounded round may now replace battle records while retaining the
  accepted scene path.
