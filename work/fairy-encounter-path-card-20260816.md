# Fairy encounter path card (2026-08-16)

## Frontier

Restore one original-client flow edge without inventing a replacement screen:

```text
exploration forward
-> /connect/app/exploration/explore
-> ExploreTagData(event_type=1, fairy=...)
-> layout behavior fairy_floor
-> scene 6202 exploration_fairy
```

Battle animation, battle result parsing, reward settlement, rare fairy, fairy history, and
expired/dead fairy branches are explicitly outside this card.

## Accepted entry and expected result

- Accepted entry: the current `exploration-forward-visual-smoke` path reaches scene 6200,
  presses the original forward control, submits `/connect/app/exploration/explore`, consumes AP,
  persists the move, and displays the ordinary walking result.
- Target result: the same forward action and request must keep the existing AP/progress mutation,
  but a selected encounter response must move through the client's existing `fairy_floor`
  behavior into scene 6202 (`exploration_fairy`).
- Observable: the request sequence still contains `/exploration/get_floor -> /exploration/explore`;
  the post-forward screenshot/scene must show the fairy encounter surface. A 200 response alone is
  not acceptance.

## Native request and scene path

- `_ExplorationMain::newEventCheck()` at `0x003454A0` dispatches on
  `_ExplorationModel+0x68` (`event_type`). The `event_type == 1` case at
  `0x0034561E..0x00345676` stops walking, runs the ordinary prize trigger, performs the level-up
  gate, and branches to the hashed layout behavior `fairy_floor` at
  `0x00345DD0..0x00345DE2`.
- `layout_exploration_main.xml` defines behavior `fairy_floor` and issues command `fairy`.
- `_ExplorationMain::Fairy::exec(int)` at `0x00343120` writes exploration state `0x60` and calls
  `_ExplorationModel::fairyFloor()` at `0x001D6230`.
- `_ExplorationModel::fairyFloor()` passes literal `0x183A` (decimal 6202) to the client's existing
  scene/connect path. `rule_scene.xml` maps scene 6202 to `exploration_fairy` and
  `layout_exploration_fairy.xml`.
- `_ExplorationModel::init(ExploreTagData)` at `0x001D6700` initializes the singleton
  `_FairyModel` from `ExploreTagData+0x50` before the event dispatch. Therefore the encounter must
  be delivered as the original nested `<fairy>` object in the `/exploration/explore` response; a
  hand-built scene jump would skip required model state.

## FairyTagData schema

`_FairyTagParser::parse(TiXmlElement*)` at `0x002FACF4` and
`_FairyModel::init(FairyTagData)` at `0x001D9688` close the ordinary fairy object as:

| XML field | parsed meaning |
| --- | --- |
| `serial_id` | encounter identity used by the battle request |
| `master_boss_id` | row in the shipped `master_boss` database |
| `name` | display name |
| `lv` | displayed fairy level |
| `hp` | current HP |
| `hp_max` | maximum HP |
| `time_limit` | remaining encounter time |
| `discoverer_id` | discovering user id |
| `rare_flg` | ordinary/rare discriminator |
| `event_chara_flg` | event-character discriminator |
| `attacker_history` | optional nested attacker list |

The shipped `save/database/master_boss` has 285 structurally valid rows. Row `30024` resolves to
master card/image `600`, name `小龙女`, base value `9660`, and matches the bundled
`pack/161/boss/boss600_0.pack`; it is the first selected ordinary-fairy visual baseline.

## Following battle edge (closed statically, not patched by this card)

- `layout_exploration_fairy.xml` command `battle` reaches
  `_ExplorationMain::Battle::exec(int)` at `0x003438E0`.
- It calls `_BattleModel::battleFairy(int,String)` at `0x001CCDC8`.
- The original request contains exactly `user_id=<discoverer id>` and
  `serial_id=<fairy serial id>`, then connects with route id `0x27`, whose shipped route string is
  `exploration/fairybattle`.
- This is enough to define the next protocol frontier, but the battle response and reward parser
  are separate schema cards and must be proven before product settlement code is added.

## Wrong-path connection and reuse rationale

The current server always returns `event_type=0`, `encounter=0`, and no `<fairy>` object, so the
client remains on the ordinary exploration result path. Reusing the full parser -> model -> event
dispatcher -> layout command -> scene 6202 path preserves the original level-up gate, model
ownership, button wiring, and subsequent `user_id + serial_id` request contract. Locally forcing a
scene id or recreating the fairy UI would lose those invariants and make the later battle edge less
reliable.

## ARM19 acceptance

- Command:

  ```powershell
  $env:KSSMA_FAIRY_ENABLED='1'
  $env:KSSMA_FAIRY_ENCOUNTER_RATE='100'
  $env:KSSMA_FAIRY_LEVEL='18'
  $env:KSSMA_FAIRY_MAX_HP='20000'
  $env:KSSMA_FAIRY_TIME_LIMIT_SECONDS='3600'
  powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow -Scenario exploration-forward-visual-smoke
  ```

- Accepted artifact: `work/kssma-flow-exploration-forward-visual-smoke-20260816-223933`.
- The server observable records `fairyEncounter=true`, rate `100`, serial `100001`,
  `masterBossId=30024`, level `18`, and max HP `20000`.
- `screenshots/after-forward-0200ms.png` visibly shows the original fairy screen with 小龙女,
  Lv.18, and HP `20000/20000` behind the network retry dialog.
- The next foreground click emitted `/connect/app/exploration/fairybattle` twice with decrypted
  `user_id=1` and `serial_id=100001`. The server returned 501 because the battle endpoint is not
  implemented yet. This is positive evidence for the encounter UI/click migration and the exact
  next frontier, not a battle acceptance.
