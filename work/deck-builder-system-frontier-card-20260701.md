# Deck Builder System Frontier Card, updated 2026-08-10

Frontier:
- D1 and D2 are accepted: main-menu bottom deck -> `/roundtable/edit move=1` -> scene `83200` -> visible
  `_DeckScene` -> leader `(1090,270)` -> client-local `change_mode_leader_select`, with three seconds of route quiet.
- D3 is statically closed in `work/deck-builder-edit-native-path-card-20260809.md`. The exact local edit path is
  card-select tab `(127,360)` -> sole candidate `(226,247)` -> reverse tab `(1144,360)`, remaining in scene `83200`.
- D4 is accepted in `work/kssma-flow-deck-builder-edit-smoke-deck-builder-edit-2`: serial 2 enters slot 1 in memory,
  all three local actions are route-quiet, and the artifact save remains deck `[1]` / leader `1`.
- D5 capture is accepted: decide emits exact `C=1,2,empty...` and `lr=1`, once, with no disk write.
- D5.5 rejected the response-only candidate `save_deck_card/result=0`: the explicit body arrived, but the client
  stayed on the populated DeckScene (`diff=0.05`). Static postmortem proved `next_scene=83200` pushes a new
  DeckScene whose `initModel` ignores `save_deck_card`; the old model result branch is bypassed.
- The `next_scene == 0` current-model delivery path is now statically closed, including HeaderTagData's default zero,
  Main's no-push branch, current LayoutScene pending-model dispatch, Circle update, and DeckScene result-zero back.
  Accepted exploration 50% -> 55% is the same-chain differential. C2-B later measured an accepted ARM19 warm boot
  at `tBoot=102.733s`, so the corrected D5.6 runtime round replayed the exact no-`next_scene` response once. The
  response was consumed, but the client emitted `/connect/app/mainmenu` 165ms later, violating the round's explicit
  three-second route-quiet success contract. The response/strict-flow experiment was removed and D5 capture-only
  restored. D6 remains blocked; do not reinterpret that stopped run as accepted or try another XML.
- D6-S is nevertheless statically complete. Native rules require complete empty three-slot groups to trail,
  preserve holes inside partial groups, reject repeated character ids, require a non-empty owned leader in the deck,
  and cap total cost at `bc.max`. `server/data/game/card-master.json` contains the clean 480-row character/cost map,
  generated and checked from the SHA-pinned accepted `master_card` by `work/generate-card-master-data.js`.

Known accepted state:
- `work/kssma-flow-deck-builder-entry-smoke-deck-builder-entry-1` passed on ARM19 `emulator-5556` with exact
  `move=1`, `command=round_table`, `nextScene=83200`, screenshot diff `68.86`, a live client, and a visibly populated
  12-slot DeckScene with the original `decide`, `leader`, `create_deck`, and `back` controls.
- `deck-builder-entry-smoke` now requires a DeckScene-specific 1280x720 color signature in addition to the route,
  scene metadata, activity, and screenshot-diff gates. The accepted DeckScene passes; its main-menu baseline rejects.
- The historical `mainmenu-bottom-buttons-smoke` artifact proved scene `10100` was a visible round-table viewer.
  That remains historical evidence only: `_RoundTableScene::update` has no deck-edit action, so the former
  `scene 10100 -> find edit button` assumption is explicitly deprecated.
- `work/kssma-flow-deck-builder-leader-mode-smoke-deck-builder-leader-mode-2` proves D2. After leader is tapped,
  no `connect_app_probe` appears for three seconds, screenshot diff is `37.89`, the right controls are disabled/dimmed,
  the left card rail remains active, and the client stays alive. The dedicated visual signature accepts this state and
  rejects the normal DeckScene and main menu. The `deck-builder-leader-mode-1` artifact is runtime-only evidence:
  it stopped at `restart-boot-timeout` before login or gameplay.

Static anchors:
- `rule_scene.xml`
  - `10100` = `round_table_scene`, layout `roundtable`.
  - `83100` = `card_select_scene`, layout `true`.
  - `83200` = `deck_scene`, layout `true`.
- `rule_resource.xml`
  - `round_table_scene` resources include `cmn_bg_00.png`, `ae_cardselect.png`,
    `ae_cardselect_deck.png`, and `round_table.xml`.
  - `card_select_scene` resources include `ae_cardselect.png`, `btl_deckmake_button.png`,
    `card_back.png`, and `cardselect_compound.png`.
  - `deck_scene` resources include `btl_deckmake_button.png`, `cmn_bg_00.png`,
    `icon_skill.png`, and `icon_combo.png`.
- `layout_roundtable.xml` binds `circle_table_model` fields:
  - `lockCards`
  - `deckCards`
  - `totalHp`
  - `totalAtk`
  - `totalCost`
  - `exGauge`
- `layout_deck_scene.xml` binds scene fields:
  - `deck`
  - `adapter`
  - `leader`
  - `offsc`
  and exposes commands `decide`, `leader`, `create_deck`, `back`.
- `layout_card_select_scene.xml` exposes deck-specific `deck_save` command `save_deck`.

Accepted route map:
- `/connect/app/roundtable/edit` -> `<roundtable_edit>` -> deck editor, scene `83200`.
- Scene `10100` -> round-table viewer only; it is not an editor entry.
- `/connect/app/cardselect/savedeckcard` -> save path with captured request keys `C` and `lr`; neither the current
  empty body nor the rejected explicit-zero candidate proves the successful response path/value domain.

Shared data prerequisites:
- Player save already has:
  - `cards.instances`
  - `cards.protectedInstanceIds`
  - `cards.decks[]`
  - `cards.activeDeckId`
  - `profile.leaderSerialId`
- The accepted player header already emits `owner_card_list`; this prevents leader-card lookup crashes.
- A real deck builder needs a clean card master baseline and enough owned card instances to populate card selection.

Current stop:
- `deck-builder-save-current-model-2` is valid evidence that the response immediately causes `/connect/app/mainmenu`,
  but it failed the user-approved route-quiet contract. Keep the ignored artifact and D5 capture-only server/flow.
- D6 persistence is frozen despite the completed D6-S data gate. A later plan must first resolve whether the
  main-menu request is an expected part of `LayoutScene::back()` and define a new acceptance contract; this round
  may not relax its gate or run another response experiment.

Non-goals while frozen:
- No full nine-card layout.
- No auto-build algorithm unless the client triggers it first.
- No compound/sell card flows.
- No card sorting or filtering beyond what is needed to select one owned card.
- No persistence, server response experiment, error-code invention, resource sync, native patch, or emulator restart.

Resume condition:
- New static evidence and an explicitly approved bounded contract explain the `/mainmenu` follow-up without treating
  HTTP 200, activity survival, or a route alone as save success. Until then, D5 capture-only is the accepted ceiling.

Do not repeat:
- Do not confuse the main-menu bottom deck entry with `/cardselect/savedeckcard`; runtime proved it is
  `/roundtable/edit move=1`.
- Do not return to scene `10100` looking for a deck-edit button.
- Do not treat the failed pre-login D5.6 invocation as product evidence or rerun it during the runtime-health round.
- Do not treat C2's `tShell=4.789` as valid or infer a boot deadline from the failed sampler; it stopped before 120
  seconds with no `tIdentity`, `tBoot`, or stable pair.
- Do not introduce a second save-response XML; a later D5.6 round may only reapply the already documented exact
  no-`next_scene` hypothesis.
- Do not implement deck persistence merely because the request shape is known; the success response edge is not.
- Do not call `deck-builder-save-current-model-2` accepted: it stopped on the required unexpected-route gate.
