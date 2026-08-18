# Fairy battle settlement schema card (2026-08-16)

## Frontier and accepted parent path

This card changes only the records inside the accepted path:

```text
fairy challenge
-> /connect/app/exploration/fairybattle(user_id, serial_id)
-> battle_vs_info + battle_battle + battle_result
-> scene 4100 -> state-6 scene 4301 -> result scene 4420
```

`work/kssma-flow-fairy-battle-smoke-scene4100-candidate2-valid` already proves that the APK-bundled
three-section response drives the original VS, battle, and fairy-result scenes. Scene selection and
the request convention are frozen for this round.

## Shipped schema evidence

The complete `assets/bundle/local_battle_result.xml` and the three native tag parsers establish:

- `battle_vs_info` repeats `player`; each player contains `user_id`, `name`, one `user_card`,
  `status_friend`, and `status_yell`.
- `battle_battle` contains `back_id`, `bgm_name`, repeated `battle_player_list`, and repeated
  `battle_action_list`.
- A battle player contains `player_enemy`, `name`, `type`, `size`, `maxhp`, `hp`, repeated
  `card_list`, `ex`, and `maxex`.
- An attack action contains `action_player`, `attack_card`, `attack_type`, and `attack_damage`; a
  turn delimiter contains `turn`. The bundled sample visibly executes these records in scene 4301.
- `battle_result` contains `event_flag`, `event_type`, `winner`, before/after gold/exp/level values,
  the two shipped result subrecords, and `result_scene`. The accepted result selector is 4420.
- The bundled sample alone did not establish whether `winner` was a player index or a local-result flag. The first
  A12 run that visibly reached the result screen settled a real local victory but rendered `YOU LOSE` with
  `winner=0`. This direct client observable supersedes the action-list inference: `winner=1` is local victory and
  `winner=0` is local defeat.

## Dynamic local contract

- The active player deck is resolved from `cards.activeDeckId`; missing slots are ignored and the
  leader falls back to the first resolved deck card.
- Player HP is the sum of resolved card HP and each player attack uses that card's power. The
  ordinary fairy is represented by its recovered visual card master 600, with HP, level, and attack
  power snapshotted when the encounter is created.
- Combat alternates the player's resolved cards and one fairy attack until either side reaches zero.
  A hard 200-round guard is an intentional local ceiling; if reached, the higher remaining-HP ratio
  wins. This prevents an administrator-created billion-HP battle from generating an unbounded XML
  response. Upgrade path: persist multi-attempt raid state when an original repeated-attack capture
  is recovered.
- Victory grants configured gold and EXP, clears the active fairy, updates the discovered copy, and
  appends one compact history row. Defeat preserves the fairy's remaining HP for another challenge.
  Both outcomes increment the existing battle win/loss counters and are written atomically before
  the encrypted response is sent.
- BC is deliberately unchanged because the accepted path does not yet establish the original charge or
  insufficient-BC failure contract. Upgrade it as one captured retry/insufficient-BC edge rather than
  inventing a cost inside the settlement response.
- No card drop, factor piece, rare fairy, assist player, network co-op, or reward-box delivery is
  claimed in this round.

## Administrative controls

The existing local-only/token-protected fairy form gains three real runtime values:

- attack power (strength together with level and max HP);
- victory gold;
- victory EXP.

They are validated, written to `server/data/server/runtime-config.json`, snapshotted into new
encounters, and may be overridden in flow by `KSSMA_FAIRY_ATTACK_POWER`,
`KSSMA_FAIRY_REWARD_GOLD`, and `KSSMA_FAIRY_REWARD_EXP`.

## Success and stop

Success requires one ARM19 flow artifact with the configured fairy/card identities visible, a live
Activity through result scene 4420, response log values matching the simulation, and an artifact
player save whose fairy state, battle counters, gold, and EXP equal those logged values. HTTP 200 or
server-only tests are insufficient. After two dynamic record candidates without a new route,
visible scene, or persisted-state observable, stop and record the rejected hypotheses.

## Current verification state

- Server and flow self-checks pass for the dynamic settlement candidate. The integration response
  records a two-round win, emits master card 600, clears the active fairy, and atomically persists
  counters/rewards/history.
- The first ARM19 command was interrupted during login before any exploration or battle request.
  Artifact `work/kssma-flow-fairy-battle-smoke-dynamic-settlement-candidate1` contains no product
  observable and is not counted as a response candidate.
- After interruption, `fast-health` classified `adb-transport`; `repair-adb` found no target process
  or bound 5556/5557 ports, so it correctly refused the detached-runtime warm restart. A normal
  `start-runtime` then stopped before launch because the current execution sandbox denied access to
  `%USERPROFILE%\.android\avd\kssma_arm19.avd\config.ini`. Dynamic ARM19 acceptance remains pending;
  do not reinterpret the server tests as client acceptance.
- The browser-skill regression check was also stopped before navigation because its Node kernel was denied
  `lstat` access to `%USERPROFILE%\AppData`. The temporary server was closed and no QA player save was
  created. Existing API tests cover the new fields; a real browser pass for these three additions remains
  pending even though the previously accepted 639px M1 layout still covers the shared responsive grid.
- Permission recovery run accepted the dynamic damage/persistence slice:
  `flow -Scenario fairy-battle-smoke -Tag fairy-battle-dynamic-acceptance` passed on ARM19 in 180.341s;
  artifact `work/kssma-flow-fairy-battle-smoke-fairy-battle-dynamic-acceptance` records the exact
  `/exploration/explore -> /exploration/fairybattle(user_id=1,serial_id=100001)` edge and a live resumed
  `RooneyJActivity`. The battle frame visibly names 小龙女, starts at 6000 HP, reaches 0 HP, and leaves
  Arthur at 4620 HP. The response and artifact save agree on two rounds, 6000/1000 damage, gold
  `18 -> 795`, EXP `3 -> 7`, `wins=1`, cleared active fairy, and one matching history row; logcat has
  no native crash. This accepts dynamic battle records and atomic gold/EXP settlement on the client path.
- The same run exposes the next separate edge: at 10s and 18s the foreground is again the fairy layout but
  still renders the encounter snapshot as `HP 6000/6000`, while the artifact save has the fairy defeated and
  inactive. No reward summary or next click/route was captured. Do not claim post-result FairyModel refresh,
  defeated-page behavior, or replay rejection from this artifact; those require a new path card and flow edge.
- That separate edge is now accepted by
  `work/kssma-flow-fairy-battle-smoke-postbattle-visual-masterboss`. Appending a no-event `<explore>`
  sibling refreshes the original ExplorationModel path, so the 18s frame no longer replays the dead
  fairy; its diff from the encounter is `66.52`. Setting enemy battle `type` to master boss `30024`
  also makes the original `getMasterBoss -> getCardImageId -> getBossImage` path render boss image
  600 (小龙女), rather than the generic soldier. See
  `work/fairy-postbattle-visual-path-card-20260817.md`; actual rare-fairy generation remains separate.
