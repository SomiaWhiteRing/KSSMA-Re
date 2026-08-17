# Fairy post-battle settlement path card (2026-08-17)

## Frontier

```text
/connect/app/exploration/fairybattle
-> scene 4100 -> scene 4301 -> scene 4420
-> original fairy victory/result animation
-> visible Gold/EXP/level settlement
-> return click/next route
```

Success requires a visible settlement surface backed by the accepted dynamic `battle_result` values.
The defeated ordinary fairy must not replay its encounter animation, and the client must not stop at
the exploration background with only a return button. Rare-fairy generation, BC, drops, reward box,
and co-operation are non-goals for this response-only round.

## Accepted entry and wrong branch

- `work/kssma-flow-fairy-battle-smoke-postbattle-visual-masterboss` accepts the request, battle
  scenes, enemy boss resource, dead-fairy save, and removal of the stale `HP 6000/6000` encounter.
- Its 10s/18s frames contain only the exploration background and return button. The response appended
  `<explore><event_type>0</event_type>...`, which is the ordinary walking/no-event branch.
- `_ExplorationMain::newEventCheck()` at `0x003454A0` dispatches `event_type=0` at
  `0x003455AE` through `walk_stop`, `item_update`, ordinary prize checks, and finally
  `stand/recover_buttons`. That exactly explains the accepted blank result frame.

## Original scene-4420 settlement path

- `rule_scene.xml` maps scene `4420` to `exploration_fairy_result` with
  `layout_exploration_fairy.xml`.
- `_ExplorationMain::initModel(SceneInitializer)` at `0x00344138` parses an `<explore>` sibling with
  `_ExploreTagParser`, initializes `_ExplorationModel`, and installs the existing singleton
  `_BattleModel` as layout model `battle_model`.
- `_ExplorationMain::newEventCheck()` dispatches `ExplorationModel.event_type == 18` from
  `0x00345504` to the internal block at `0x00345FE0`.
- On the first entry, `0x00345FE6 -> 0x00346358` triggers the complete `area_fairy_dead` behavior.
  Its continuation triggers `reward_check_com` at `0x003463E2` (or after the existing bonus gate).
- `layout_exploration_fairy.xml` defines `area_fairy_dead` as the original boss/fairy victory
  presentation. Its `reward_check_com` behavior makes `btl_exp` and `item` visible, slides the item
  component, and invokes `levelCheckFairy`.
- The `btl_exp` node is already bound to `battle_model.beforeExp`, `afterExp`, `beforeGold`,
  `afterGold`, `beforeLevel`, `afterLevel`, and `winner`. These are populated by
  `_BattleModel::init(BattleResultTagData)` at `0x001CAF28`; the server's accepted dynamic
  `battle_result` already supplies them.
- The same native block triggers layout behavior `return` after the reward/level gate. If a real
  `_RareFairyModel` exists, the later part of the event-18 path converts it into the next fairy and
  continues to the rare appearance branch. An ordinary victory with no `rare_fairy` must stop after
  settlement/return and must not synthesize awakening.

## Response reuse

Keep the accepted `battle_vs_info`, `battle_battle`, `battle_result`, scene selectors, damage, and
persisted rewards unchanged. Change only the appended post-battle `<explore>` state from no-event
`event_type=0` to the statically closed fairy-victory result `event_type=18`, retaining
`encounter=0` and no fairy/rare-fairy child.

This reuses the client's complete original scene-4420 path. It is more reliable than manually
showing `btl_exp`, adding a new page, changing `result_scene`, or patching a draw flag.

## Observable and stop

- Response log: `explorationEventType=18`, with the already accepted battle/reward values.
- A post-battle screenshot must visibly contain the result/Gold/EXP presentation, not only the
  background and return button.
- After advancing/closing settlement, the next visible state or request must be recorded and the
  foreground `RooneyJActivity` must remain alive.
- If two response-only candidates do not produce a settlement frame or a new return observable,
  stop and record both before considering layout/native changes.

## Candidate 1 status

- Implemented the single response change above: the appended post-battle `<explore>` now has
  `event_type=18`, retains `encounter=0`, and contains no defeated `<fairy>` or synthetic
  `<rare_fairy>` object. The response log exposes `explorationEventType=18`.
- `node .\server\test-bootstrap-server.js` passed, including encrypted endpoint coverage, and
  `flow -Scenario self-check -Tag fairy-settlement-event18` passed with artifact
  `work/kssma-flow-self-check-fairy-settlement-event18`.
- The first ARM19 command was:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\work\kssma-runtime.ps1 flow `
    -Scenario fairy-battle-smoke -Tag fairy-settlement-event18-candidate1
  ```

  It stopped before login at `failureStep=repair-adb`, `failureClass=runtime-not-ready`, with
  an empty route sequence. Artifact:
  `work/kssma-flow-fairy-battle-smoke-fairy-settlement-event18-candidate1`.
- The permitted repair and one later `fast-health` observation both left `emulator-5556 offline`
  while ports `5556/5557` and the same AVD process remained present. The `/cache` mount warning is
  already known to occur in successful boots and is not reclassified as the cause.
- This is runtime-only evidence. Candidate 1 has not reached the client, so it is neither accepted
  nor rejected as a settlement response. Replay the exact same flow after `fast-health` reaches
  `armeabi-v7a / 4.4.2 / boot_completed=1`; do not change XML before that replay.
