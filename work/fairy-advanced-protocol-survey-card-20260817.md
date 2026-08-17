# Fairy Advanced Protocol Survey Card (2026-08-17)

## Scope and evidence ceiling

This is the static handoff for the work after the accepted ordinary-fairy battle edge. It covers BC deduction and
shortage, immediate card/factor drops, the reward box, rare fairies, and LAN co-operation. It deliberately does not
add guessed XML or mutate the product server. The only dynamic claim in this card is the already accepted ARM19 run:

```text
explore
-> fairybattle(user_id=1, serial_id=100001)
-> scene 4100
-> scene 4301
-> scene 4420
```

Artifact `work/kssma-flow-fairy-battle-smoke-fairy-battle-dynamic-acceptance` passed on
Android 4.4.2/API19 ARM. It records 小龙女 HP `6000 -> 0`, Arthur HP `5620 -> 4620`, two rounds, Gold
`18 -> 795`, EXP `3 -> 7`, `wins=1`, the cleared active encounter, and a matching battle-history row. The Activity
remained resumed and no native fatal/crash line was present. The returned fairy layout still renders the old
`6000/6000` encounter snapshot, so post-result model refresh and the next click/route are separate unaccepted work.

Static symbols and addresses below are from the unique client-baseline `librooneyj.so`, SHA-256
`DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F`. The equivalent bytes inspected in
`work/million_cn/apktool/lib/armeabi/librooneyj.so` have the same functions and parser layouts.

## BC deduction and BC shortage

### Closed facts

- `_ExplorationMain::isBcFull()` at `0x00343274` is exactly `movs r0,#1; bx lr`. It is an unconditional true result
  in the accepted APK, not a runtime capacity calculation.
- `_ExplorationMain::BcCheck::exec` at `0x0034317c` and `BcCheck2::exec` at `0x00343160` only trigger
  `battle_stanby_max_bc` and `battle_stanby2_max_bc`. The corresponding no-BC layout behaviors exist but these
  handlers do not select them.
- `_ExplorationMain::Battle::exec` at `0x003438e0` calls `_BattleModel::battleFairy(int,String)` at
  `0x001ccdc8`. The request contains only `user_id` and `serial_id`; no BC value, deck id, or cost is sent.
- The battle command contains no BC mutation. Consequently the local server must be authoritative for both the
  check and the debit. A malicious or simply unmodified client can always emit `fairybattle`.
- The response header already has the exact client-consumed state channel:
  `<your_data><bc><current>...<max>...<interval_time>...<last_update_time>...</bc></your_data>`.
  `_BcTagParser` and `_CPlayer::updatePlayerData` update the same status object used by the HUD.
- The active saved deck has a statically closed cost rule: resolve each selected owned-card serial through
  `server/data/game/card-master.json`, sum card `cost`, and require total cost not to exceed
  `playerSave.resources.bc.max`. See `work/deck-builder-save-capture-native-path-card-20260809.md`.

### Still open

The original server's exact debit amount is not carried in the request and is not derivable from the battle command.
The strongest local reconstruction candidate is the saved active deck's summed card cost, capped by current BC, but
that is not yet an accepted original-protocol fact. The exact encrypted failure body/result for insufficient BC is
also not closed. An HTTP-only `409` is not acceptable evidence because the original client expects the encrypted
connect/app response pipeline.

### Minimum implementation/acceptance edge

Implement one configurable server rule only after adopting it explicitly in a BC schema card. The safest local rule
is `cost = active deck cost`; reject before any battle mutation when `bc.current < cost`, and debit BC atomically with
the accepted battle settlement otherwise. The two required flows are:

```text
enough BC -> fairybattle -> current BC decreases exactly once -> battle/result scenes -> saved BC matches header
low BC    -> fairybattle -> no HP/reward/history mutation -> encrypted shortage presentation -> next action proven
```

The shortage candidate must be a response-only experiment. If two candidate bodies produce no new scene, next
route, or log observable, stop and return to the common error/result parser rather than sweeping error values.

## Immediate card, factor-piece, and special-item drops

The native schemas are substantially closed.

`_ExploreTagParser::parse` at `0x002f9a64` accepts these direct exploration branches in addition to normal progress
and currency fields:

```text
user_card
autocomp_card
parts_one
parts_complete
special_item
fairy
rare_fairy
```

This proves that an ordinary exploration step can award a card directly (`user_card`), report automatic composition
(`autocomp_card`), award/complete a factor piece (`parts_one`, `parts_complete`), or award a special item. These are
not restricted to the fairy battle result.

The factor branch embedded in `_BattleResultTagParser::parse` at `0x002f21a0` is:

```xml
<get_item_parts_event>
  <event_id>...</event_id>
  <parts_one>
    <lake_id>...</lake_id>
    <parts>
      <master_card_id>...</master_card_id>
      <parts_num>...</parts_num>
      <parts_have>...</parts_have>
    </parts>
    <user_card>...</user_card> <!-- optional completion award -->
  </parts_one>
</get_item_parts_event>
```

Parser evidence:

- `_GetItemPartsEventTagParser::parse` `0x00300954`: `event_id`, repeated `parts_one`.
- `_PartsOneTagParser::parse` `0x00308ae8`: `lake_id`, `parts`, optional `user_card`.
- `_PartsTagParser::parse` `0x003082e4`: `master_card_id`, `parts_num`, `parts_have`.
- `_SpecialItemTagParser::parse` `0x0030fab4`: `item_id`, `before_count`, `after_count`.
- `layout_battle_result.xml` binds `getItemPartsEvent` to the original `btl_parts_get` presentation.

The immediate card award must use the already accepted `_UserCardTagParser` shape and allocate a unique owned-card
serial before rendering the header. Factor completion must add the completed card at most once and persist the factor
counter in the same atomic save. The exact factor event/lake master values and `autocomp_card` consumer remain a data
frontier; do not invent them inside `server/data/player/`.

## Reward box

### Request path

- `menu/rewardbox`: `_MailBoxModel::rewardbox()` uses connect id `0x40` and no parameters.
- `menu/get_rewards`: `_MailBoxModel::getReward(vector<int>)` uses connect id `0x41` and parameter
  `notice_id`, formatted as a comma-separated list of integer notice ids. The one-item overload delegates to the same
  vector path.
- `_MenuRewardBox::All_Get::exec` uses the same batch claim path; a separate endpoint is not required.

### List and claim schemas

`_RewardBoxListTagParser::parse` (`0x0030d8f4`) parses repeated `rewardbox` plus `message`. Each
`_RewardBoxTagParser::parse` row (`0x0030d304`) has:

```text
id, type, title, card_id, item_id, point, get_num, content, date
```

The row layout is also statically mapped: `id` and `type` are the first two integers, `title` and `content` are
strings, `card_id`, `item_id`, `point`, and `get_num` are integers, and `date` is unsigned. UI function
`_MenuRewardBox::createGotRewordList` at `0x003663e4` dispatches `type=1` through the card manager and `type=2`
through the item manager. Types `3..6` use generic point/currency cells, but their exact semantic enum is not yet
closed and must not be guessed.

`_GetRewardsTagParser::parse` (`0x00300b28`) parses:

```text
success, message, id_list
```

A local claim must therefore validate every requested notice id, apply its card/item/currency mutation, remove only
successfully claimed notices, and return the updated `your_data` header atomically. Duplicate ids and replayed claims
must not duplicate rewards. The first acceptance slice should use one `type=1` card row and one single-id claim;
batch/all-get comes only after that edge is visible and persisted.

## Rare fairies

Rare fairies are a separate, original parser branch rather than an ordinary fairy with only a color flag:

- `_ExploreTagParser::parse` accepts sibling tags `fairy` and `rare_fairy`.
- `_RareFairyTagParser::parse` at `0x0030aa58` accepts
  `serial_id`, `master_boss_id`, `name`, `lv`, `hp`, `hp_max`, `time_limit`, `discoverer_id`, `rare_flg`, and nested
  `attacker_history`.
- The ordinary `_FairyTagParser::parse` at `0x002facf4` has the same core fields plus `event_chara_flg`.
- `layout_exploration_fairy.xml` contains distinct `rare_fairy_encount`, `rare_fairy_stay`, and
  `disable_rare_fairy` behaviors, and the rare encounter drives the bundled `rare_boss_appear` action.

The minimum rare-fairy implementation is therefore a second encounter outcome that renders `<rare_fairy>` with the
closed schema and a resource-backed `master_boss_id`. It must not overload the accepted `<fairy>` branch. Acceptance
requires the rare appearance animation/screenshot and the next `fairybattle(user_id,serial_id)` request. Rarity rate,
level multiplier, HP multiplier, attack multiplier, and reward multiplier should be runtime-admin settings sampled
when the encounter is created, just like the accepted ordinary-fairy snapshot.

## LAN co-operation and attacker history

The client has a real shared-fairy path, but this is larger than adding an `attackers` array to the current one-save
settlement:

- `menu/fairyselect` uses `_FairyModel::selection()` connect id `0x3c`.
- `_FairySelectTagParser::parse` exposes `fairy_event`, `message`, and `remaining_rewards`.
- `_FairyEventTagParser::parse` exposes `user`, `fairy`, `put_down`, `start_time`, and `reward_status`.
- `exploration/fairy_floor` takes `serial_id`, `user_id`, and `check`.
- `exploration/fairyhistory` takes `user_id` and `serial_id`.
- `exploration/fairy_lose` takes `serial_id` and `user_id`; the resulting fairy layout plays
  `request_assist`, which is a visual action, not a separate proven HTTP endpoint.
- `_AttackerHistoryTagParser::parse` contains repeated `attacker`. `_AttackerTagParser::parse` rows contain
  `user_id`, `discoverer`, `user_name`, `attack_point`, `attack_times`, `country_id`, `status_friend`, `status_yell`,
  and nested `leader_card`.
- `_BattleBattleTagParser::parse` accepts `battle_player_list`, `battle_support`, `battle_action_list`, `back_id`,
  and `bgm_name`; `_BattleSupportTagParser::parse` contains nested `user_info` and `support_type`.

For a LAN-only restoration the server needs a shared fairy registry keyed by `(discoverer_user_id, serial_id)`, not
the current per-save `battle.fairy.active` object alone. Each attack must lock that registry row, subtract damage
once, append/update the participant's attacker row, and then settle discoverer/participant rewards idempotently.
`fairyselect`, `fairy_floor`, `fairyhistory`, and `fairy_lose` should be restored in that order. Multi-user testing is
blocked until the local account/save selector can produce at least two distinct users; faking two attackers inside
one save would exercise rendering but would not accept collaboration semantics.

## Recommended implementation order

1. Refresh or re-fetch the defeated FairyModel after the accepted result so the old `6000/6000` snapshot and replay
   button cannot survive settlement.
2. Add server-authoritative BC debit and one encrypted BC-shortage response experiment, with separate enough/low-BC
   flows.
3. Add the rare-fairy sibling branch and its admin probability/strength/reward controls.
4. Add one deterministic factor-piece drop and then the completion `user_card` edge; add direct card drops only after
   unique serial/idempotency checks are shared.
5. Restore one-card reward-box list and single claim, then item/currency and all-get.
6. Add a two-user LAN registry and shared-fairy selection/history/lose paths; only then call the feature multiplayer.

This order keeps every slice observable and prevents reward duplication or shared-fairy races from being hidden
behind the already accepted visual battle path.
