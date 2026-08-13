# Deck-builder save capture native path card (2026-08-09)

## Round boundary

- Frontier: capture the original client's deck-save request after the accepted D4 in-memory edit.
- Success: prove the exact request keys and values, reject duplicate save requests, keep the client alive, and prove
  the artifact save is unchanged.
- Non-goal: no persistence, response-body change, inferred error code, or native patch.
- Stop: the repository has no original successful or failed response sample. Do not implement D6 until response and
  error semantics have evidence beyond the current empty-body behavior.

## Accepted source state

`work/kssma-flow-deck-builder-edit-smoke-deck-builder-edit-2` proves the D4 state using owned serials `[1,2]`,
persisted deck `[1]`, and leader `1`. The client-local DeckScene has serial `2` in slot 1 after
`(127,360) -> (226,247) -> (1144,360)`, while the disk save remains unchanged.

## Decide and request path

- `layout_deck_scene.xml` places `decide` at logical `(440,42)`, whose safe 1280x720 center is `(1090,95)`.
- `_DeckScene::Decide::exec` at `0x0033d1f0` calls `showDialogWithCheckingDeck` at `0x0033d014`. The valid path
  sets scene state 2, triggers `layout_lock`, and runs layout behavior `sort_deck`.
- `_DeckLayout::action` at `0x002b5198` handles that behavior at `0x002b51cc`, calls
  `_DeckStage::sortDeck` at `0x002bc8cc`, and returns command 10 (`connect_save`).
- `_DeckScene::ConnectSave::exec` at `0x0033c52c` copies the current deck and leader into
  `_CircleTableModel::save` at `0x001d159c`, triggers the model, and sets scene state 3.
- `_CircleTableModel::save` walks all 12 slots in index order at `0x001d15ca..0x001d160c`, joining them with
  comma `0x003d2bd8`; null slots use literal `empty` at `0x003d3ba4`. It inserts key `C` at `0x003d786c`, then
  leader key `lr` at `0x003d3bac`, and calls `Model::connect(74, map)` at `0x001d1734`.
- Route id 74 maps to `cardselect/savedeckcard` at `0x003d9b78`. `_ConnectionControl::connect` traverses the map
  in key order, yielding logical `&C=<value>&lr=<value>` before encryption.

For the accepted D4 state, the exact decrypted request must be:

```text
C=1,2,empty,empty,empty,empty,empty,empty,empty,empty,empty,empty
lr=1
```

The runtime probe must also reject extra decrypted parameter names; ordinary parameter matching alone does not.

## Response parser and branch behavior

- The response parent is `save_deck_card` at `0x003d3a70`.
- `_SaveDeckCardTagParser::parse` at `0x0030e0ac` accepts `result` (integer, tag `+0`), `error_message`
  (string, tag `+4`), `leader_card` (string, tag `+12`), and comma-split `deck_cards` (vector, tag `+20`).
- `_CircleTableModel::init` at `0x001d1278` copies those fields to model `+52`, `+56`, `+96`, and `+76`.
- If the response remains owned by the current scene, `_DeckScene::update` state 3 at `0x0033ce0c` waits for the
  model connection. At `0x0033ce6c..0x0033cf2c`, model `result == 0` calls `_DeckScene`'s
  `LayoutScene::back()` and unlocks; nonzero result unlocks and stays.
- `Model::isError` is checked before the application result branch. That generic connection-error path is separate
  from `save_deck_card/result` and does not recover a server error-code value domain.

This closes client branch behavior, not the original server value domain. No bundled XML, request log, or repository
sample supplies a successful `save_deck_card` body or any nonzero error value/message pairing.

The result branch does not inspect `leader_card` or `deck_cards`, so echo is not a success condition. However, an
explicit `save_deck_card` parent with those fields omitted initializes the model copies to empty values. Static
evidence does not prove whether a nonzero stay-on-page response needs echo to preserve the already-built layout.

## Current empty-body trap

The current generic server stub for `/connect/app/cardselect/savedeckcard` returns an empty `<body>` and never writes
the player save. `_CircleTableModel` initializes result `+52` to zero in its constructor. If the response parent is
absent, the model keeps that constructor-default zero. The first D5 runtime capture proved that this default alone
did not produce a visible `LayoutScene::back()`: the client remained on DeckScene. Therefore the dispatch/state
condition that makes the recovered result branch reachable was not closed by this trace.

Therefore a visible return after decide is a false-positive save observable. D5 must not call it successful
persistence and must not use the current response to select a D6 XML body.

## D5 runtime observable

1. Reuse the accepted D4 seed and local edit path.
2. Hash and read the artifact save before `/roundtable/edit`.
3. Move the request cursor, tap decide at `(1090,95)`, and capture exactly one
   `/connect/app/cardselect/savedeckcard` probe with the exact `C` and `lr` values above and no extra keys.
4. Move the cursor after the first request and require a three-second window without a duplicate save probe.
5. Record the current response and client state as diagnostic evidence only.
6. Require the final save text and SHA-256 to equal the pre-entry values.

D5 may close request capture. It cannot close D6 persistence or original error semantics from the current server.

## Runtime closure

`flow -Scenario deck-builder-save-smoke -Tag deck-builder-save-1` passed with artifact
`work/kssma-flow-deck-builder-save-smoke-deck-builder-save-1`:

- exactly one request carried the two expected case-sensitive parameters and no extras;
- no duplicate or follow-up request occurred;
- the generic empty-body placeholder produced no disk write;
- the response screenshot remained the same populated DeckScene (`diff=0.05`) with a live client;
- final save SHA-256 equaled the pre-entry value
  `8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`.

The current placeholder therefore did not visibly exercise the statically recovered explicit `result=0` return
branch. D5 is accepted as request capture only. D6 remains blocked on an evidence-backed explicit success response
and the unknown nonzero failure contract.

## Rejected D5.5 response candidate

`flow -Scenario deck-builder-save-smoke -Tag deck-builder-save-result0-1` tested one response-only variable. For the
already captured request, the server returned a parser-visible `save_deck_card` body containing explicit `result=0`
and the captured leader/deck echo; it did not write the save.

Artifact `work/kssma-flow-deck-builder-save-smoke-deck-builder-save-result0-1` proves:

- the exact request appeared once and the explicit response marker followed it;
- no duplicate or follow-up `/connect/app/*` request appeared in the response window;
- the client activity remained alive with no fatal/resource-miss evidence;
- the before/after screenshots remained the same populated DeckScene (`diff=0.05`);
- the artifact save remained SHA-256
  `8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`, deck `[1]`, leader `1`.

This falsifies the claim that a formed parent plus explicit numeric zero is sufficient to reach the visible back
edge under the current connect-74 path. The response experiment was removed from the product baseline. The next
round is static-only: recover response ownership/dispatch, `_CircleTableModel` state transitions, and the exact
condition under which `_DeckScene::update` reads model result. Do not vary `next_scene`, XML nesting, result values,
or persistence until that missing path is closed.

## Header-dispatch correction

The missing condition is now localized:

- `_CircleTableModel::save` at `0x001d159c` calls `Model::connect(74)` at `0x001d1734`; the scene triggers that model
  at `_DeckScene::ConnectSave::exec` `0x0033c578`.
- `_Main::connect` at `0x001c32d8` parses response-header `next_scene` at `0x001c35c4..0x001c35d0` and tests it at
  `0x001c3710`.
- Nonzero `next_scene=83200` reaches `_SceneControl::push(nextScene, parser)` at `0x001c3888`; its overload entry is
  `0x001f6af8` and carries the response parser into a new scene initialization.
- New `_DeckScene::initModel` at `0x0033c6c8` recognizes only parent `roundtable_edit` (`0x003e15f8`, branch
  `0x0033c6ea..0x0033c776`). It does not recognize `save_deck_card` (`0x003d3a70`).

Therefore D5.5 pushed/reinitialized scene 83200 instead of delivering the body to the old
`_CircleTableModel::update`; the nearly identical screenshot is consistent with that route. The recovered
state-3/result-zero tail remains valid only after current-model delivery. Repeated scene-id stack behavior is not
closed and must not be used as evidence.

## Current-model dispatch closure

The zero-scene delivery path is now statically closed:

- `_HeaderTagParser::parse` at `0x00301cec` initializes `HeaderTagData+0x08` to zero at `0x00301d1e`. It only
  overwrites that slot after matching `next_scene` at `0x003021e0..0x003021fc`, so an omitted tag has effective
  value zero rather than an unknown stale value.
- `_Main::connect` reads that value at `0x001c35b8..0x001c35d0`. Its zero branch at `0x001c3710` skips scene push,
  resets `_ConnectionControl` at `0x001c3970`, and returns true at `0x001c3986`.
- The response parser still owns the `<body>` element when `_Main::main` passes the body and connection result to
  `_Main::update` at `0x0018071c`. `_Main::update` builds the `SceneInitializer` from those values and tasks the
  pre-connect current scene rather than initializing a replacement scene.
- `_DeckScene::ConnectSave::exec` at `0x0033c52c` has already installed the same `_CircleTableModel` as the current
  pending model through `LayoutScene::trigger` at `0x001f3eb4`. The pending branch in `LayoutScene::task` at
  `0x001f3e40` calls that model's `setError` and vtable `+0x14` update before clearing the pending owner.
- `_CircleTableModel` vtable `0x00409bd0` maps `+0x14` to `_CircleTableModel::update` at `0x001d1354`. In save state
  2 it parses the direct `save_deck_card` parent and initializes model result; `_DeckScene::update` state 3 then
  consumes result zero and reaches `LayoutScene::back()`.

The accepted same-scene differential is `/connect/app/exploration/explore`: its response omits `next_scene`, and
artifact `work/kssma-flow-exploration-forward-visual-smoke-no-next-scene-visual` proves the current exploration
scene consumed the body by changing progress from 50% to 55% and showing the reward overlay. This exercises the
same `_Main::connect` zero branch and current `LayoutScene` pending-model convention.

Therefore the old "zero-scene delivery is unclosed" frontier is retired. D5.6 may test one response-only
hypothesis: keep the already tested `save_deck_card/result=0` body and echo unchanged, omit `next_scene`, make no
save mutation, and require a visible local back to the same-run main menu. This authorizes one runtime experiment;
it does not establish original-server success/error semantics or authorize D6 persistence.

## D5.6 runtime attempt

The single authorized invocation,
`flow -Scenario deck-builder-save-smoke -Tag deck-builder-save-current-model-1`, stopped before login or gameplay.
Artifact `work/kssma-flow-deck-builder-save-smoke-deck-builder-save-current-model-1` records
`failureClass=runtime-not-ready`, `failureStep=repair-adb`, and `restart-boot-timeout`. The route sequence is empty;
there is no deck entry, save request, probe response, or client-state observable. The failure screenshot is black
while ADB was returning during cleanup, and the seeded artifact save remains SHA-256
`8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`.

This is runtime-only evidence and neither accepts nor rejects the no-`next_scene` hypothesis. Per the round stop
rule, the response-only server and strict acceptance-flow changes were removed, restoring the D5 capture-only
baseline. Do not try another XML. A later round must first restore the accepted ARM19 health baseline; only a new,
explicitly bounded D5.6 round may reapply this exact hypothesis unchanged.

That corrected round re-applied the exact hypothesis once with tag `deck-builder-save-current-model-2`. D4, the
exact `C/lr` request, and the no-write response marker all passed. The client then emitted
`/connect/app/mainmenu` 165ms after the response. This is consistent with current-model delivery reaching a
back/main-menu transition, but it violates the round's explicit three-second no-follow-up-route contract, so the
flow stopped as `unexpected-route` before making a visual acceptance claim. The artifact save stayed byte-identical
at SHA-256 `8A3B41FE46F94B4147A1FAF74EA3BD4FF42C4DBCFFAE0BA1FDFA6D7A4007C68F`. Per the stop rule, the probe is
removed, D5 capture-only remains baseline, and persistence is not authorized. Do not silently redefine this failed
gate as accepted or try a second XML shape.

## D6-S deck value-domain closure

This section closes only the three requested save-input rules. It does not bypass the D5.6 response gate or recover
the original server's error XML.

Static source: current accepted `work/librooneyj-gacha-cardget-inner-touch-nullguard.so`, SHA-256
`DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`; the accepted gacha guard does not touch
the deck functions below.

### Empty-slot ordering

- Decide calls `_DeckScene::showDialogWithCheckingDeck` before the already recovered `sort_deck ->
  _DeckStage::sortDeck -> connect_save` path. In `_DeckStage::sortDeck` at `0x002bc8cc`, the first pass
  (`0x002bc8f8..0x002bc95c`) examines slots in index order and closes a group whenever `index % 3 == 2` at
  `0x002bc916..0x002bc920`.
- A group is marked empty only when all three slots are null. The `emptyCount == 3` branch records `true` at
  `0x002bcb14..0x002bcb90`; a partially occupied group records `false` at `0x002bc934..0x002bc94e` or
  `0x002bcb64..0x002bcb74`.
- The second pass (`0x002bc95e..0x002bcae0`) finds the first all-empty group followed by a non-empty group. It swaps
  exactly three positions with `_GrpIcon::swapIconWithMovement` and `_DeckStage::swapSerialOfDeck` at
  `0x002bc9a4..0x002bca20`, using `group * 3 + {0,1,2}`.

Therefore the client compacts only complete three-slot groups. The four groups are
`[0..2]`, `[3..5]`, `[6..8]`, and `[9..11]`; all-empty groups become a trailing suffix while relative non-empty
group order is retained. Empty holes inside a partially occupied group are preserved. D6 must not globally left-pack
cards. It should validate this client-normalized group order and persist the accepted 12 positions exactly; an
all-empty group before a later non-empty group is not an official-client Decide output and should use the invalid
request fallback rather than be silently rewritten.

### Duplicate serials

- `_DeckScene::showDialogWithCheckingDeck` calls `DeckUtil::checkDeck` at `0x0033d042` before `sort_deck` or save.
- `DeckUtil::checkDeck` resolves every non-empty serial through the `IPlayer` vtable `+0x40`, which maps to
  `_CPlayer::getUserCard(String)` at `0x001f00dc` (`0x002bc250..0x002bc27a`). It keys a local map by
  `_UserCard::getCharacterId()` at `0x002bc2a6..0x002bc2f2`.
- A second card with an existing character id branches at `0x002bc2b0..0x002bc2d6` and returns result `18` at
  `0x002bc3a0..0x002bc3ae`. The result-18 case in `_DeckScene::showDialogWithCheckingDeck` reaches
  `_DeckScene::showDialogSimilarCards` at `0x0033d144`, so no save request is emitted.

A repeated owned serial necessarily resolves to the same card and character id, so it is illegal. Native behavior is
broader: two distinct owned serials with the same character id are also rejected. The required server mapping is now
statically closed:

- Each player-owned instance already stores `serialId` and `masterCardId`. Native `_UserCard::getMasterCardId()`
  reads the owned-card tag value at `0x001f2cc8..0x001f2cd4`; `_UserCard::getCharacterId()` resolves its associated
  `_Card` and delegates to `_Card::getCharacterId()` at `0x001f3298..0x001f32b4`.
- The accepted
  `work/million_cn/sdcard_dump/sdcard/Android/data/com.square_enix.million_cn/files/save/database/master_card`
  has SHA-256 `7B121DE5626DD3B9820022C698A1FF754F87CAC4B64E563B70138F68B3A56BDF`. `_Card::serialize` writes `cost` at
  `0x001ec430..0x001ec438` and `characterId` at `0x001ec550..0x001ec558`. An exact record parser consumed all 480
  records to their declared boundaries: all 480 master ids and character ids are positive and unique, and every
  record has `characterId == masterCardId`.
- `work/generate-card-master-data.js` pins that source hash and serialization layout. It generates and checks
  `server/data/game/card-master.json`, a clean 480-row runtime table containing only `masterCardId`, `characterId`,
  and `cost`. The generated file SHA-256 is
  `0E7F2F4C590593CDFA21E4E5805841C2B32FB0CBFE2DBCE54B1AE8A030589466`.

Thus the usable mapping is `owned serial -> owned instance.masterCardId -> card-master.characterId`. D6 must reject
both repeated serials and distinct selected serials whose resolved `characterId` repeats. For this accepted table the
latter is equivalent to repeated `masterCardId`, but the validator should read the explicit field rather than bake in
that coincidence. An owned instance whose master id has no table row is unresolved and must also take the invalid
request fallback before mutation.

### Leader and non-empty deck

- A null/empty leader returns result `20` at `0x002bc1fc..0x002bc210`. An entirely empty 12-slot deck returns result
  `19` at `0x002bc3ba..0x002bc3e0`.
- For each non-empty slot, `DeckUtil::checkDeck` resolves the serial from `_CPlayer`'s owned-card map, obtains that
  `_UserCard`'s serial with `_UserCard::getSerialId()` at `0x002bc2f4..0x002bc304`, and compares it with `lr` through
  `_String::equals(String)` at `0x002bc30e..0x002bc320` (the `_String` vtable `+0x10` target is `0x0037b42c`).
- If no resolved deck card matches `lr`, the final branch at `0x002bc376..0x002bc382` returns result `20`. A match
  produces the valid `-1` result, subject to the separate cost check.

Thus a saved deck must contain at least one card, `lr` must be non-empty, and `lr` may name any non-empty deck slot
but must exactly match one of them. Because every accepted `C` serial must resolve from the owned-card map, this also
closes the owned-leader requirement. With duplicate serials rejected, the matching leader occurs exactly once.

### Cost and BC capacity

- `DeckUtil::checkDeck` calls `_UserCard::getCost()` while walking each resolved non-empty slot and accumulates the
  result at `0x002bc296..0x002bc2aa`. `_UserCard::getCost()` delegates to the associated `_Card::getCost()` at
  `0x001f338c..0x001f33a8`. After the walk, `0x002bc350..0x002bc36c` compares the total with
  `_CPlayer::getMaxBc()` and returns result `17` at `0x002bc36e..0x002bc382` when total cost is greater.
- The generated card master supplies the request-time cost for every accepted master id. Its 480 costs are positive
  integers in `[2,99]`; current rows are master `22 -> character 22, cost 10` and master
  `9 -> character 9, cost 3`.
- `_YourDataTagParser::parse` hands `<bc>` to `_BcTagParser::parse` at `0x00313a16` and stores the parsed object at
  `_YourDataTagData+108` at `0x00313a3e..0x00313a4c`. The parser's literal `max` branch stores the integer at
  `_BcTagData+4` at `0x002f3afa..0x002f3b16`.
- `_CPlayer::updatePlayerData` reads that `+4` value and calls `_StatusPoint::setMaxPoint` on `CPlayer+0x50` at
  `0x001f0af4..0x001f0b2e`. `_CPlayer::getMaxBc()` reads the same `CPlayer+0x50` object and calls
  `_StatusPoint::getMaxPoint()` at `0x001ee758..0x001ee768`.
- Server `renderYourDataXml` already passes `playerSave.resources.bc` to `renderGaugeXml("bc", ...)`; that renderer
  writes its `max` member as `<bc><max>...`. Therefore the request-time comparison source is exactly
  `playerSave.resources.bc.max`, not current BC, base BC, level, or an inferred limit. The current two-card fixture is
  cost `10 + 3 = 13` against `maxBc=25`.

D6 must resolve every selected owned serial through the card master, add the twelve-or-fewer costs without coercion,
require a canonical non-negative safe-integer `resources.bc.max`, and accept only `totalCost <= maxBc`. Unknown
master ids, missing/non-integer costs, invalid `maxBc`, or an over-capacity total all use the existing invalid fallback
with zero mutation.

### D6 validator handoff and evidence ceiling

The requested native and data value domains are statically closed. A D6 validator may accept only a canonical
12-token `C` whose non-empty serials are owned and resolve to adopted card-master rows, whose serials and resolved
character ids are unique, whose complete empty triplets form a suffix, whose non-empty owned `lr` appears in `C`, and
whose resolved total cost does not exceed the persisted BC maximum. It must preserve accepted slot positions rather
than normalize them again.

There was no existing server card-master file or loader; the minimal generated table above is the single adopted
source and should be loaded directly during D6, without a generic deck or master-data service. The generator is the
runnable provenance/schema check:

```powershell
node .\work\generate-card-master-data.js --check
```

This closes legality data, not persistence or wire error semantics. Persistence remains conditionally blocked until
the unchanged D5.6 no-`next_scene` response is accepted on ARM19; invalid requests must continue to use the existing
`83200` empty-body fallback rather than inventing a nonzero `<result>` or error XML.
