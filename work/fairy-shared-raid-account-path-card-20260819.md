# Shared fairy raid, account, and reward-box path card (2026-08-19)

## Bounded round

- **Frontier:** `account A explores -> loses -> fairy remains active -> account B selects/attacks it -> shared defeat -> contributor card rewards`.
- **Success:** two persisted local accounts select distinct saves; one shared raid permits only one live fairy per discoverer; every attacker is recorded on loss or victory; a defeat creates idempotent card rewards for all contributors; the existing reward-box claim path creates unique owned-card serials.
- **Non-goal:** client-side registration, arbitrary public Internet accounts, rare/awakened fairies, factor pieces, a guessed concurrent-session protocol, or visual acceptance of every co-op screen.
- **Stop:** if two response candidates do not produce a new route/scene/client observable, stop XML iteration and retain the server state machine plus static schema evidence.

## Accepted paths reused

### Own encounter and battle

The accepted local path is:

```text
exploration/explore <fairy>
-> ExplorationModel initializes FairyModel
-> visible fairy surface
-> exploration/fairybattle(user_id, serial_id)
-> battle_vs_info + battle_battle + battle_result
-> scene 4100 -> 4301 -> 4420
```

Artifacts and schema cards:

- `work/fairy-encounter-path-card-20260816.md`
- `work/fairy-battle-settlement-schema-card-20260816.md`
- `work/fairy-postbattle-visual-path-card-20260817.md`
- `work/kssma-flow-fairy-battle-smoke-mumu-a12-bc-deduction-acceptance`

### Friend fairy selection and floor

- `_FairyModel::selection()` at `0x001d8bb1` sends connect id `0x3c`, route `menu/fairyselect`.
- `_FairySelectTagParser::parse` at `0x002fc5cc` accepts repeated `fairy_event`, `message`, and `remaining_rewards`.
- `_FairyEventTagParser::parse` at `0x002fb184` accepts nested `user`, `fairy`, then `put_down`, `start_time`, and `reward_status`.
- `_FairyEventTagData` stores parsed `put_down` at offset `+0x00`, the nested `user` at `+0x10`, and the nested `fairy` at `+0x18`. `_FairyEventTagParser::parse` writes the integer parsed from `<put_down>` to `+0x00` at `0x002fb47c`.
- `_FairySelect::update` at `0x00357fa1` branches on that exact `+0x00` value. `put_down == 1` calls `_FairyModel::fairyFloor(String,int)` at `0x00358280`; every other value calls `_FairyModel::fairyHistory(int,String)` at `0x00358096`.
- The 2026-08-19 real-client request log closed this distinction: selecting the live `serial_id=100018` row while the server emitted `put_down=0` repeatedly sent `exploration/fairyhistory(user_id=1,serial_id=100018)` and left the client on the selection page. Therefore a live, attackable row must emit `put_down=1` so the original client calls `exploration/fairy_floor` with `serial_id`, `user_id`, and `check`.
- `_FairyFloorTagParser::parse` at `0x002fb618` accepts exactly two model children: `get_floor` and `explore`.

The product response must therefore reuse the already accepted complete get-floor and explore renderers:

```text
menu/fairyselect
-> fairy_event(user + fairy snapshot)
-> exploration/fairy_floor(discoverer user_id, serial_id)
-> scene 6202 exploration_fairy with fairy_floor(get_floor + explore(fairy))
-> original ExplorationModel/FairyModel surface
-> original battle button emits exploration/fairybattle
```

This is safer than constructing a new fairy page or forcing a scene/state flag: both child models, their parameter sources, and the next battle request already exist in the accepted client.

### Menu-origin scene stack and post-battle split

- `rule_scene.xml` declares scene `6202` as `exploration_fairy` and explicitly permits suspended cause
  `menu_fairy_select`. A selected menu fairy must therefore enter scene 6202 directly. Scene `6200` is
  `exploration_main`; it is the known-good ordinary exploration parent, not the menu-fairy target.
- The first direct-scene response incorrectly kept the ordinary encounter's `explore.event_type=1`. The
  2026-08-19 real-client replay reached `/menu/fairyselect -> /exploration/fairy_floor` for active serial
  `100019`, then rendered only `exploration_fairy`'s default background while `bgm_event1` played. The Activity
  remained resumed, the resource sentinels passed, logcat contained no texture/native fatal, and no later route
  appeared. This rejects a resource or transport failure and rejects event 1 as the menu-entry initializer.
- `_ExplorationMain::newEventCheck` proves why: event 1 is the exploration-only discovery branch which triggers
  layout behavior `fairy_floor`; that command calls `_ExplorationModel::fairyFloor()` and performs the local
  connection/scene transition to 6202. Replaying it after the server has already pushed scene 6202 does not select
  a visible detail behavior. Event 11 dispatches at `0x0034551e -> 0x003463bc` and its first exact behavior is
  `fairy_stay`. `layout_exploration_fairy.xml` defines `fairy_stay` as the complete live-fairy detail state: it
  shows the fairy/status, HP/time, AP/BC, battle/compound/back and scroll buttons, then unlocks the button group.
- The 2026-08-19 real-client capture proves the wrong stack: the live row emitted
  `fairy_floor(user_id=1,serial_id=100018)`, the server returned `next_scene=6200`, battle settlement was a loss
  (`playerWon=false`, `winner=0`), but the response still emitted exploration `event_type=18`; closing the result
  then produced `/exploration/get_floor` and visibly returned to exploration.
- `_ExplorationMain::newEventCheck` dispatches exploration `event_type=10` at `0x00345516` to
  `0x003462d2`, whose first layout behavior is `fairy_lose`. The shipped behavior leaves the fairy/status/battle
  surface visible and invokes `request_assist`. This is the original failed-battle return state.
- The accepted victory branch remains `event_type=18` at `0x00345504 -> 0x00345fe0`, ending through the existing
  settlement/`return` path. With the corrected direct stack `29200 -> 6202`, that return resumes scene 29200 instead
  of scene 6200.

The complete response map is therefore:

```text
menu_fairy_select (29200)
-> fairy_floor response next_scene=6202 + explore.event_type=11
-> exploration_fairy detail
-> fairybattle -> 4100 -> 4301 -> 4420
   loss: explore.event_type=10 -> fairy_lose -> detail remains attackable
   win:  explore.event_type=18 -> settlement/return -> suspended fairy list (29200)
```

### Contributor history

- `exploration/fairyhistory` takes `user_id` and `serial_id`.
- `_AttackerHistoryTagParser::parse` at `0x002edcd5` accepts repeated `attacker`.
- `_AttackerTagParser` rows contain `user_id`, `discoverer`, `user_name`, `attack_point`, `attack_times`, `country_id`, `status_friend`, `status_yell`, and `leader_card`.

The shared registry is authoritative for HP and attacker totals. Per-account `battle.fairy.active` remains a client-compatible mounted snapshot and is refreshed from the registry before exploration/fairy routes.

### Reward box

- `menu/rewardbox` is `_MailBoxModel::rewardbox()` connect id `0x40`.
- `_RewardBoxListTagParser::parse` at `0x0030d8f4` consumes `rewardbox_list`, repeated `rewardbox`, and `message`.
- Card rows use closed `type=1` fields: `id`, `type`, `title`, `card_id`, `item_id`, `point`, `get_num`, `content`, `date`.
- `menu/get_rewards` is connect id `0x41` and sends comma-separated integer `notice_id` values.
- `_GetRewardsTagParser::parse` at `0x00300b28` consumes `get_rewards(success, message, id_list)`.

Claim writes the generated card and a durable claimed reward id into the player save before marking the shared reward claimed. A retry sees the claimed id and cannot duplicate the card.

## Original-behavior research adopted for the local baseline

2026-08-19 update: the fixed `master_card_id=600` paragraph below records the first accepted shared-reward baseline.
It has been superseded by the per-slot drop percentage and weighted pool in
`work/fairy-gacha-pool-path-card-20260819.md`. The contributor/finisher counts and idempotent claim path are unchanged.

- Contemporary Japanese guides state that an attacker receives one card when the fairy is defeated and the player landing the finishing blow receives two cards total.
- A 2012 update note says the discoverer later became eligible for one reward even without attacking. This restoration deliberately follows the user's requested stricter rule for now: only accounts with at least one recorded attack are contributors.
- The original first reward baseline used resource-backed fairy card `master_card_id=600`. The current admin instead
  controls a weighted recovered-card pool and an overall per-slot drop percentage. Holographic probability and
  boss-specific named drop tables remain separate data frontiers.

Sources:

- https://w.atwiki.jp/kssma/pages/16.html
- https://w.atwiki.jp/kssma/pages/31.html
- https://www.inside-games.jp/article/2012/07/12/58138.html
- https://aruhinosora-master-piece.livedoor.biz/archives/5788428.html

## Account transport boundary

Captured Android 12 requests show credentials only on `/connect/app/login`; later gameplay requests contain neither login id, session id, cookie, nor authorization. MuMu NAT also presents every TCP connection as `127.0.0.1`, with a new source port for each request. The accepted native library contains no Cookie/Set-Cookie consumer string.

The first account implementation can therefore select a persisted save at login and supports deterministic sequential two-account play on one local server. It must advertise this limitation in the admin UI. True simultaneous clients require one new observable client identifier (accepted HTTP cookie replay, an original session parameter, or a narrowly scoped native transport patch); remote address heuristics are prohibited.

## Implemented product baseline

- `server/bootstrap-server.js` now owns a global raid registry. A raid remains `active` after a loss, is re-mounted into its discoverer's save, and prevents `shouldCreateFairyEncounter` from creating another live fairy for that account.
- Every successful battle response records or accumulates one attacker row even when the attacker loses. Assisting another account never clears the attacker's own mounted fairy.
- Defeat rolls every snapshotted contributor reward slot independently and creates type-1 notices only for successful
  card rolls. The baseline remains one slot per contributor plus one extra slot for the finisher.
  `menu/get_rewards` writes unique card instances and `rewards.claimedIds` before marking notices claimed, so a retry cannot duplicate cards.
- Until original friend approval/list membership is restored, enabled local accounts are mutual LAN friends. This is intentionally marked `ponytail:` in product code.
- Client-side `add_user.php` remains a compatibility response and does not create accounts. `/admin/api/accounts` is the only creation path, passwords use `crypto.scryptSync`, and probe logs redact password/token fields.
- The admin exposes account creation/selection and new-fairy snapshot controls for drop percentage, weighted pool,
  contributor slot quantity, and finisher bonus. It refuses pool IDs missing from the recovered 480-card master table.

## Verification

`node .\server\test-bootstrap-server.js` passes a deterministic two-account sequence:

```text
owner attack loses -> raid HP 9000 and remains mounted
friend attack wins -> two contributor rows
owner reward = master 600 x1
finisher reward = master 600 x2
owner claim -> one unique card added
same notice replay -> no duplicate card
```

The test also exercises admin account creation/authentication, wrong-password rejection, per-account save selection, no credential/hash fields in API responses, unknown reward-card rejection, and the reward-box XML parser shape.

MuMu Android 12 regression artifact:

- `work/kssma-flow-fairy-battle-smoke-mumu-a12-shared-raid-single-account-regression-r2`
- `summary.json`: pass, `127.0.0.1:7555`, no warnings.
- Route edge: `explore -> fairybattle(user_id=1,serial_id=100001) -> get_floor`.
- Client save: win 1, loss 0, active fairy cleared, BC `25 -> 15`, gold `18 -> 795`.
- Isolated `fairy-raids.json`: raid `100001` defeated, attacker `1` recorded as finisher, pending reward `master_card_id=600 x2`.

This real-client run accepts the existing single-account encounter/battle/result edge after the new state model. The two-account friend-selection page and reward-box claim page remain server/self-check accepted but not yet client-visual accepted.
