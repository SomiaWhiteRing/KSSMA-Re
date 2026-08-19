# Fairy battle BC debit and shortage boundary (2026-08-19)

## Bounded round

- **Frontier:** `fairy challenge -> /connect/app/exploration/fairybattle -> BC decision -> battle/result/save`.
- **Success:** recover the battle cost rule, make the successful debit atomic with settlement, prove the response
  header and saved BC agree, and reject an underfunded request without changing battle/fairy/reward state.
- **Non-goal:** card/parts drops, reward box, rare fairy, assist/multiplayer, or a guessed visible error dialog.
- **Stop:** if the accepted client cannot statically present the existing no-BC layout, stop at a fail-closed server
  boundary and do not invent response XML.

## Cost rule evidence

- The accepted client request still sends only `user_id` and `serial_id`; the server is authoritative.
- The saved-deck path resolves each active slot through owned-card serial id to card master id. The recovered
  480-card master table has the authoritative per-card `cost` field and exact source SHA-256
  `7B121DE5626DD3B9820022C698A1FF754F87CAC4B64E563B70138F68B3A56BDF`.
- Contemporary Dengeki guides describe deck construction as the sum of card costs within BC and explicitly warn
  that an auto deck can consume all BC in one battle; they recommend a cheaper deck to fight a fairy several
  times. These descriptions support `battle BC cost = active deck card COST sum`:
  - https://dengekionline.com/elem/000/000/534/534734/index-2.html
  - https://dengekionline.com/elem/000/000/543/543061/index-2.html
- The current default deck contains only master card `22`, whose recovered cost is `10`; its deterministic
  acceptance edge is therefore `25 -> 15`.

## Implemented server contract

- `getFairyBattleBcState` resolves the active deck and sums recovered master-card costs. Missing master-card data
  is an error rather than a zero-cost fallback.
- `createFairyBattleSettlement` checks funds before mutation, debits the sum, and then performs battle, rewards,
  fairy state, counters, and history on the same in-memory save before the existing atomic rename.
- The encrypted success response publishes the post-debit value through the already accepted
  `<your_data><bc><current>...` header. Logs and history expose `bcBefore`, `bcCost`, and `bcAfter` for audit.
- The admin status page now shows `active deck COST / current BC`; the existing player editor remains the control
  for current/max BC.

## Insufficient-BC stop boundary

- `layout_exploration_fairy.xml` contains `battle_stanby_no_bc`, `battle_stanby2_no_bc`,
  `fairy_stay_non_bc`, and `fairy_lose_non_bc`; these hide the battle affordance and expose BC recovery.
- In this exact client, `_ExplorationMain::BcCheck::exec` and `BcCheck2::exec` directly trigger only the
  `*_max_bc` behaviors, while `_ExplorationMain::isBcFull()` is `movs r0,#1; bx lr`. A server error response cannot
  reliably select the existing no-BC layout.
- An underfunded request therefore fails closed at HTTP 409 and does not write the save. This is a server trust
  boundary, not an accepted client-facing shortage presentation. The next product patch must restore the native
  producer for the existing no-BC behaviors; parser-minimum `code=1` XML remains prohibited by the already recorded
  missing generic-dialog presentation edge.

## Checks and observable

- `node .\server\test-bootstrap-server.js` passed. It proves:
  - card `22` resolves to cost `10`;
  - `9/10` rejects with HTTP 409 and leaves BC, active fairy HP, wins, and history unchanged;
  - `25/10` returns encrypted success with header BC `15` and saves history `25/10/15`;
  - win and loss attempts both charge BC.
- MuMu Android 12 flow passed in `139006 ms` without changing its native `1440x2560/360dpi` display:
  `work/kssma-flow-fairy-battle-smoke-mumu-a12-bc-deduction-acceptance/summary.json`.
- Its request chain was `area -> floor -> get_floor -> explore -> fairybattle -> get_floor`. The battle response
  logged `bcBefore=25`, `bcCost=10`, `bcAfter=15`, the saved history matched, the active fairy was null, and the
  10-second screenshot visibly shows `YOU WIN / 777 Gold / 7 EXP`; the 18-second exploration screenshot visibly
  shows the BC gauge at `15/25` and differs from the encounter surface by `64.43`.
- `server.err.log` is empty and the flow fatal scan found no client fatal signal.

## Next frontier

Restore one native entry that chooses the existing `*_no_bc` layout from `current BC < active deck COST`, with a
path card, byte guards, branch map, accepted-library hash check, and one route-quiet A12/ARM19 observable. Do not
change the server success XML or guess a new shortage dialog in that round.
